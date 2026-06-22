import AppKit
import XCTest
@testable import PersonaWritingAgent

final class ApplicationMenuControllerTests: XCTestCase {
    func testStandardMainMenuIncludesResponderEditCommandsForTextInputs() throws {
        let menu = ApplicationMenuController.makeStandardMainMenu(appName: "PersonaWritingAgent")
        let editMenu = try XCTUnwrap(menu.items.compactMap(\.submenu).first { $0.title == "Edit" })

        XCTAssertEqual(
            editMenu.items
                .filter { $0.isSeparatorItem == false }
                .map(\.title),
            ["Undo", "Redo", "Cut", "Copy", "Paste", "Select All"]
        )

        XCTAssertMenuItem(editMenu, title: "Paste", action: "paste:", keyEquivalent: "v")
        XCTAssertMenuItem(editMenu, title: "Copy", action: "copy:", keyEquivalent: "c")
        XCTAssertMenuItem(editMenu, title: "Cut", action: "cut:", keyEquivalent: "x")
        XCTAssertMenuItem(editMenu, title: "Select All", action: "selectAll:", keyEquivalent: "a")
    }

    private func XCTAssertMenuItem(
        _ menu: NSMenu,
        title: String,
        action: String,
        keyEquivalent: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let item = menu.items.first { $0.title == title }
        XCTAssertNotNil(item, file: file, line: line)
        XCTAssertEqual(item?.action, Selector(action), file: file, line: line)
        XCTAssertNil(item?.target, file: file, line: line)
        XCTAssertEqual(item?.keyEquivalent, keyEquivalent, file: file, line: line)
        XCTAssertEqual(item?.keyEquivalentModifierMask.contains(.command), true, file: file, line: line)
    }
}
