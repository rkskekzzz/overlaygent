struct DashboardDependencies {
    var agentProfileStore: AgentProfileStore
    var llmProviderStore: LLMProviderStore
    var apiKeyStore: any LLMProviderAPIKeyStoring

    static var live: DashboardDependencies {
        DashboardDependencies(
            agentProfileStore: .defaultStore,
            llmProviderStore: LLMProviderStore(),
            apiKeyStore: KeychainStore()
        )
    }
}
