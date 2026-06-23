import Foundation

final class OrchestratorSettingsStore: OrchestratorSettingsLoading {
    static let defaultFileName = "OrchestratorSettings.json"

    static var defaultStore: OrchestratorSettingsStore {
        OrchestratorSettingsStore(fileURL: defaultFileURL())
    }

    let fileURL: URL

    private let fileStore: JSONFileStore<OrchestratorSettings>

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileStore = JSONFileStore(fileURL: fileURL, fileManager: fileManager)
    }

    func loadSettings() throws -> OrchestratorSettings {
        guard fileStore.fileExists else {
            let settings = OrchestratorSettings()
            try saveSettings(settings)
            return settings
        }

        return try fileStore.loadIfPresent() ?? OrchestratorSettings()
    }

    func saveSettings(_ settings: OrchestratorSettings) throws {
        try fileStore.save(
            OrchestratorSettings(
                id: settings.id,
                name: settings.name,
                description: settings.description,
                maximumSelectedAgents: settings.maximumSelectedAgents
            )
        )
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        ApplicationSupportPaths(fileManager: fileManager).fileURL(named: defaultFileName)
    }
}
