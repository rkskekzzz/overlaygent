import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var dashboardWindowController = environment.makeDashboardWindowController()
    private let environment: AppEnvironment
    private let permissionCoordinator: PermissionCoordinator
    private let agentProfileStore: AgentProfileStore
    private let hotkeyRegistrar: HotkeyRegistering
    private let activeAgentRunTaskController: any ActiveAgentRunTaskControlling
    private let logger: SafeLogger
    private let makeStatusBarController: AppEnvironment.StatusBarFactory
    private let terminateApplication: () -> Void
    private lazy var hotkeyManager = HotkeyManager(registrar: hotkeyRegistrar)
    private lazy var debugOverlayController = OverlayController()
    private var statusBarController: StatusBarController?
    private var agentProfiles: [AgentProfile] = []

    init(environment: AppEnvironment = .live()) {
        self.environment = environment
        self.agentProfileStore = environment.agentProfileStore
        self.permissionCoordinator = environment.permissionCoordinator
        self.hotkeyRegistrar = environment.hotkeyRegistrar
        self.activeAgentRunTaskController = environment.activeAgentRunTaskController
        self.logger = environment.logger
        self.makeStatusBarController = environment.makeStatusBarController
        self.terminateApplication = environment.terminateApplication
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ApplicationMenuController.installStandardMainMenu()
        reloadAgentProfiles()

        statusBarController = makeStatusBarController(
            StatusBarController.Actions(
                runActiveAgents: { [weak self] activeAgentNames in
                    self?.runActiveAgents(activeAgentNames: activeAgentNames)
                },
                setAgentActive: { [weak self] id, isActive in
                    self?.setAgentActive(id: id, isActive: isActive)
                },
                openDashboard: { [weak self] in
                    self?.openDashboard()
                },
                openDiagnostics: { [weak self] in
                    self?.openDiagnostics()
                },
                quit: { [terminateApplication] in
                    terminateApplication()
                }
            ),
            activeAgentMenuEntries()
        )

        registerAgentProfileChanges()
        registerRunActiveAgentsHotkey()
        registerDebugOverlayProbe()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        hotkeyManager.stop()
        activeAgentRunTaskController.cancelCurrentRun()
    }

    private func reloadAgentProfiles() {
        do {
            agentProfiles = try agentProfileStore.loadProfiles()
            statusBarController?.updateActiveAgentEntries(activeAgentMenuEntries())
        } catch {
            agentProfiles = AgentProfileStore.defaultAgents()
            statusBarController?.updateActiveAgentEntries(activeAgentMenuEntries())
            logger.log("Failed to load agent profiles: \(error.localizedDescription)")
        }
    }

    private func activeAgentMenuEntries() -> [StatusBarController.ActiveAgentEntry] {
        agentProfiles.map { profile in
            StatusBarController.ActiveAgentEntry(
                id: profile.id,
                name: profile.name,
                isActive: profile.isActive,
                isEnabled: profile.isEnabled
            )
        }
    }

    private func activeProfiles() -> [AgentProfile] {
        agentProfiles.filter { $0.isEnabled && $0.isActive }
    }

    private func runActiveAgents(activeAgentNames _: [String]) {
        reloadAgentProfiles()
        let profiles = activeProfiles()
        let names = profiles.map(\.name)

        if names.isEmpty {
            logger.log("Run Active Agents requested, but no agents are active.")
        } else {
            logger.log("Run Active Agents requested for \(names.count) active agent(s).")
        }

        let runTask = activeAgentRunTaskController.startRun()
        Task { @MainActor [weak self] in
            let summary = await runTask.value
            guard summary.failureStage == .emptyInput else {
                return
            }

            self?.statusBarController?.showEmptyInputFeedback()
        }
    }

    private func registerRunActiveAgentsHotkey() {
        do {
            try hotkeyManager.start(config: .runActiveAgents) { [weak self] in
                self?.runActiveAgents(activeAgentNames: [])
            }
        } catch {
            logger.log(
                "Failed to register global hotkey \(HotkeyConfig.runActiveAgents.displayName): \(error.localizedDescription)"
            )
        }
    }

    private func registerAgentProfileChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(agentProfilesDidChange),
            name: .overlaygentAgentProfilesDidChange,
            object: nil
        )
    }

    @objc private func agentProfilesDidChange() {
        reloadAgentProfiles()
    }

    private func registerDebugOverlayProbe() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(showDebugOverlayProbe),
            name: .overlaygentShowDebugOverlayProbe,
            object: nil
        )
    }

    @objc private func showDebugOverlayProbe() {
        do {
            let capture = try AccessibilityPreparingInputCapture(
                preparer: FocusedApplicationAccessibilityPreparer(
                    logger: logger.log
                ),
                baseCapture: FocusedTextSession()
            ).capture()
            let anchor = OverlayAnchorGeometry(
                caretRect: capture.geometry.caretBounds ?? capture.geometry.selectionBounds,
                inputRect: capture.geometry.inputFrame,
                fallbackRect: nil
            )
            let placement = debugOverlayController.showStatus(
                anchor: anchor,
                title: "Overlay Probe",
                detail: Self.debugOverlayDetail(capture: capture)
            )
            logger.log(
                "Overlay probe placement source=\(placement.anchorSource) frame=\(Self.formatRect(placement.frame)) detail=\(Self.debugOverlayDetail(capture: capture))"
            )
        } catch {
            let detail = SafeLogger.redacted(String(describing: error))
            logger.log("Overlay probe failed: \(detail)")
            _ = debugOverlayController.showStatus(
                anchor: OverlayAnchorGeometry(),
                title: "Overlay Probe Failed",
                detail: detail
            )
        }
    }

    private static func debugOverlayDetail(capture: FocusedTextCapture) -> String {
        [
            "bundle: \(capture.snapshot.sourceBundleID)",
            "role: \(capture.focusedElement.role ?? "nil")",
            "selected: \(formatRange(capture.focusedElement.selectedRange))",
            "input: \(formatRect(capture.geometry.inputFrame))",
            "caret: \(formatRect(capture.geometry.caretBounds))",
            "selection: \(formatRect(capture.geometry.selectionBounds))"
        ].joined(separator: "\n")
    }

    private static func formatRange(_ range: AXTextRange?) -> String {
        guard let range else {
            return "nil"
        }

        return "\(range.location)..<\(range.upperBound)"
    }

    private static func formatRect(_ rect: CGRect?) -> String {
        guard let rect else {
            return "nil"
        }

        return "x:\(Int(rect.minX)) y:\(Int(rect.minY)) w:\(Int(rect.width)) h:\(Int(rect.height))"
    }

    private func setAgentActive(id: AgentProfile.ID, isActive: Bool) {
        do {
            var profiles = try agentProfileStore.loadProfiles()

            guard let index = profiles.firstIndex(where: { $0.id == id }) else {
                logger.log("Agent active toggle ignored because the profile no longer exists.")
                reloadAgentProfiles()
                return
            }

            profiles[index].isActive = isActive
            try agentProfileStore.saveProfiles(profiles)
            agentProfiles = profiles
            statusBarController?.updateActiveAgentEntries(activeAgentMenuEntries())
        } catch {
            logger.log("Failed to update agent active state: \(error.localizedDescription)")
            reloadAgentProfiles()
        }
    }

    private func openDashboard() {
        dashboardWindowController.showWindow(nil)
    }

    private func openDiagnostics() {
        let accessibilityState = permissionCoordinator.accessibilityStatus()
        let alert = NSAlert()
        alert.messageText = "Diagnostics"
        alert.informativeText = accessibilityState.diagnosticsDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
