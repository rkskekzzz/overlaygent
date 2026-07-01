import Foundation

protocol LLMProviderCredentialResolving {
    func credential(for provider: LLMProviderConfig) async throws -> LLMCredential
}

enum LLMProviderCredentialError: Error, Equatable, LocalizedError {
    case missingCredential(mode: LLMProviderAuthMode)
    case unsupportedAuthMode(LLMProviderAuthMode)

    var errorDescription: String? {
        switch self {
        case .missingCredential(let mode):
            return "Missing credential for auth mode \(mode.rawValue)."
        case .unsupportedAuthMode(let mode):
            return "Unsupported auth mode \(mode.rawValue)."
        }
    }
}

struct ChatGPTSubscriptionCredential: Codable, Equatable {
    var accessToken: String
    var accountID: String
    var expiresAt: Date?
    var sourceDescription: String?

    var isUsable: Bool {
        accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && isExpired == false
    }

    var isExpired: Bool {
        guard let expiresAt else {
            return false
        }

        return expiresAt <= Date().addingTimeInterval(60)
    }
}

protocol ChatGPTSubscriptionCredentialStoring {
    func saveChatGPTSubscriptionCredential(
        _ credential: ChatGPTSubscriptionCredential,
        for provider: LLMProviderConfig
    ) throws

    func readChatGPTSubscriptionCredential(
        for provider: LLMProviderConfig
    ) throws -> ChatGPTSubscriptionCredential?

    func deleteChatGPTSubscriptionCredential(for provider: LLMProviderConfig) throws
}

struct DefaultLLMProviderCredentialResolver: LLMProviderCredentialResolving {
    private let apiKeyStore: any LLMProviderAPIKeyStoring
    private let chatGPTCredentialStore: any ChatGPTSubscriptionCredentialStoring

    init(
        apiKeyStore: any LLMProviderAPIKeyStoring,
        chatGPTCredentialStore: any ChatGPTSubscriptionCredentialStoring
    ) {
        self.apiKeyStore = apiKeyStore
        self.chatGPTCredentialStore = chatGPTCredentialStore
    }

    func credential(for provider: LLMProviderConfig) async throws -> LLMCredential {
        switch provider.auth.mode {
        case .apiKey:
            let apiKey = try apiKeyStore.readAPIKey(for: provider)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard apiKey.isEmpty == false else {
                throw LLMProviderCredentialError.missingCredential(mode: .apiKey)
            }
            return .apiKey(apiKey)

        case .subscriptionOAuth:
            guard provider.auth.subscriptionService == .chatGPT else {
                throw LLMProviderCredentialError.unsupportedAuthMode(.subscriptionOAuth)
            }

            guard let credential = try chatGPTCredentialStore.readChatGPTSubscriptionCredential(for: provider),
                  credential.isUsable else {
                throw LLMProviderCredentialError.missingCredential(mode: .subscriptionOAuth)
            }

            return .chatGPTSubscription(
                accessToken: credential.accessToken.trimmingCharacters(in: .whitespacesAndNewlines),
                accountID: credential.accountID.trimmingCharacters(in: .whitespacesAndNewlines)
            )

        case .bearerTokenCommand:
            throw LLMProviderCredentialError.unsupportedAuthMode(.bearerTokenCommand)

        case .none:
            return .none
        }
    }
}

struct NoopChatGPTSubscriptionCredentialStore: ChatGPTSubscriptionCredentialStoring {
    func saveChatGPTSubscriptionCredential(
        _ credential: ChatGPTSubscriptionCredential,
        for provider: LLMProviderConfig
    ) throws {}

    func readChatGPTSubscriptionCredential(
        for provider: LLMProviderConfig
    ) throws -> ChatGPTSubscriptionCredential? {
        nil
    }

    func deleteChatGPTSubscriptionCredential(for provider: LLMProviderConfig) throws {}
}
