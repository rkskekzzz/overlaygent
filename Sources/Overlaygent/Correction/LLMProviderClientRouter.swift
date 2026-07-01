import Foundation

struct LLMProviderClientRouter: LLMProvider {
    var openAICompatible: OpenAICompatibleProvider
    var chatGPTSubscription: ChatGPTSubscriptionProvider

    init(
        openAICompatible: OpenAICompatibleProvider = OpenAICompatibleProvider(),
        chatGPTSubscription: ChatGPTSubscriptionProvider = ChatGPTSubscriptionProvider()
    ) {
        self.openAICompatible = openAICompatible
        self.chatGPTSubscription = chatGPTSubscription
    }

    func complete(
        bundle: AgentMessageBundle,
        provider: LLMProviderConfig,
        credential: LLMCredential
    ) async throws -> String {
        switch provider.kind {
        case .chatGPTSubscription:
            return try await chatGPTSubscription.complete(
                bundle: bundle,
                provider: provider,
                credential: credential
            )
        case .openAICompatibleAPI, .localOpenAICompatible:
            return try await openAICompatible.complete(
                bundle: bundle,
                provider: provider,
                credential: credential
            )
        }
    }
}
