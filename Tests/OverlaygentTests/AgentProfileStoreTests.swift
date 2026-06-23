import Foundation
import XCTest
@testable import Overlaygent

final class AgentProfileStoreTests: XCTestCase {
    func testMissingStoreSeedsDefaultAgentsAndPersistsThem() throws {
        let fileURL = try makeTemporaryStoreURL()
        let store = AgentProfileStore(fileURL: fileURL)

        let profiles = try store.loadProfiles()

        XCTAssertEqual(
            profiles.map(\.name),
            ["Grammar Fixer", "Natural English", "Coding Terms", "Tone Polish"]
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let reloadedProfiles = try AgentProfileStore(fileURL: fileURL).loadProfiles()
        XCTAssertEqual(reloadedProfiles, profiles)
    }

    func testDefaultAgentsMatchExpectedPersonaBehavior() {
        let profiles = AgentProfileStore.defaultAgents()

        XCTAssertEqual(profiles.count, 4)
        XCTAssertTrue(profiles.allSatisfy(\.isEnabled))
        XCTAssertEqual(
            profiles.filter(\.isActive).map(\.name),
            ["Grammar Fixer", "Natural English"]
        )

        let codingTerms = profiles.first { $0.name == "Coding Terms" }
        XCTAssertEqual(codingTerms?.tone, .technical)
        XCTAssertEqual(codingTerms?.aggressiveness, .conservative)
        XCTAssertTrue(codingTerms?.instruction.contains("Preserve code identifiers") ?? false)

        let tonePolish = profiles.first { $0.name == "Tone Polish" }
        XCTAssertEqual(tonePolish?.tone, .polite)
        XCTAssertTrue(tonePolish?.instruction.contains("Slack") ?? false)
    }

    func testProfilesPersistAcrossStoreInstances() throws {
        let fileURL = try makeTemporaryStoreURL()
        let store = AgentProfileStore(fileURL: fileURL)
        var profile = AgentProfileStore.newAgent()
        profile.name = "Support Tone"
        profile.instruction = "Make the message concise and kind."
        profile.isActive = true

        try store.saveProfiles([profile])

        let reloadedProfiles = try AgentProfileStore(fileURL: fileURL).loadProfiles()
        XCTAssertEqual(reloadedProfiles, [profile])
    }

    func testSavingProfilesPostsChangeNotification() throws {
        let fileURL = try makeTemporaryStoreURL()
        let store = AgentProfileStore(fileURL: fileURL)
        var observedObjects: [AnyObject] = []
        let observer = NotificationCenter.default.addObserver(
            forName: .overlaygentAgentProfilesDidChange,
            object: nil,
            queue: nil
        ) { notification in
            if let object = notification.object as AnyObject? {
                observedObjects.append(object)
            }
        }
        addTeardownBlock {
            NotificationCenter.default.removeObserver(observer)
        }

        try store.saveProfiles([AgentProfileStore.newAgent()])

        XCTAssertEqual(observedObjects.count, 1)
        XCTAssertTrue(observedObjects.first === store)
    }

    func testDuplicateCreatesInactiveCopyWithNewIdentity() {
        let original = AgentProfileStore.defaultAgents()[0]

        let duplicate = AgentProfileStore.duplicate(original)

        XCTAssertNotEqual(duplicate.id, original.id)
        XCTAssertEqual(duplicate.name, "Grammar Fixer Copy")
        XCTAssertEqual(duplicate.instruction, original.instruction)
        XCTAssertEqual(duplicate.systemPrompt, original.systemPrompt)
        XCTAssertFalse(duplicate.isActive)
    }

    func testResetToDefaultAgentsOverwritesPersistedProfiles() throws {
        let fileURL = try makeTemporaryStoreURL()
        let store = AgentProfileStore(fileURL: fileURL)
        var customProfile = AgentProfileStore.newAgent()
        customProfile.name = "Temporary Agent"
        try store.saveProfiles([customProfile])

        let defaults = try store.resetToDefaultAgents()

        XCTAssertEqual(defaults.map(\.name), ["Grammar Fixer", "Natural English", "Coding Terms", "Tone Polish"])
        XCTAssertEqual(try AgentProfileStore(fileURL: fileURL).loadProfiles(), defaults)
    }

    private func makeTemporaryStoreURL() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OverlaygentTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        return directoryURL.appendingPathComponent(AgentProfileStore.defaultFileName, isDirectory: false)
    }
}
