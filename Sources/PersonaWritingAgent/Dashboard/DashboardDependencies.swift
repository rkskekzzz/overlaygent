struct DashboardDependencies {
    var agentProfileStore: AgentProfileStore
    var llmProviderStore: LLMProviderStore
    var orchestratorSettingsStore: OrchestratorSettingsStore
    var apiKeyStore: any LLMProviderAPIKeyStoring

    static var live: DashboardDependencies {
        DashboardDependencies(
            agentProfileStore: .defaultStore,
            llmProviderStore: LLMProviderStore(),
            orchestratorSettingsStore: .defaultStore,
            apiKeyStore: KeychainStore()
        )
    }
}
