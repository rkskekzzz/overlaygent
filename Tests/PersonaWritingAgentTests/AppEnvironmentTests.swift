import XCTest
@testable import PersonaWritingAgent

final class AppEnvironmentTests: XCTestCase {
    func testLiveEnvironmentSharesDashboardStoresWithAppStores() throws {
        let environment = AppEnvironment.live()

        XCTAssertTrue(environment.dashboardDependencies.agentProfileStore === environment.agentProfileStore)
        XCTAssertEqual(environment.dashboardDependencies.llmProviderStore.fileURL, environment.llmProviderStore.fileURL)
        XCTAssertEqual(environment.memoryStore.fileURL, AgentMemoryStore.defaultFileURL())

        let appKeychainStore = try XCTUnwrap(environment.apiKeyStore as? KeychainStore)
        let dashboardKeychainStore = try XCTUnwrap(environment.dashboardDependencies.apiKeyStore as? KeychainStore)
        XCTAssertTrue(appKeychainStore === dashboardKeychainStore)
    }
}
