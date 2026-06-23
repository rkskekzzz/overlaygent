import Foundation
import XCTest
@testable import Overlaygent

final class LLMProviderStoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("LLMProviderStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testLoadProvidersReturnsEmptyArrayWhenFileIsMissing() throws {
        let store = makeStore()

        XCTAssertEqual(try store.loadProviders(), [])
    }

    func testSaveAndLoadProvidersRoundTripJSON() throws {
        let provider = LLMProviderConfig.defaultOpenAICompatible(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            name: "Local Gateway",
            baseURL: URL(string: "http://localhost:11434/v1")!,
            defaultModel: "llama-3.1",
            temperature: 0.7,
            maxTokens: 900,
            timeoutSeconds: 12
        )
        let store = makeStore()

        try store.saveProviders([provider])

        XCTAssertEqual(try store.loadProviders(), [provider])
    }

    func testLoadOrCreateDefaultProvidersPersistsDefaultProvider() throws {
        let store = makeStore()

        let providers = try store.loadOrCreateDefaultProviders()

        XCTAssertEqual(providers.count, 1)
        XCTAssertEqual(providers.first?.id, AgentProfileStore.defaultProviderID)
        XCTAssertEqual(providers.first?.name, "OpenAI Compatible")
        XCTAssertEqual(providers.first?.baseURL, URL(string: "https://api.openai.com/v1"))
        XCTAssertEqual(try store.loadProviders(), providers)
    }

    func testSeededDefaultProviderMatchesDefaultAgentProviderID() throws {
        let providerStore = makeStore()
        let agentStore = AgentProfileStore(
            fileURL: temporaryDirectory.appendingPathComponent("AgentProfiles.json", isDirectory: false)
        )

        let providers = try providerStore.loadOrCreateDefaultProviders()
        let agents = try agentStore.loadProfiles()

        XCTAssertEqual(Set(providers.map(\.id)), [AgentProfileStore.defaultProviderID])
        XCTAssertTrue(agents.allSatisfy { $0.providerID == AgentProfileStore.defaultProviderID })
    }

    func testSeededConfigLoaderCreatesDefaultProviderForRuntimeLoads() throws {
        let store = makeStore()
        let loader = SeededLLMProviderConfigLoader(providerStore: store)

        let providers = try loader.loadProviders()

        XCTAssertEqual(providers.count, 1)
        XCTAssertEqual(providers.first?.id, AgentProfileStore.defaultProviderID)
        XCTAssertEqual(try store.loadProviders(), providers)
    }

    func testSavedJSONDoesNotContainPlaintextAPIKeyField() throws {
        let provider = LLMProviderConfig.defaultOpenAICompatible(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        )
        let store = makeStore()

        try store.saveProviders([provider])

        let data = try Data(contentsOf: store.fileURL)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("apiKey"))
        XCTAssertFalse(json.contains("api_key"))
    }

    func testDefaultProviderUsesStableKeychainServicePrefix() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
        let provider = LLMProviderConfig.defaultOpenAICompatible(id: id)

        XCTAssertEqual(
            provider.keychainServiceName,
            "Overlaygent.LLMProvider.00000000-0000-0000-0000-000000000103"
        )
    }

    private func makeStore(fileName: String = "llm-providers.json") -> LLMProviderStore {
        LLMProviderStore(
            fileURL: temporaryDirectory.appendingPathComponent(fileName, isDirectory: false)
        )
    }
}
