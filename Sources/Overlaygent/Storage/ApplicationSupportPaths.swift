import Foundation

struct ApplicationSupportPaths {
    static let appDirectoryName = "Overlaygent"

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func fileURL(named fileName: String) -> URL {
        applicationSupportDirectoryURL()
            .appendingPathComponent(Self.appDirectoryName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private func applicationSupportDirectoryURL() -> URL {
        fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }
}
