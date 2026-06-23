import ApplicationServices
import Foundation

enum AccessibilityPermissionStatus: String, Codable, Equatable {
    case trusted
    case notTrusted
}

struct AccessibilityPermissionState: Codable, Equatable {
    var status: AccessibilityPermissionStatus
    var settingsURL: URL
    var promptWasRequested: Bool

    var isTrusted: Bool {
        status == .trusted
    }

    var requiresUserAction: Bool {
        !isTrusted
    }

    var diagnosticsDescription: String {
        switch status {
        case .trusted:
            return "Accessibility permission granted"
        case .notTrusted:
            return "Accessibility permission missing"
        }
    }
}

struct AccessibilityPermissionPromptOptions: Equatable {
    static let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String

    var promptUser: Bool

    var dictionaryRepresentation: [String: Bool] {
        [Self.promptKey: promptUser]
    }

    var cfDictionary: CFDictionary {
        dictionaryRepresentation as CFDictionary
    }
}

struct AccessibilitySettingsDestination: Equatable {
    static let accessibilityURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    var url: URL = Self.accessibilityURL
    var paneName: String = "Privacy & Security"
    var sectionName: String = "Accessibility"
}
