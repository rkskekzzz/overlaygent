import AppKit

struct ApplicationMenuController {
    static func installStandardMainMenu(
        on application: NSApplication = .shared,
        appName: String = ProcessInfo.processInfo.processName
    ) {
        application.mainMenu = makeStandardMainMenu(appName: appName)
    }

    static func makeStandardMainMenu(appName: String) -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(makeApplicationMenuItem(appName: appName))
        mainMenu.addItem(makeEditMenuItem())
        return mainMenu
    }

    private static func makeApplicationMenuItem(appName: String) -> NSMenuItem {
        let menuItem = NSMenuItem()
        let menu = NSMenu(title: appName)
        menu.addItem(
            NSMenuItem(
                title: "Quit \(appName)",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        menuItem.submenu = menu
        return menuItem
    }

    private static func makeEditMenuItem() -> NSMenuItem {
        let menuItem = NSMenuItem()
        let menu = NSMenu(title: "Edit")

        menu.addItem(makeResponderMenuItem(title: "Undo", actionName: "undo:", keyEquivalent: "z"))
        let redoItem = makeResponderMenuItem(title: "Redo", actionName: "redo:", keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redoItem)
        menu.addItem(.separator())
        menu.addItem(makeResponderMenuItem(title: "Cut", actionName: "cut:", keyEquivalent: "x"))
        menu.addItem(makeResponderMenuItem(title: "Copy", actionName: "copy:", keyEquivalent: "c"))
        menu.addItem(makeResponderMenuItem(title: "Paste", actionName: "paste:", keyEquivalent: "v"))
        menu.addItem(.separator())
        menu.addItem(makeResponderMenuItem(title: "Select All", actionName: "selectAll:", keyEquivalent: "a"))

        menuItem.submenu = menu
        return menuItem
    }

    private static func makeResponderMenuItem(
        title: String,
        actionName: String,
        keyEquivalent: String
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: Selector(actionName),
            keyEquivalent: keyEquivalent
        )
        item.target = nil
        return item
    }
}
