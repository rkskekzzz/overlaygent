import Foundation

struct ContextRedactor {
    private let patterns: [RedactionPattern]

    init(redactionRules: [String] = []) {
        self.patterns = Self.makePatterns(redactionRules: redactionRules)
    }

    func redact(_ value: String) -> String {
        patterns.reduce(value) { redactedValue, pattern in
            pattern.redact(redactedValue)
        }
    }

    func redact(_ value: String?) -> String? {
        value.map(redact)
    }

    private static func makePatterns(redactionRules: [String]) -> [RedactionPattern] {
        var patterns = builtInPatterns
        var seenCustomRules = Set<String>()

        for rule in redactionRules {
            let trimmedRule = rule.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedRule.isEmpty == false else {
                continue
            }

            let canonicalRule = canonicalIdentifier(trimmedRule)
            guard builtInRuleNames.contains(canonicalRule) == false else {
                continue
            }

            let dedupeKey = trimmedRule.lowercased()
            guard seenCustomRules.insert(dedupeKey).inserted else {
                continue
            }

            patterns.append(
                RedactionPattern(
                    regularExpression: try? NSRegularExpression(
                        pattern: NSRegularExpression.escapedPattern(for: trimmedRule),
                        options: [.caseInsensitive]
                    ),
                    replacement: "[REDACTED_CUSTOM]"
                )
            )
        }

        return patterns
    }

    private static let builtInRuleNames: Set<String> = [
        "email",
        "phone",
        "apikey",
        "apiKey",
        "api key",
        "password",
        "passcode"
    ].map(canonicalIdentifier).reduce(into: Set<String>()) { names, name in
        names.insert(name)
    }

    private static let builtInPatterns: [RedactionPattern] = [
        RedactionPattern(
            pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            options: [.caseInsensitive],
            replacement: "[REDACTED_EMAIL]"
        ),
        RedactionPattern(
            pattern: #"\b(?:api[_ -]?key|apikey|access[_ -]?token|secret[_ -]?key)\b\s*[:=]\s*["']?[^"',;\s]+["']?"#,
            options: [.caseInsensitive],
            replacement: "[REDACTED_API_KEY]"
        ),
        RedactionPattern(
            pattern: #"\bsk-[A-Za-z0-9_-]{16,}\b"#,
            replacement: "[REDACTED_API_KEY]"
        ),
        RedactionPattern(
            pattern: #"\b(?:password|passwd|pwd|passcode)\b\s*[:=]\s*["']?[^"',;\s]+["']?"#,
            options: [.caseInsensitive],
            replacement: "[REDACTED_PASSWORD]"
        ),
        RedactionPattern(
            pattern: #"(?<![A-Za-z0-9])(?:\+?\d[\d\s().-]{7,}\d)(?![A-Za-z0-9])"#,
            replacement: "[REDACTED_PHONE]"
        )
    ]

    private static func canonicalIdentifier(_ value: String) -> String {
        value
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map { String($0).lowercased() }
            .joined()
    }
}

private struct RedactionPattern {
    private let regularExpression: NSRegularExpression?
    private let replacement: String

    init(
        pattern: String,
        options: NSRegularExpression.Options = [],
        replacement: String
    ) {
        self.regularExpression = try? NSRegularExpression(pattern: pattern, options: options)
        self.replacement = replacement
    }

    init(
        regularExpression: NSRegularExpression?,
        replacement: String
    ) {
        self.regularExpression = regularExpression
        self.replacement = replacement
    }

    func redact(_ value: String) -> String {
        guard let regularExpression else {
            return value
        }

        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regularExpression.stringByReplacingMatches(
            in: value,
            options: [],
            range: range,
            withTemplate: replacement
        )
    }
}
