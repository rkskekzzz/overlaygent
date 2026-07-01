import Foundation

struct ChatGPTSubscriptionModelLister: LLMProviderModelListing {
    private let httpClient: any LLMProviderHTTPClient
    private let decoder: JSONDecoder
    private let clientVersion: String

    init(
        httpClient: any LLMProviderHTTPClient = URLSessionLLMProviderHTTPClient(),
        decoder: JSONDecoder = JSONDecoder(),
        clientVersion: String = "overlaygent"
    ) {
        self.httpClient = httpClient
        self.decoder = decoder
        self.clientVersion = clientVersion
    }

    func listModels(
        provider: LLMProviderConfig,
        credential: LLMCredential
    ) async throws -> [String] {
        guard case let .chatGPTSubscription(accessToken, accountID) = credential,
              accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw LLMProviderError.unsupportedCredential
        }

        let endpointURL = try modelListURL(for: provider.baseURL)
        var request = URLRequest(url: endpointURL, timeoutInterval: provider.timeoutSeconds)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id")
        request.setValue("responses=experimental", forHTTPHeaderField: "OpenAI-Beta")

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

        if let codexResponse = try? decoder.decode(ChatGPTCodexModelListResponse.self, from: data),
           codexResponse.models.isEmpty == false {
            return sortedUnique(codexResponse.models.map(\.slug))
        }

        if let openAIResponse = try? decoder.decode(OpenAIModelListCompatibleResponse.self, from: data),
           openAIResponse.data.isEmpty == false {
            return sortedUnique(openAIResponse.data.map(\.id))
        }

        throw LLMProviderError.invalidResponseJSON
    }

    private func modelListURL(for baseURL: URL) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              components.scheme?.isEmpty == false,
              components.host?.isEmpty == false else {
            throw LLMProviderError.invalidEndpoint(baseURL.absoluteString)
        }

        components.fragment = nil
        var path = components.path
        while path.hasSuffix("/") {
            path.removeLast()
        }
        if path.hasSuffix("/models") == false {
            path += "/models"
        }
        components.path = path
        components.queryItems = [
            URLQueryItem(name: "client_version", value: clientVersion)
        ]

        guard let url = components.url else {
            throw LLMProviderError.invalidEndpoint(baseURL.absoluteString)
        }

        return url
    }

    private func sortedUnique(_ modelIDs: [String]) -> [String] {
        Array(
            Set(
                modelIDs
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.isEmpty == false }
            )
        )
        .sorted { lhs, rhs in
            lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
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

private struct ChatGPTCodexModelListResponse: Decodable {
    struct Model: Decodable {
        var slug: String
    }

    var models: [Model]
}

private struct OpenAIModelListCompatibleResponse: Decodable {
    struct Model: Decodable {
        var id: String
    }

    var data: [Model]
}

struct LLMProviderModelListerRouter: LLMProviderModelListing {
    var openAICompatible: OpenAICompatibleModelLister
    var chatGPTSubscription: ChatGPTSubscriptionModelLister

    init(
        openAICompatible: OpenAICompatibleModelLister = OpenAICompatibleModelLister(),
        chatGPTSubscription: ChatGPTSubscriptionModelLister = ChatGPTSubscriptionModelLister()
    ) {
        self.openAICompatible = openAICompatible
        self.chatGPTSubscription = chatGPTSubscription
    }

    func listModels(
        provider: LLMProviderConfig,
        credential: LLMCredential
    ) async throws -> [String] {
        switch provider.kind {
        case .chatGPTSubscription:
            return try await chatGPTSubscription.listModels(provider: provider, credential: credential)
        case .openAICompatibleAPI, .localOpenAICompatible:
            return try await openAICompatible.listModels(provider: provider, credential: credential)
        }
    }
}
