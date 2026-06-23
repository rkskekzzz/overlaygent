import Foundation

struct BundleIdentifier: Hashable {
    var rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    var trimmed: String {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var lookupKey: String {
        trimmed.lowercased()
    }

    var isEmpty: Bool {
        lookupKey.isEmpty
    }

    func matches(_ other: String) -> Bool {
        lookupKey == Self.lookupKey(for: other)
    }

    static func lookupKey(for rawValue: String) -> String {
        BundleIdentifier(rawValue).lookupKey
    }

    static func lookupKeys(for rawValues: [String]) -> Set<String> {
        Set(rawValues.map(Self.lookupKey).filter { $0.isEmpty == false })
    }
}
