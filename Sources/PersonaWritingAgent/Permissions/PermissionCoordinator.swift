import AppKit
import ApplicationServices
import Foundation

protocol AccessibilityTrustChecking {
    func isProcessTrusted(options: AccessibilityPermissionPromptOptions) -> Bool
}

struct SystemAccessibilityTrustChecker: AccessibilityTrustChecking {
    func isProcessTrusted(options: AccessibilityPermissionPromptOptions) -> Bool {
        AXIsProcessTrustedWithOptions(options.cfDictionary)
    }
}

protocol SettingsOpening {
    func open(_ url: URL) -> Bool
}

struct WorkspaceSettingsOpener: SettingsOpening {
    func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}

final class PermissionCoordinator {
    private let trustChecker: AccessibilityTrustChecking
    private let settingsOpener: SettingsOpening
    private let settingsDestination: AccessibilitySettingsDestination

    init(
        trustChecker: AccessibilityTrustChecking = SystemAccessibilityTrustChecker(),
        settingsOpener: SettingsOpening = WorkspaceSettingsOpener(),
        settingsDestination: AccessibilitySettingsDestination = AccessibilitySettingsDestination()
    ) {
        self.trustChecker = trustChecker
        self.settingsOpener = settingsOpener
        self.settingsDestination = settingsDestination
    }

    func accessibilityStatus(promptUser: Bool = false) -> AccessibilityPermissionState {
        let options = AccessibilityPermissionPromptOptions(promptUser: promptUser)
        let status: AccessibilityPermissionStatus = trustChecker.isProcessTrusted(options: options)
            ? .trusted
            : .notTrusted

        return AccessibilityPermissionState(
            status: status,
            settingsURL: settingsDestination.url,
            promptWasRequested: promptUser
        )
    }

    func requestAccessibilityPermissionPrompt() -> AccessibilityPermissionState {
        accessibilityStatus(promptUser: true)
    }

    func accessibilitySettingsDestination() -> AccessibilitySettingsDestination {
        settingsDestination
    }

    @discardableResult
    func openAccessibilitySettings() -> Bool {
        settingsOpener.open(settingsDestination.url)
    }
}
