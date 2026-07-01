import Foundation

struct ChatGPTSubscriptionProvider: LLMProvider {
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
        guard case let .chatGPTSubscription(accessToken, accountID) = credential,
              accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw LLMProviderError.unsupportedCredential
        }

        let model = normalizedModel(for: bundle, provider: provider)
        guard model.isEmpty == false else {
            throw LLMProviderError.missingModel
        }

        let request = try makeRequest(
            bundle: bundle,
            provider: provider,
            model: model,
            accessToken: accessToken.trimmingCharacters(in: .whitespacesAndNewlines),
            accountID: accountID.trimmingCharacters(in: .whitespacesAndNewlines)
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

        guard let content = decodedResponseText(from: data), content.isEmpty == false else {
            throw LLMProviderError.emptyContent
        }

        return content
    }

    private func makeRequest(
        bundle: AgentMessageBundle,
        provider: LLMProviderConfig,
        model: String,
        accessToken: String,
        accountID: String
    ) throws -> URLRequest {
        let endpointURL = try responsesURL(for: provider.baseURL)
        let payload = ChatGPTCodexResponsesRequest(
            model: model,
            input: bundle.messages.map { message in
                ChatGPTCodexResponsesRequest.InputMessage(
                    role: message.role.responsesRole,
                    content: [
                        ChatGPTCodexResponsesRequest.InputContent(
                            type: "input_text",
                            text: message.content
                        )
                    ]
                )
            },
            temperature: provider.temperature,
            reasoning: provider.reasoningEffort.map {
                ChatGPTCodexResponsesRequest.Reasoning(effort: $0.rawValue)
            },
            maxOutputTokens: provider.maxTokens,
            text: ChatGPTCodexResponsesRequest.TextConfig(
                format: OpenAIResponseFormat.correctionResult
            ),
            store: false,
            stream: false
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
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id")
        request.setValue("responses=experimental", forHTTPHeaderField: "OpenAI-Beta")

        for (name, value) in provider.endpoint.extraHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }

        return request
    }

    private func responsesURL(for baseURL: URL) throws -> URL {
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
        if path.hasSuffix("/responses") == false {
            path += "/responses"
        }
        components.path = path

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

    private func decodedResponseText(from data: Data) -> String? {
        if let decoded = try? decoder.decode(ChatGPTCodexResponsesResponse.self, from: data) {
            if let outputText = decoded.outputText?.trimmingCharacters(in: .whitespacesAndNewlines),
               outputText.isEmpty == false {
                return outputText
            }

            let text = (decoded.output ?? [])
                .flatMap(\.content)
                .compactMap(\.text)
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty == false {
                return text
            }
        }

        return nil
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

private extension AgentMessageRole {
    var responsesRole: String {
        switch self {
        case .system, .developer:
            return "system"
        case .user:
            return "user"
        }
    }
}

private struct ChatGPTCodexResponsesRequest: Encodable {
    struct InputMessage: Encodable {
        var role: String
        var content: [InputContent]
    }

    struct InputContent: Encodable {
        var type: String
        var text: String
    }

    struct Reasoning: Encodable {
        var effort: String
    }

    struct TextConfig: Encodable {
        var format: OpenAIResponseFormat
    }

    var model: String
    var input: [InputMessage]
    var temperature: Double
    var reasoning: Reasoning?
    var maxOutputTokens: Int
    var text: TextConfig
    var store: Bool
    var stream: Bool

    private enum CodingKeys: String, CodingKey {
        case model
        case input
        case temperature
        case reasoning
        case maxOutputTokens = "max_output_tokens"
        case text
        case store
        case stream
    }
}

private struct ChatGPTCodexResponsesResponse: Decodable {
    struct OutputItem: Decodable {
        var content: [ContentItem]
    }

    struct ContentItem: Decodable {
        var text: String?
    }

    var outputText: String?
    var output: [OutputItem]?

    private enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }
}
