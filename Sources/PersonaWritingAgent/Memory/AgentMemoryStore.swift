import Foundation

struct AgentMemoryStore {
    static let defaultFileName = "agent-memory.json"

    static var defaultStore: AgentMemoryStore {
        AgentMemoryStore(fileURL: defaultFileURL())
    }

    let fileURL: URL

    private let fileStore: JSONFileStore<AgentMemory>

    init(
        fileURL: URL = AgentMemoryStore.defaultFileURL(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileStore = JSONFileStore(fileURL: fileURL, fileManager: fileManager)
    }

    func loadMemory() throws -> AgentMemory {
        try fileStore.loadIfPresent() ?? Self.defaultMemory()
    }

    func saveMemory(_ memory: AgentMemory) throws {
        try fileStore.save(memory)
    }

    static func defaultMemory() -> AgentMemory {
        AgentMemory(
            terminologyRules: [],
            tonePreferences: [],
            writingRules: [
                "Preserve the user's intent and do not add facts."
            ]
        )
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        ApplicationSupportPaths(fileManager: fileManager).fileURL(named: defaultFileName)
    }
}
