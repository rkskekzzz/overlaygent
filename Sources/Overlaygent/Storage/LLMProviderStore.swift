import Foundation

struct LLMProviderStore {
    let fileURL: URL

    private let fileStore: JSONFileStore<[LLMProviderConfig]>

    init(
        fileURL: URL = LLMProviderStore.defaultFileURL(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileStore = JSONFileStore(fileURL: fileURL, fileManager: fileManager)
    }

    func loadProviders() throws -> [LLMProviderConfig] {
        try fileStore.loadIfPresent() ?? []
    }

    func loadOrCreateDefaultProviders() throws -> [LLMProviderConfig] {
        let storedProviders = try loadProviders()
        guard storedProviders.isEmpty else {
            return storedProviders
        }

        let defaultProvider = LLMProviderConfig.defaultOpenAICompatible(id: DefaultSeedConfiguration.providerID)
        try saveProviders([defaultProvider])
        return [defaultProvider]
    }

    func saveProviders(_ providers: [LLMProviderConfig]) throws {
        try fileStore.save(providers)
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        ApplicationSupportPaths(fileManager: fileManager).fileURL(named: "llm-providers.json")
    }
}

extension LLMProviderConfig {
    static func defaultOpenAICompatible(
        id: UUID = UUID(),
        name: String = "OpenAI Compatible",
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        defaultModel: String = "gpt-4.1-mini",
        reasoningEffort: ReasoningEffort? = nil,
        temperature: Double = 0.2,
        maxTokens: Int = 1_200,
        timeoutSeconds: Double = 30
    ) -> LLMProviderConfig {
        LLMProviderConfig(
            id: id,
            name: name,
            category: .api,
            kind: .openAICompatibleAPI,
            baseURL: baseURL,
            defaultModel: defaultModel,
            reasoningEffort: reasoningEffort,
            temperature: temperature,
            maxTokens: maxTokens,
            timeoutSeconds: timeoutSeconds,
            keychainServiceName: "Overlaygent.LLMProvider.\(id.uuidString)"
        )
    }

    static func defaultChatGPTSubscription(
        id: UUID = UUID(),
        name: String = "ChatGPT Subscription",
        baseURL: URL = URL(string: "https://chatgpt.com/backend-api/codex")!,
        defaultModel: String = "gpt-5.2",
        reasoningEffort: ReasoningEffort? = nil,
        temperature: Double = 0.2,
        maxTokens: Int = 1_200,
        timeoutSeconds: Double = 30
    ) -> LLMProviderConfig {
        LLMProviderConfig(
            id: id,
            name: name,
            category: .subscription,
            kind: .chatGPTSubscription,
            endpoint: LLMProviderEndpointConfig(
                baseURL: baseURL,
                wireAPI: .codexBackendResponses,
                extraHeaders: [:]
            ),
            auth: LLMProviderAuthConfig(
                mode: .subscriptionOAuth,
                keychainServiceName: "Overlaygent.ChatGPTSubscription.\(id.uuidString)",
                subscriptionService: .chatGPT,
                profileID: "default",
                credentialCommand: nil
            ),
            baseURL: baseURL,
            defaultModel: defaultModel,
            reasoningEffort: reasoningEffort,
            temperature: temperature,
            maxTokens: maxTokens,
            timeoutSeconds: timeoutSeconds,
            keychainServiceName: "Overlaygent.ChatGPTSubscription.\(id.uuidString)"
        )
    }
}
