import Foundation

protocol LLMProvider {
    func complete(
        bundle: AgentMessageBundle,
        provider: LLMProviderConfig,
        apiKey: String?
    ) async throws -> String
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
    case missingModel
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
        case .missingModel:
            return "LLM provider model is missing."
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
