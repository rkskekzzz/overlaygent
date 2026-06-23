import Foundation

protocol LLMProviderModelListing {
    func listModels(
        provider: LLMProviderConfig,
        apiKey: String?
    ) async throws -> [String]
}

struct OpenAICompatibleModelLister: LLMProviderModelListing {
    private let httpClient: any LLMProviderHTTPClient
    private let decoder: JSONDecoder

    init(
        httpClient: any LLMProviderHTTPClient = URLSessionLLMProviderHTTPClient(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.httpClient = httpClient
        self.decoder = decoder
    }

    func listModels(
        provider: LLMProviderConfig,
        apiKey: String?
    ) async throws -> [String] {
        let normalizedAPIKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard normalizedAPIKey.isEmpty == false else {
            throw LLMProviderError.missingAPIKey
        }

        let endpointURL = try modelListURL(for: provider.baseURL)
        var request = URLRequest(url: endpointURL, timeoutInterval: provider.timeoutSeconds)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(normalizedAPIKey)", forHTTPHeaderField: "Authorization")

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
                message: safeErrorMessage(from: data, redacting: normalizedAPIKey)
            )
        }

        let decodedResponse: OpenAIModelListResponse
        do {
            decodedResponse = try decoder.decode(OpenAIModelListResponse.self, from: data)
        } catch {
            throw LLMProviderError.invalidResponseJSON
        }

        let modelIDs = decodedResponse.data
            .map { $0.id.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        return Array(Set(modelIDs))
            .sorted { lhs, rhs in
                lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
    }

    private func modelListURL(for baseURL: URL) throws -> URL {
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
        components.path = path + "/models"

        guard let url = components.url else {
            throw LLMProviderError.invalidEndpoint(baseURL.absoluteString)
        }

        return url
    }

    private func safeErrorMessage(from data: Data, redacting apiKey: String) -> String? {
        guard data.isEmpty == false else {
            return nil
        }

        let decodedMessage = try? decoder.decode(OpenAIModelListErrorResponse.self, from: data).messageText
        guard let decodedMessage, decodedMessage.isEmpty == false else {
            return nil
        }

        let redactedMessage = SafeLogger.redacted(decodedMessage, redactionRules: [apiKey])
        let collapsedMessage = redactedMessage
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
        return String(collapsedMessage.prefix(320))
    }
}

private struct OpenAIModelListResponse: Decodable {
    struct Model: Decodable {
        var id: String
    }

    var data: [Model]
}

private struct OpenAIModelListErrorResponse: Decodable {
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
