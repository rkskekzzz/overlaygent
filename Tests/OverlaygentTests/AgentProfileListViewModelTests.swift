import XCTest
@testable import Overlaygent

@MainActor
final class AgentProfileListViewModelTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentProfileListViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testLoadsProvidersAndOrchestratorSettingsForAgentDashboard() throws {
        let stores = try makeStores()
        let firstProvider = provider(idSuffix: "101", name: "Fast")
        let secondProvider = provider(idSuffix: "102", name: "Careful")
        let orchestratorSettings = OrchestratorSettings(
            name: "Root Router",
            description: "Selects agents.",
            maximumSelectedAgents: 3
        )

        try stores.providerStore.saveProviders([firstProvider, secondProvider])
        try stores.orchestratorStore.saveSettings(orchestratorSettings)

        let viewModel = AgentProfileListViewModel(
            store: stores.agentStore,
            providerStore: stores.providerStore,
            orchestratorSettingsStore: stores.orchestratorStore
        )

        XCTAssertEqual(viewModel.providers, [firstProvider, secondProvider])
        XCTAssertEqual(viewModel.orchestratorSettings, orchestratorSettings)
        XCTAssertEqual(viewModel.selection, .agent(viewModel.profiles[0].id))
    }

    func testCreateProfileUsesFirstConfiguredProvider() throws {
        let stores = try makeStores()
        let firstProvider = provider(idSuffix: "201", name: "Fast")
        let secondProvider = provider(idSuffix: "202", name: "Careful")
        try stores.providerStore.saveProviders([firstProvider, secondProvider])
        try stores.agentStore.saveProfiles([])

        let viewModel = AgentProfileListViewModel(
            store: stores.agentStore,
            providerStore: stores.providerStore,
            orchestratorSettingsStore: stores.orchestratorStore
        )

        viewModel.createProfile()

        XCTAssertEqual(viewModel.profiles.first?.providerID, firstProvider.id)
        XCTAssertEqual(viewModel.selection, viewModel.profiles.first.map { .agent($0.id) })
    }

    func testOrchestratorSettingsBindingPersistsChanges() throws {
        let stores = try makeStores()
        let viewModel = AgentProfileListViewModel(
            store: stores.agentStore,
            providerStore: stores.providerStore,
            orchestratorSettingsStore: stores.orchestratorStore
        )

        var updatedSettings = viewModel.orchestratorSettingsBinding.wrappedValue
        updatedSettings.name = "Operator"
        updatedSettings.maximumSelectedAgents = 3
        viewModel.orchestratorSettingsBinding.wrappedValue = updatedSettings

        XCTAssertEqual(try stores.orchestratorStore.loadSettings().name, "Operator")
        XCTAssertEqual(try stores.orchestratorStore.loadSettings().maximumSelectedAgents, 3)
    }

    func testMovingProfilesUpdatesPublishedAndPersistedOrder() throws {
        let stores = try makeStores()
        let viewModel = AgentProfileListViewModel(
            store: stores.agentStore,
            providerStore: stores.providerStore,
            orchestratorSettingsStore: stores.orchestratorStore
        )
        let grammarID = viewModel.profiles[0].id
        let naturalID = viewModel.profiles[1].id

        XCTAssertFalse(viewModel.canMoveProfileUp(id: grammarID))
        XCTAssertTrue(viewModel.canMoveProfileDown(id: grammarID))

        viewModel.moveProfileDown(id: grammarID)

        XCTAssertEqual(Array(viewModel.profiles.map(\.id).prefix(2)), [naturalID, grammarID])
        XCTAssertEqual(try stores.agentStore.loadProfiles().map(\.id), viewModel.profiles.map(\.id))
        XCTAssertTrue(viewModel.canMoveProfileUp(id: grammarID))

        viewModel.moveProfileUp(id: grammarID)

        XCTAssertEqual(Array(viewModel.profiles.map(\.id).prefix(2)), [grammarID, naturalID])
        XCTAssertEqual(try stores.agentStore.loadProfiles().map(\.id), viewModel.profiles.map(\.id))
    }

    private func makeStores() throws -> (
        agentStore: AgentProfileStore,
        providerStore: LLMProviderStore,
        orchestratorStore: OrchestratorSettingsStore
    ) {
        let agentStore = AgentProfileStore(
            fileURL: temporaryDirectory.appendingPathComponent(AgentProfileStore.defaultFileName)
        )
        let providerStore = LLMProviderStore(
            fileURL: temporaryDirectory.appendingPathComponent("providers.json")
        )
        let orchestratorStore = OrchestratorSettingsStore(
            fileURL: temporaryDirectory.appendingPathComponent(OrchestratorSettingsStore.defaultFileName)
        )
        _ = try agentStore.loadProfiles()
        return (agentStore, providerStore, orchestratorStore)
    }

    private func provider(
        idSuffix: String,
        name: String
    ) -> LLMProviderConfig {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000\(idSuffix)")!
        return LLMProviderConfig.defaultOpenAICompatible(
            id: id,
            name: name,
            defaultModel: "model-\(idSuffix)"
        )
    }
}
