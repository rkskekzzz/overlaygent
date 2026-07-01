import Foundation

protocol LLMProvider {
    func complete(
        bundle: AgentMessageBundle,
        provider: LLMProviderConfig,
        credential: LLMCredential
    ) async throws -> String
}

enum LLMCredential: Equatable {
    case apiKey(String)
    case chatGPTSubscription(accessToken: String, accountID: String)
    case bearerToken(String)
    case none

    var redactionRules: [String] {
        switch self {
        case .apiKey(let value), .bearerToken(let value):
            return value.isEmpty ? [] : [value]
        case let .chatGPTSubscription(accessToken, accountID):
            return [accessToken, accountID].filter { $0.isEmpty == false }
        case .none:
            return []
        }
    }
}

protocol LLMProviderHTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionLLMProviderHTTPClient: LLMProviderHTTPClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidHTTPResponse
        }

        return (data, httpResponse)
    }
}

enum LLMProviderError: Error, Equatable, LocalizedError, CustomStringConvertible {
    case missingAPIKey
    case missingCredential
    case missingModel
    case unsupportedProvider
    case unsupportedCredential
    case invalidEndpoint(String)
    case invalidRequestBody
    case invalidHTTPResponse
    case transportFailed
    case httpStatus(Int, message: String?)
    case invalidResponseJSON
    case emptyChoices
    case emptyContent

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "LLM provider API key is missing."
        case .missingCredential:
            return "LLM provider credential is missing."
        case .missingModel:
            return "LLM provider model is missing."
        case .unsupportedProvider:
            return "LLM provider type is not supported by this client."
        case .unsupportedCredential:
            return "LLM provider credential type is not supported by this client."
        case .invalidEndpoint(let baseURL):
            return "LLM provider base URL is invalid: \(baseURL)"
        case .invalidRequestBody:
            return "LLM provider request body could not be encoded."
        case .invalidHTTPResponse:
            return "LLM provider returned a non-HTTP response."
        case .transportFailed:
            return "LLM provider request failed before receiving a response."
        case let .httpStatus(statusCode, message):
            if let message, message.isEmpty == false {
                return "LLM provider returned HTTP status \(statusCode): \(message)"
            }
            return "LLM provider returned HTTP status \(statusCode)."
        case .invalidResponseJSON:
            return "LLM provider response JSON is invalid."
        case .emptyChoices:
            return "LLM provider response did not include any choices."
        case .emptyContent:
            return "LLM provider response did not include assistant content."
        }
    }

    var description: String {
        errorDescription ?? "LLM provider error."
    }
}
