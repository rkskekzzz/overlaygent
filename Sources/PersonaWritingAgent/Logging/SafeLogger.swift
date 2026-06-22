import Foundation

struct SafeLogger {
    static let `default` = SafeLogger()

    private let redactionRules: [String]
    private let sink: (String) -> Void

    init(
        redactionRules: [String] = [],
        sink: @escaping (String) -> Void = { NSLog("%@", $0) }
    ) {
        self.redactionRules = redactionRules
        self.sink = sink
    }

    func log(_ message: String) {
        sink(Self.redacted(message, redactionRules: redactionRules))
    }

    static func redacted(_ message: String, redactionRules: [String] = []) -> String {
        ContextRedactor(redactionRules: redactionRules).redact(message)
    }
}
