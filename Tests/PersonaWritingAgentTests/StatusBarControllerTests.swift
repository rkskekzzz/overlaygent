import AppKit
import XCTest
@testable import PersonaWritingAgent

final class StatusBarControllerTests: XCTestCase {
    func testStatusMenuMatchesPRDShell() {
        let statusItem = FakeStatusItem()
        let controller = StatusBarController(statusItem: statusItem)

        XCTAssertTrue(statusItem.menu === controller.menu)
        XCTAssertEqual(
            controller.menu.items.map(menuItemTitle),
            [
                "Run Active Agents",
                "-",
                "Active Agents",
                "No active agents configured",
                "-",
                "Disable for Current App",
                "Open Dashboard",
                "Permissions",
                "Diagnostics",
                "-",
                "Quit"
            ]
        )
        XCTAssertFalse(controller.menu.item(withTitle: "Active Agents")?.isEnabled ?? true)
        XCTAssertFalse(controller.menu.item(withTitle: "No active agents configured")?.isEnabled ?? true)
    }

    func testMenuActionsDispatchCallbacks() {
        let statusItem = FakeStatusItem()
        var events: [String] = []
        let controller = StatusBarController(
            statusItem: statusItem,
            actions: StatusBarController.Actions(
                runActiveAgents: { names in
                    events.append("run:\(names.joined(separator: ","))")
                },
                setCurrentAppEnabled: { isEnabled in
                    events.append("current-app:\(isEnabled)")
                },
                openDashboard: {
                    events.append("dashboard")
                },
                openPermissions: {
                    events.append("permissions")
                },
                openDiagnostics: {
                    events.append("diagnostics")
                },
                quit: {
                    events.append("quit")
                }
            )
        )

        selectMenuItem("Run Active Agents", in: controller.menu)
        let currentAppToggle = controller.menu.item(withTitle: "Disable for Current App")
        selectMenuItem("Disable for Current App", in: controller.menu)
        selectMenuItem("Open Dashboard", in: controller.menu)
        selectMenuItem("Permissions", in: controller.menu)
        selectMenuItem("Diagnostics", in: controller.menu)
        selectMenuItem("Quit", in: controller.menu)

        XCTAssertEqual(
            events,
            [
                "run:",
                "current-app:false",
                "dashboard",
                "permissions",
                "diagnostics",
                "quit"
            ]
        )
        XCTAssertEqual(currentAppToggle?.title, "Enable for Current App")
    }

    func testActiveAgentEntriesReplacePlaceholderArea() {
        let statusItem = FakeStatusItem()
        let controller = StatusBarController(statusItem: statusItem)

        controller.updateActiveAgentEntries([
            StatusBarController.ActiveAgentEntry(name: "Grammar Fixer", isActive: true),
            StatusBarController.ActiveAgentEntry(name: "Tone Polish", isActive: false)
        ])

        XCTAssertNil(controller.menu.item(withTitle: "No active agents configured"))
        XCTAssertEqual(controller.menu.item(withTitle: "Grammar Fixer")?.state, .on)
        XCTAssertEqual(controller.menu.item(withTitle: "Tone Polish")?.state, .off)
        XCTAssertTrue(controller.menu.item(withTitle: "Grammar Fixer")?.isEnabled ?? false)
        XCTAssertTrue(controller.menu.item(withTitle: "Tone Polish")?.isEnabled ?? false)
    }

    func testAgentMenuItemsToggleAndDispatchAgentCallback() {
        let statusItem = FakeStatusItem()
        let grammarID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        let toneID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        var toggles: [(AgentProfile.ID, Bool)] = []
        let controller = StatusBarController(
            statusItem: statusItem,
            actions: StatusBarController.Actions(
                setAgentActive: { id, isActive in
                    toggles.append((id, isActive))
                }
            ),
            activeAgentEntries: [
                StatusBarController.ActiveAgentEntry(id: grammarID, name: "Grammar Fixer", isActive: true),
                StatusBarController.ActiveAgentEntry(id: toneID, name: "Tone Polish", isActive: false)
            ]
        )

        selectMenuItem("Grammar Fixer", in: controller.menu)
        selectMenuItem("Tone Polish", in: controller.menu)

        XCTAssertEqual(toggles.map { $0.0 }, [grammarID, toneID])
        XCTAssertEqual(toggles.map { $0.1 }, [false, true])
        XCTAssertEqual(controller.menu.item(withTitle: "Grammar Fixer")?.state, .off)
        XCTAssertEqual(controller.menu.item(withTitle: "Tone Polish")?.state, .on)
    }

    func testRunActiveAgentsDispatchesOnlyActiveEnabledAgentNames() {
        let statusItem = FakeStatusItem()
        var dispatchedNames: [String] = []
        let controller = StatusBarController(
            statusItem: statusItem,
            actions: StatusBarController.Actions(
                runActiveAgents: { names in
                    dispatchedNames = names
                }
            ),
            activeAgentEntries: [
                StatusBarController.ActiveAgentEntry(name: "Grammar Fixer", isActive: true),
                StatusBarController.ActiveAgentEntry(name: "Tone Polish", isActive: false),
                StatusBarController.ActiveAgentEntry(name: "Disabled Agent", isActive: true, isEnabled: false)
            ]
        )

        selectMenuItem("Run Active Agents", in: controller.menu)

        XCTAssertEqual(dispatchedNames, ["Grammar Fixer"])
    }

    private func menuItemTitle(_ item: NSMenuItem) -> String {
        item.isSeparatorItem ? "-" : item.title
    }

    private func selectMenuItem(
        _ title: String,
        in menu: NSMenu,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let item = menu.item(withTitle: title) else {
            XCTFail("Missing menu item: \(title)", file: file, line: line)
            return
        }

        guard let action = item.action else {
            XCTFail("Menu item has no action: \(title)", file: file, line: line)
            return
        }

        XCTAssertTrue(
            NSApplication.shared.sendAction(action, to: item.target, from: item),
            "Menu action was not handled: \(title)",
            file: file,
            line: line
        )
    }
}

private final class FakeStatusItem: StatusItemProviding {
    var button: NSStatusBarButton?
    var menu: NSMenu?
}
