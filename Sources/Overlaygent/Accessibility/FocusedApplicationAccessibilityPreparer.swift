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

final class RecentFocusedApplicationProvider: FocusedApplicationProviding {
    static let shared = RecentFocusedApplicationProvider()

    private let lock = NSLock()
    private let notificationCenter: NotificationCenter
    private let ownBundleID: String?
    private let ownProcessIdentifier: pid_t
    private var recentApplication: FocusedApplicationSnapshot?
    private var activationObserver: NSObjectProtocol?

    init(
        workspace: NSWorkspace = .shared,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        ownBundleID: String? = Bundle.main.bundleIdentifier,
        ownProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier
    ) {
        self.notificationCenter = notificationCenter
        self.ownBundleID = ownBundleID
        self.ownProcessIdentifier = ownProcessIdentifier

        updateRecentApplication(from: workspace.frontmostApplication)
        activationObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.updateRecentApplication(
                from: notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            )
        }
    }

    deinit {
        if let activationObserver {
            notificationCenter.removeObserver(activationObserver)
        }
    }

    func focusedApplication() -> FocusedApplicationSnapshot? {
        lock.lock()
        defer { lock.unlock() }

        return recentApplication
    }

    private func updateRecentApplication(from application: NSRunningApplication?) {
        guard let application,
              let bundleID = application.bundleIdentifier,
              isOwnApplication(application) == false else {
            return
        }

        let snapshot = FocusedApplicationSnapshot(
            bundleID: bundleID,
            processIdentifier: application.processIdentifier
        )
        lock.lock()
        recentApplication = snapshot
        lock.unlock()
    }

    private func isOwnApplication(_ application: NSRunningApplication) -> Bool {
        if application.processIdentifier == ownProcessIdentifier {
            return true
        }

        guard let ownBundleID,
              let bundleID = application.bundleIdentifier else {
            return false
        }

        return BundleIdentifier.lookupKey(for: bundleID) == BundleIdentifier.lookupKey(for: ownBundleID)
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
    typealias Sleeper = (TimeInterval) -> Void

    private let applicationProvider: any FocusedApplicationProviding
    private let electronEnabler: any ElectronAccessibilityEnabling
    private let logger: Logger
    private let postEnableDelay: TimeInterval
    private let sleeper: Sleeper

    init(
        applicationProvider: any FocusedApplicationProviding = SystemFocusedApplicationProvider(),
        electronEnabler: any ElectronAccessibilityEnabling = ElectronAccessibilityEnabler(),
        logger: @escaping Logger = SafeLogger.default.log,
        postEnableDelay: TimeInterval = 0,
        sleeper: @escaping Sleeper = { Thread.sleep(forTimeInterval: $0) }
    ) {
        self.applicationProvider = applicationProvider
        self.electronEnabler = electronEnabler
        self.logger = logger
        self.postEnableDelay = max(0, postEnableDelay)
        self.sleeper = sleeper
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

        switch result {
        case .enabled:
            if postEnableDelay > 0 {
                sleeper(postEnableDelay)
            }
            return
        case .skippedUnknownBundleID:
            return
        case let .failed(_, error):
            logger(
                "Electron accessibility preparation failed for frontmost known app: \(SafeLogger.redacted(error.description))"
            )
        }
    }
}
