protocol LLMProviderAPIKeyStoring {
    func saveAPIKey(_ apiKey: String, for provider: LLMProviderConfig) throws
    func readAPIKey(for provider: LLMProviderConfig) throws -> String?
    func deleteAPIKey(for provider: LLMProviderConfig) throws
}
