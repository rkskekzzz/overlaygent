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
            baseURL: baseURL,
            defaultModel: defaultModel,
            reasoningEffort: reasoningEffort,
            temperature: temperature,
            maxTokens: maxTokens,
            timeoutSeconds: timeoutSeconds,
            keychainServiceName: "PersonaWritingAgent.LLMProvider.\(id.uuidString)"
        )
    }
}
