import XCTest
@testable import PersonaWritingAgent

final class BundleIdentifierTests: XCTestCase {
    func testLookupKeyTrimsAndLowercasesForMatching() {
        let identifier = BundleIdentifier(" com.Microsoft.VSCode ")

        XCTAssertEqual(identifier.trimmed, "com.Microsoft.VSCode")
        XCTAssertEqual(identifier.lookupKey, "com.microsoft.vscode")
        XCTAssertTrue(identifier.matches("COM.MICROSOFT.VSCODE"))
    }

    func testLookupKeysDropsEmptyIdentifiers() {
        XCTAssertEqual(
            BundleIdentifier.lookupKeys(for: ["", "  ", "com.TinySpeck.SlackMacGap"]),
            ["com.tinyspeck.slackmacgap"]
        )
    }
}
