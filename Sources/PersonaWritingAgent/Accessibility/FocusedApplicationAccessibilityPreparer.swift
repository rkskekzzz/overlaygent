import AppKit
import Foundation

struct FocusedApplicationSnapshot: Equatable {
    var bundleID: String
    var processIdentifier: pid_t
}

protocol FocusedApplicationProviding {
    func focusedApplication() -> FocusedApplicationSnapshot?
}

struct SystemFocusedApplicationProvider: FocusedApplicationProviding {
    func focusedApplication() -> FocusedApplicationSnapshot? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              let bundleID = application.bundleIdentifier else {
            return nil
        }

        return FocusedApplicationSnapshot(
            bundleID: bundleID,
            processIdentifier: application.processIdentifier
        )
    }
}

protocol ElectronAccessibilityEnabling {
    func enableIfNeeded(for target: ElectronAccessibilityTarget) -> ElectronAccessibilityEnableResult
}

extension ElectronAccessibilityEnabler: ElectronAccessibilityEnabling {}

protocol FocusedApplicationAccessibilityPreparing {
    func prepareFocusedApplication()
}

struct NoopFocusedApplicationAccessibilityPreparer: FocusedApplicationAccessibilityPreparing {
    func prepareFocusedApplication() {}
}

struct FocusedApplicationAccessibilityPreparer: FocusedApplicationAccessibilityPreparing {
    typealias Logger = (String) -> Void

    private let applicationProvider: any FocusedApplicationProviding
    private let electronEnabler: any ElectronAccessibilityEnabling
    private let logger: Logger

    init(
        applicationProvider: any FocusedApplicationProviding = SystemFocusedApplicationProvider(),
        electronEnabler: any ElectronAccessibilityEnabling = ElectronAccessibilityEnabler(),
        logger: @escaping Logger = SafeLogger.default.log
    ) {
        self.applicationProvider = applicationProvider
        self.electronEnabler = electronEnabler
        self.logger = logger
    }

    func prepareFocusedApplication() {
        guard let application = applicationProvider.focusedApplication() else {
            return
        }

        let result = electronEnabler.enableIfNeeded(
            for: ElectronAccessibilityTarget(
                bundleID: application.bundleID,
                processIdentifier: application.processIdentifier
            )
        )

        guard case let .failed(_, error) = result else {
            return
        }

        logger(
            "Electron accessibility preparation failed for frontmost known app: \(SafeLogger.redacted(error.description))"
        )
    }
}
