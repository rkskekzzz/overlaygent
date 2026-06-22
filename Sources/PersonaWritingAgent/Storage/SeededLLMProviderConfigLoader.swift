import Foundation

struct SeededLLMProviderConfigLoader: LLMProviderConfigLoading {
    private let providerStore: LLMProviderStore

    init(providerStore: LLMProviderStore) {
        self.providerStore = providerStore
    }

    func loadProviders() throws -> [LLMProviderConfig] {
        try providerStore.loadOrCreateDefaultProviders()
    }
}
