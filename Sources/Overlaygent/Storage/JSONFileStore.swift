import Foundation

struct JSONFileStore<Value: Codable> {
    let fileURL: URL

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileURL: URL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    var fileExists: Bool {
        fileManager.fileExists(atPath: fileURL.path)
    }

    func loadIfPresent() throws -> Value? {
        guard fileExists else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        guard data.isEmpty == false else {
            return nil
        }

        return try decoder.decode(Value.self, from: data)
    }

    func save(_ value: Value) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let data = try encoder.encode(value)
        try data.write(to: fileURL, options: [.atomic])
    }
}
