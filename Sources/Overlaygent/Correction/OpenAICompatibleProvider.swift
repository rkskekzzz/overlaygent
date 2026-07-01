import Foundation

struct OpenAICompatibleProvider: LLMProvider {
    private let httpClient: any LLMProviderHTTPClient
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        httpClient: any LLMProviderHTTPClient = URLSessionLLMProviderHTTPClient(),
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.httpClient = httpClient
        self.encoder = encoder
        self.decoder = decoder
    }

    func complete(
        bundle: AgentMessageBundle,
        provider: LLMProviderConfig,
        credential: LLMCredential
    ) async throws -> String {
        let bearerToken = try bearerToken(from: credential)
        guard bearerToken.isEmpty == false else {
            throw LLMProviderError.missingCredential
        }

        let model = normalizedModel(for: bundle, provider: provider)
        guard model.isEmpty == false else {
            throw LLMProviderError.missingModel
        }

        let request = try makeRequest(
            bundle: bundle,
            provider: provider,
            model: model,
            bearerToken: bearerToken
        )

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await httpClient.data(for: request)
        } catch let error as LLMProviderError {
            throw error
        } catch {
            throw LLMProviderError.transportFailed
        }

        guard (200...299).contains(response.statusCode) else {
            throw LLMProviderError.httpStatus(
                response.statusCode,
                message: safeErrorMessage(from: data, redactionRules: credential.redactionRules)
            )
        }

        let decodedResponse: OpenAIChatCompletionResponse
        do {
            decodedResponse = try decoder.decode(OpenAIChatCompletionResponse.self, from: data)
        } catch {
            throw LLMProviderError.invalidResponseJSON
        }

        guard let firstChoice = decodedResponse.choices.first else {
            throw LLMProviderError.emptyChoices
        }

        guard let content = firstChoice.message?.content, content.isEmpty == false else {
            throw LLMProviderError.emptyContent
        }

        return content
    }

    private func makeRequest(
        bundle: AgentMessageBundle,
        provider: LLMProviderConfig,
        model: String,
        bearerToken: String
    ) throws -> URLRequest {
        let endpointURL = try chatCompletionsURL(for: provider.baseURL)
        let payload = OpenAIChatCompletionRequest(
            model: model,
            messages: bundle.messages.map { message in
                OpenAIChatCompletionRequest.Message(
                    role: message.role.rawValue,
                    content: message.content
                )
            },
            temperature: provider.temperature,
            reasoningEffort: provider.reasoningEffort,
            maxCompletionTokens: provider.maxTokens,
            responseFormat: .correctionResult
        )

        let body: Data
        do {
            body = try encoder.encode(payload)
        } catch {
            throw LLMProviderError.invalidRequestBody
        }

        var request = URLRequest(url: endpointURL, timeoutInterval: provider.timeoutSeconds)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")

        return request
    }

    private func bearerToken(from credential: LLMCredential) throws -> String {
        switch credential {
        case .apiKey(let apiKey), .bearerToken(let apiKey):
            return apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .chatGPTSubscription, .none:
            throw LLMProviderError.unsupportedCredential
        }
    }

    private func chatCompletionsURL(for baseURL: URL) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              components.scheme?.isEmpty == false,
              components.host?.isEmpty == false else {
            throw LLMProviderError.invalidEndpoint(baseURL.absoluteString)
        }

        components.query = nil
        components.fragment = nil

        var path = components.path
        while path.hasSuffix("/") {
            path.removeLast()
        }
        components.path = path + "/chat/completions"

        guard let url = components.url else {
            throw LLMProviderError.invalidEndpoint(baseURL.absoluteString)
        }

        return url
    }

    private func normalizedModel(
        for bundle: AgentMessageBundle,
        provider: LLMProviderConfig
    ) -> String {
        let resolvedModel = bundle.resolvedModel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if resolvedModel.isEmpty == false {
            return resolvedModel
        }

        return provider.defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func safeErrorMessage(from data: Data, redactionRules: [String]) -> String? {
        guard data.isEmpty == false else {
            return nil
        }

        let decodedMessage = try? decoder.decode(OpenAIErrorResponse.self, from: data).messageText
        guard let decodedMessage, decodedMessage.isEmpty == false else {
            return nil
        }

        let redactedMessage = SafeLogger.redacted(decodedMessage, redactionRules: redactionRules)
        let collapsedMessage = redactedMessage
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
        return String(collapsedMessage.prefix(320))
    }
}

private struct OpenAIChatCompletionRequest: Encodable {
    struct Message: Encodable {
        var role: String
        var content: String
    }

    var model: String
    var messages: [Message]
    var temperature: Double
    var reasoningEffort: ReasoningEffort?
    var maxCompletionTokens: Int
    var responseFormat: OpenAIResponseFormat

    private enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case reasoningEffort = "reasoning_effort"
        case maxCompletionTokens = "max_completion_tokens"
        case responseFormat = "response_format"
    }
}

struct OpenAIResponseFormat: Encodable {
    struct JSONSchemaEnvelope: Encodable {
        var name: String
        var strict: Bool
        var schema: CorrectionResultJSONSchema
    }

    var type: String
    var jsonSchema: JSONSchemaEnvelope

    static let correctionResult = OpenAIResponseFormat(
        type: "json_schema",
        jsonSchema: JSONSchemaEnvelope(
            name: "correction_result",
            strict: true,
            schema: CorrectionResultJSONSchema()
        )
    )

    private enum CodingKeys: String, CodingKey {
        case type
        case jsonSchema = "json_schema"
    }
}

struct CorrectionResultJSONSchema: Encodable {
    struct RootProperties: Encodable {
        var summary = NullableStringSchema()
        var edits = EditArraySchema()
        var fullRewrite = NullableStringSchema()
    }

    struct EditArraySchema: Encodable {
        var type = "array"
        var items = EditItemSchema()
    }

    struct EditItemSchema: Encodable {
        var type = "object"
        var additionalProperties = false
        var required = ["rangeStart", "rangeEnd", "original", "replacement", "reason"]
        var properties = EditProperties()
    }

    struct EditProperties: Encodable {
        var rangeStart = IntegerSchema()
        var rangeEnd = IntegerSchema()
        var original = StringSchema()
        var replacement = StringSchema()
        var reason = StringSchema()
    }

    struct StringSchema: Encodable {
        var type = "string"
    }

    struct IntegerSchema: Encodable {
        var type = "integer"
    }

    struct NullableStringSchema: Encodable {
        var type = ["string", "null"]
    }

    var type = "object"
    var additionalProperties = false
    var required = ["summary", "edits", "fullRewrite"]
    var properties = RootProperties()
}

private struct OpenAIChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: String?
        }

        var message: Message?
    }

    var choices: [Choice]
}

struct OpenAIErrorResponse: Decodable {
    struct ErrorDetail: Decodable {
        var message: String?
    }

    var error: ErrorDetail?
    var topLevelMessage: String?

    private enum CodingKeys: String, CodingKey {
        case error
        case topLevelMessage = "message"
    }

    var messageText: String? {
        error?.message ?? topLevelMessage
    }
}
