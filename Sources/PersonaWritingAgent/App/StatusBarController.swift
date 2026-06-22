import AppKit

protocol StatusItemProviding: AnyObject {
    var button: NSStatusBarButton? { get }
    var menu: NSMenu? { get set }
}

extension NSStatusItem: StatusItemProviding {}

final class StatusBarController: NSObject {
    struct Actions {
        var runActiveAgents: ([String]) -> Void
        var setAgentActive: (AgentProfile.ID, Bool) -> Void
        var setCurrentAppEnabled: (Bool) -> Void
        var openDashboard: () -> Void
        var openPermissions: () -> Void
        var openDiagnostics: () -> Void
        var quit: () -> Void

        init(
            runActiveAgents: @escaping ([String]) -> Void = { _ in },
            setAgentActive: @escaping (AgentProfile.ID, Bool) -> Void = { _, _ in },
            setCurrentAppEnabled: @escaping (Bool) -> Void = { _ in },
            openDashboard: @escaping () -> Void = {},
            openPermissions: @escaping () -> Void = {},
            openDiagnostics: @escaping () -> Void = {},
            quit: @escaping () -> Void = {}
        ) {
            self.runActiveAgents = runActiveAgents
            self.setAgentActive = setAgentActive
            self.setCurrentAppEnabled = setCurrentAppEnabled
            self.openDashboard = openDashboard
            self.openPermissions = openPermissions
            self.openDiagnostics = openDiagnostics
            self.quit = quit
        }

        static var placeholder: Actions {
            Actions()
        }
    }

    struct ActiveAgentEntry: Equatable {
        var id: AgentProfile.ID
        var name: String
        var isActive: Bool
        var isEnabled: Bool

        init(
            id: AgentProfile.ID = UUID(),
            name: String,
            isActive: Bool,
            isEnabled: Bool = true
        ) {
            self.id = id
            self.name = name
            self.isActive = isActive
            self.isEnabled = isEnabled
        }
    }

    private enum MenuTitle {
        static let runActiveAgents = "Run Active Agents"
        static let activeAgents = "Active Agents"
        static let emptyActiveAgents = "No active agents configured"
        static let enableForCurrentApp = "Enable for Current App"
        static let disableForCurrentApp = "Disable for Current App"
        static let openDashboard = "Open Dashboard"
        static let permissions = "Permissions"
        static let diagnostics = "Diagnostics"
        static let quit = "Quit"
    }

    private let statusItem: StatusItemProviding
    private let removeStatusItem: () -> Void
    private let actions: Actions
    private var activeAgentEntries: [ActiveAgentEntry]
    private var currentAppToggleItem: NSMenuItem?

    private(set) var menu: NSMenu
    private(set) var isCurrentAppEnabled: Bool

    convenience init(
        actions: Actions = .placeholder,
        activeAgentEntries: [ActiveAgentEntry] = [],
        isCurrentAppEnabled: Bool = true
    ) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.init(
            statusItem: statusItem,
            removeStatusItem: {
                NSStatusBar.system.removeStatusItem(statusItem)
            },
            actions: actions,
            activeAgentEntries: activeAgentEntries,
            isCurrentAppEnabled: isCurrentAppEnabled
        )
    }

    init(
        statusItem: StatusItemProviding,
        removeStatusItem: @escaping () -> Void = {},
        actions: Actions = .placeholder,
        activeAgentEntries: [ActiveAgentEntry] = [],
        isCurrentAppEnabled: Bool = true
    ) {
        self.statusItem = statusItem
        self.removeStatusItem = removeStatusItem
        self.actions = actions
        self.activeAgentEntries = activeAgentEntries
        self.isCurrentAppEnabled = isCurrentAppEnabled
        self.menu = NSMenu()

        super.init()

        configureStatusItem()
        rebuildMenu()
    }

    deinit {
        removeStatusItem()
    }

    func updateActiveAgentEntries(_ entries: [ActiveAgentEntry]) {
        activeAgentEntries = entries
        rebuildMenu()
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.toolTip = "Persona Writing Agent"

            if let image = NSImage(
                systemSymbolName: "text.badge.checkmark",
                accessibilityDescription: "Persona Writing Agent"
            ) {
                image.isTemplate = true
                button.image = image
                button.imagePosition = .imageOnly
            } else {
                button.title = "PWA"
            }
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(makeMenuItem(title: MenuTitle.runActiveAgents, action: #selector(runActiveAgents(_:))))
        menu.addItem(.separator())

        let activeAgentsHeader = NSMenuItem(title: MenuTitle.activeAgents, action: nil, keyEquivalent: "")
        activeAgentsHeader.isEnabled = false
        menu.addItem(activeAgentsHeader)

        if activeAgentEntries.isEmpty {
            let placeholder = NSMenuItem(title: MenuTitle.emptyActiveAgents, action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            menu.addItem(placeholder)
        } else {
            for entry in activeAgentEntries {
                let item = makeMenuItem(
                    title: entry.name,
                    action: #selector(toggleAgentActive(_:))
                )
                item.representedObject = entry.id
                item.isEnabled = entry.isEnabled
                item.state = entry.isActive ? .on : .off
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let currentAppToggle = makeMenuItem(
            title: currentAppToggleTitle,
            action: #selector(toggleCurrentAppEnabled(_:))
        )
        currentAppToggleItem = currentAppToggle
        menu.addItem(currentAppToggle)

        menu.addItem(makeMenuItem(title: MenuTitle.openDashboard, action: #selector(openDashboard(_:))))
        menu.addItem(makeMenuItem(title: MenuTitle.permissions, action: #selector(openPermissions(_:))))
        menu.addItem(makeMenuItem(title: MenuTitle.diagnostics, action: #selector(openDiagnostics(_:))))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: MenuTitle.quit, action: #selector(quit(_:)), keyEquivalent: "q"))

        self.menu = menu
        statusItem.menu = menu
    }

    private func makeMenuItem(
        title: String,
        action: Selector?,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.isEnabled = true
        return item
    }

    private var currentAppToggleTitle: String {
        isCurrentAppEnabled ? MenuTitle.disableForCurrentApp : MenuTitle.enableForCurrentApp
    }

    @objc private func runActiveAgents(_ sender: NSMenuItem) {
        let activeAgentNames = activeAgentEntries
            .filter { $0.isEnabled && $0.isActive }
            .map(\.name)
        actions.runActiveAgents(activeAgentNames)
    }

    @objc private func toggleAgentActive(_ sender: NSMenuItem) {
        guard
            let id = sender.representedObject as? AgentProfile.ID,
            let index = activeAgentEntries.firstIndex(where: { $0.id == id })
        else {
            return
        }

        activeAgentEntries[index].isActive.toggle()
        let isActive = activeAgentEntries[index].isActive
        rebuildMenu()
        actions.setAgentActive(id, isActive)
    }

    @objc private func toggleCurrentAppEnabled(_ sender: NSMenuItem) {
        isCurrentAppEnabled.toggle()
        currentAppToggleItem?.title = currentAppToggleTitle
        actions.setCurrentAppEnabled(isCurrentAppEnabled)
    }

    @objc private func openDashboard(_ sender: NSMenuItem) {
        actions.openDashboard()
    }

    @objc private func openPermissions(_ sender: NSMenuItem) {
        actions.openPermissions()
    }

    @objc private func openDiagnostics(_ sender: NSMenuItem) {
        actions.openDiagnostics()
    }

    @objc private func quit(_ sender: NSMenuItem) {
        actions.quit()
    }
}
