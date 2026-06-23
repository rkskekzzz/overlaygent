import Foundation
import XCTest
@testable import Overlaygent

final class AgentMemoryStoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("AgentMemoryStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testLoadMemoryReturnsSensibleDefaultWhenFileIsMissing() throws {
        let store = makeStore()

        let memory = try store.loadMemory()

        XCTAssertEqual(memory.terminologyRules, [])
        XCTAssertEqual(memory.tonePreferences, [])
        XCTAssertEqual(
            memory.writingRules,
            ["Preserve the user's intent and do not add facts."]
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    func testSaveAndLoadMemoryRoundTripsTerminologyToneAndWritingRules() throws {
        let terminologyRule = TerminologyRule(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
            match: "make deploy",
            replacement: "deploy it",
            note: "Prefer natural deploy phrasing.",
            isCaseSensitive: false
        )
        let memory = AgentMemory(
            terminologyRules: [terminologyRule],
            tonePreferences: ["concise", "friendly", "technical"],
            writingRules: [
                "Keep code identifiers unchanged.",
                "Do not add facts that are not in the source text."
            ]
        )
        let store = makeStore()

        try store.saveMemory(memory)

        let reloadedMemory = try AgentMemoryStore(fileURL: store.fileURL).loadMemory()
        XCTAssertEqual(reloadedMemory, memory)
    }

    func testSavedMemoryJSONDoesNotContainConversationHistoryFields() throws {
        let memory = AgentMemory(
            terminologyRules: [],
            tonePreferences: ["polite"],
            writingRules: ["Keep private context out of persistent memory."]
        )
        let store = makeStore()

        try store.saveMemory(memory)

        let data = try Data(contentsOf: store.fileURL)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("conversation"))
        XCTAssertFalse(json.contains("visibleMessages"))
        XCTAssertFalse(json.contains("messages"))
    }

    func testDefaultFileURLUsesApplicationSupportOverlaygentDirectory() {
        let fileURL = AgentMemoryStore.defaultFileURL()

        XCTAssertEqual(fileURL.lastPathComponent, AgentMemoryStore.defaultFileName)
        XCTAssertEqual(fileURL.deletingLastPathComponent().lastPathComponent, "Overlaygent")
    }

    private func makeStore(fileName: String = AgentMemoryStore.defaultFileName) -> AgentMemoryStore {
        AgentMemoryStore(
            fileURL: temporaryDirectory.appendingPathComponent(fileName, isDirectory: false)
        )
    }
}
