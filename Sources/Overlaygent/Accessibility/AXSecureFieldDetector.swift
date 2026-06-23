import AppKit
import Foundation

enum AXTextInputGuardResult: Equatable {
    case allowed
    case rejected(reason: AXTextInputRejectionReason)

    var isAllowed: Bool {
        self == .allowed
    }
}

enum AXTextInputRejectionReason: Equatable, CustomStringConvertible {
    case secureField
    case unsupportedRole
    case missingTextValue

    var description: String {
        switch self {
        case .secureField:
            return "secure text input"
        case .unsupportedRole:
            return "unsupported text input role"
        case .missingTextValue:
            return "focused text input has no readable text value"
        }
    }
}

struct AXSecureFieldDetector {
    private let secureRoles: Set<String>
    private let secureSubroles: Set<String>
    private let supportedTextRoles: Set<String>

    init(
        secureRoles: Set<String> = ["AXSecureTextField"],
        secureSubroles: Set<String> = [NSAccessibility.Subrole.secureTextField.rawValue],
        supportedTextRoles: Set<String> = [
            NSAccessibility.Role.textArea.rawValue,
            NSAccessibility.Role.textField.rawValue
        ]
    ) {
        self.secureRoles = Set(secureRoles.map(Self.canonicalIdentifier))
        self.secureSubroles = Set(secureSubroles.map(Self.canonicalIdentifier))
        self.supportedTextRoles = Set(supportedTextRoles.map(Self.canonicalIdentifier))
    }

    func isSecureField(_ element: AXFocusedElement) -> Bool {
        isSecureField(role: element.role, subrole: element.subrole)
    }

    func isSecureField(role: String?, subrole: String?, roleDescription: String? = nil) -> Bool {
        if matchesExact(role, in: secureRoles) {
            return true
        }

        if matchesExact(subrole, in: secureSubroles) {
            return true
        }

        if containsSensitiveFieldToken(role) || containsSensitiveFieldToken(subrole) {
            return true
        }

        return containsSensitiveFieldToken(roleDescription)
    }

    func guardTextInput(_ element: AXFocusedElement) -> AXTextInputGuardResult {
        if isSecureField(element) {
            return .rejected(reason: .secureField)
        }

        guard isSupportedTextInput(role: element.role) else {
            return .rejected(reason: .unsupportedRole)
        }

        guard element.value != nil else {
            return .rejected(reason: .missingTextValue)
        }

        return .allowed
    }

    func canProcessText(_ element: AXFocusedElement) -> Bool {
        guardTextInput(element).isAllowed
    }

    private func isSupportedTextInput(role: String?) -> Bool {
        matchesExact(role, in: supportedTextRoles)
    }

    private func matchesExact(_ value: String?, in canonicalValues: Set<String>) -> Bool {
        guard let value else {
            return false
        }

        return canonicalValues.contains(Self.canonicalIdentifier(value))
    }

    private func containsSensitiveFieldToken(_ value: String?) -> Bool {
        guard let value else {
            return false
        }

        let normalized = Self.canonicalIdentifier(value)

        return normalized.contains("password")
            || normalized.contains("passcode")
            || normalized.contains("secure")
            || normalized.contains("private")
    }

    private static func canonicalIdentifier(_ value: String) -> String {
        value
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map { String($0).lowercased() }
            .joined()
    }
}
