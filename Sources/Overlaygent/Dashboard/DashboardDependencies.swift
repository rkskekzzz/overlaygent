struct DashboardDependencies {
    var agentProfileStore: AgentProfileStore
    var llmProviderStore: LLMProviderStore
    var orchestratorSettingsStore: OrchestratorSettingsStore
    var apiKeyStore: any LLMProviderAPIKeyStoring
    var chatGPTCredentialStore: any ChatGPTSubscriptionCredentialStoring

    static var live: DashboardDependencies {
        let keychainStore = KeychainStore()
        return DashboardDependencies(
            agentProfileStore: .defaultStore,
            llmProviderStore: LLMProviderStore(),
            orchestratorSettingsStore: .defaultStore,
            apiKeyStore: keychainStore,
            chatGPTCredentialStore: keychainStore
        )
    }
}
