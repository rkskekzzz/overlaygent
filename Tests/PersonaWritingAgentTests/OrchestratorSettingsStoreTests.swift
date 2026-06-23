import Foundation
import XCTest
@testable import PersonaWritingAgent

final class OrchestratorSettingsStoreTests: XCTestCase {
    func testMissingStoreSeedsDefaultSettingsAndPersistsThem() throws {
        let fileURL = try makeTemporaryStoreURL()
        let store = OrchestratorSettingsStore(fileURL: fileURL)

        let settings = try store.loadSettings()

        XCTAssertEqual(settings, OrchestratorSettings())
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(try OrchestratorSettingsStore(fileURL: fileURL).loadSettings(), settings)
    }

    func testSaveSettingsClampsMaximumSelectedAgents() throws {
        let fileURL = try makeTemporaryStoreURL()
        let store = OrchestratorSettingsStore(fileURL: fileURL)
        let settings = OrchestratorSettings(
            name: "Router",
            description: "Routes agent runs.",
            maximumSelectedAgents: 10
        )

        try store.saveSettings(settings)

        XCTAssertEqual(try store.loadSettings().maximumSelectedAgents, 4)
    }

    private func makeTemporaryStoreURL() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrchestratorSettingsStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        return directoryURL.appendingPathComponent(OrchestratorSettingsStore.defaultFileName, isDirectory: false)
    }
}
