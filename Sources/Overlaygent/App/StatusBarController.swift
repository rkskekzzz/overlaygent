import AppKit

protocol StatusBarButtonProviding: AnyObject {
    var toolTip: String? { get set }
    var image: NSImage? { get set }
    var imagePosition: NSControl.ImagePosition { get set }
    var imageScaling: NSImageScaling { get set }
    var title: String { get set }
}

extension NSStatusBarButton: StatusBarButtonProviding {}

protocol StatusItemProviding: AnyObject {
    var statusButton: (any StatusBarButtonProviding)? { get }
    var menu: NSMenu? { get set }
}

extension NSStatusItem: StatusItemProviding {
    var statusButton: (any StatusBarButtonProviding)? {
        button
    }
}

final class StatusBarController: NSObject {
    typealias SystemImageFactory = (_ systemSymbolName: String, _ accessibilityDescription: String) -> NSImage?
    typealias StatusIconRestoreCancellation = () -> Void
    typealias StatusIconRestoreScheduler = (
        _ duration: TimeInterval,
        _ restore: @escaping () -> Void
    ) -> StatusIconRestoreCancellation

    struct Actions {
        var runActiveAgents: ([String]) -> Void
        var setAgentActive: (AgentProfile.ID, Bool) -> Void
        var openDashboard: () -> Void
        var openDiagnostics: () -> Void
        var quit: () -> Void

        init(
            runActiveAgents: @escaping ([String]) -> Void = { _ in },
            setAgentActive: @escaping (AgentProfile.ID, Bool) -> Void = { _, _ in },
            openDashboard: @escaping () -> Void = {},
            openDiagnostics: @escaping () -> Void = {},
            quit: @escaping () -> Void = {}
        ) {
            self.runActiveAgents = runActiveAgents
            self.setAgentActive = setAgentActive
            self.openDashboard = openDashboard
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
        static let emptyActiveAgents = "No active agents configured"
        static let openDashboard = "Open Dashboard"
        static let diagnostics = "Diagnostics"
        static let quit = "Quit"
    }

    private enum StatusIconState {
        case normal
        case emptyInput

        var systemSymbolName: String {
            switch self {
            case .normal:
                return "text.badge.checkmark"
            case .emptyInput:
                return "text.badge.xmark"
            }
        }

        var accessibilityDescription: String {
            switch self {
            case .normal:
                return "Overlaygent"
            case .emptyInput:
                return "No input to review"
            }
        }

        var fallbackTitle: String {
            switch self {
            case .normal:
                return "OVG"
            case .emptyInput:
                return "0"
            }
        }

        var toolTip: String {
            switch self {
            case .normal:
                return "Overlaygent"
            case .emptyInput:
                return "No input to review"
            }
        }
    }

    private let statusItem: StatusItemProviding
    private let removeStatusItem: () -> Void
    private let actions: Actions
    private let makeSystemImage: SystemImageFactory
    private let scheduleStatusIconRestore: StatusIconRestoreScheduler
    private var activeAgentEntries: [ActiveAgentEntry]
    private var cancelStatusIconRestore: StatusIconRestoreCancellation?

    private(set) var menu: NSMenu

    convenience init(
        actions: Actions = .placeholder,
        activeAgentEntries: [ActiveAgentEntry] = []
    ) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.init(
            statusItem: statusItem,
            removeStatusItem: {
                NSStatusBar.system.removeStatusItem(statusItem)
            },
            actions: actions,
            activeAgentEntries: activeAgentEntries
        )
    }

    init(
        statusItem: StatusItemProviding,
        removeStatusItem: @escaping () -> Void = {},
        actions: Actions = .placeholder,
        activeAgentEntries: [ActiveAgentEntry] = [],
        makeSystemImage: @escaping SystemImageFactory = {
            NSImage(systemSymbolName: $0, accessibilityDescription: $1)
        },
        scheduleStatusIconRestore: @escaping StatusIconRestoreScheduler = { duration, restore in
            let workItem = DispatchWorkItem(block: restore)
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
            return {
                workItem.cancel()
            }
        }
    ) {
        self.statusItem = statusItem
        self.removeStatusItem = removeStatusItem
        self.actions = actions
        self.makeSystemImage = makeSystemImage
        self.scheduleStatusIconRestore = scheduleStatusIconRestore
        self.activeAgentEntries = activeAgentEntries
        self.menu = NSMenu()

        super.init()

        configureStatusItem()
        rebuildMenu()
    }

    deinit {
        cancelStatusIconRestore?()
        removeStatusItem()
    }

    func updateActiveAgentEntries(_ entries: [ActiveAgentEntry]) {
        activeAgentEntries = entries
        rebuildMenu()
    }

    func showEmptyInputFeedback(duration: TimeInterval = 1.0) {
        cancelStatusIconRestore?()
        applyStatusIcon(.emptyInput)

        cancelStatusIconRestore = scheduleStatusIconRestore(duration) { [weak self] in
            self?.applyStatusIcon(.normal)
            self?.cancelStatusIconRestore = nil
        }
    }

    private func configureStatusItem() {
        applyStatusIcon(.normal)
    }

    private func applyStatusIcon(_ state: StatusIconState) {
        guard let button = statusItem.statusButton else {
            return
        }

        button.toolTip = state.toolTip

        if let image = makeSystemImage(state.systemSymbolName, state.accessibilityDescription) {
            image.isTemplate = true
            button.image = image
            button.title = ""
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
        } else {
            button.image = nil
            button.title = state.fallbackTitle
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(makeMenuItem(title: MenuTitle.runActiveAgents, action: #selector(runActiveAgents(_:))))
        menu.addItem(.separator())

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
        menu.addItem(makeMenuItem(title: MenuTitle.openDashboard, action: #selector(openDashboard(_:))))
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

    @objc private func openDashboard(_ sender: NSMenuItem) {
        actions.openDashboard()
    }

    @objc private func openDiagnostics(_ sender: NSMenuItem) {
        actions.openDiagnostics()
    }

    @objc private func quit(_ sender: NSMenuItem) {
        actions.quit()
    }
}
