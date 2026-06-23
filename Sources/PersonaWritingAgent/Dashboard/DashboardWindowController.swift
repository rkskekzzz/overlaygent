import AppKit
import SwiftUI

final class DashboardWindowController: NSWindowController {
    convenience init(dependencies: DashboardDependencies = .live) {
        let rootView = DashboardRootView(dependencies: dependencies)
        let hostingView = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "Persona Writing Agent"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.contentView = hostingView
        window.minSize = NSSize(width: 720, height: 500)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("PersonaWritingAgentDashboard")
        window.center()

        self.init(window: window)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}
