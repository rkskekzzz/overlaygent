import Foundation
import XCTest
@testable import Overlaygent

final class AXSecureFieldDetectorTests: XCTestCase {
    private let detector = AXSecureFieldDetector()

    func testRejectsSecureTextFieldSubrole() {
        let element = focusedElement(
            role: "AXTextField",
            subrole: "AXSecureTextField",
            value: "hidden"
        )

        XCTAssertTrue(detector.isSecureField(element))
        XCTAssertEqual(detector.guardTextInput(element), .rejected(reason: .secureField))
        XCTAssertFalse(detector.canProcessText(element))
    }

    func testRejectsPasswordLikeRoleBeforeReadingAsProcessableText() {
        let element = focusedElement(
            role: "AXPasswordTextField",
            subrole: nil,
            value: "hidden"
        )

        XCTAssertTrue(detector.isSecureField(element))
        XCTAssertEqual(detector.guardTextInput(element), .rejected(reason: .secureField))
    }

    func testRejectsPrivateOrSecureSubroleMetadata() {
        let privateElement = focusedElement(
            role: "AXTextField",
            subrole: "AXPrivateTextInput",
            value: "hidden"
        )
        let secureElement = focusedElement(
            role: "AXTextArea",
            subrole: "AXSecureEditableText",
            value: "hidden"
        )

        XCTAssertTrue(detector.isSecureField(privateElement))
        XCTAssertTrue(detector.isSecureField(secureElement))
    }

    func testRejectsPasswordRoleDescriptionStrings() {
        XCTAssertTrue(
            detector.isSecureField(
                role: "AXTextField",
                subrole: nil,
                roleDescription: "password text field"
            )
        )
        XCTAssertTrue(
            detector.isSecureField(
                role: "AXTextField",
                subrole: nil,
                roleDescription: "Private field"
            )
        )
    }

    func testAllowsRegularTextArea() {
        let element = focusedElement(
            role: "AXTextArea",
            subrole: "AXStandardWindowTextArea",
            value: "Can we deploy it after review?"
        )

        XCTAssertFalse(detector.isSecureField(element))
        XCTAssertEqual(detector.guardTextInput(element), .allowed)
        XCTAssertTrue(detector.canProcessText(element))
    }

    func testDoesNotRejectRegularTextAreaBecauseValueMentionsPassword() {
        let element = focusedElement(
            role: "AXTextArea",
            subrole: nil,
            value: "Please rotate the password after the incident."
        )

        XCTAssertFalse(detector.isSecureField(element))
        XCTAssertEqual(detector.guardTextInput(element), .allowed)
    }

    func testRejectsUnsupportedOrUnreadableTextInputs() {
        let staticText = focusedElement(
            role: "AXStaticText",
            subrole: nil,
            value: "Visible label"
        )
        let unreadableTextArea = focusedElement(
            role: "AXTextArea",
            subrole: nil,
            value: nil
        )

        XCTAssertEqual(detector.guardTextInput(staticText), .rejected(reason: .unsupportedRole))
        XCTAssertEqual(detector.guardTextInput(unreadableTextArea), .rejected(reason: .missingTextValue))
    }

    private func focusedElement(role: String?, subrole: String?, value: String?) -> AXFocusedElement {
        AXFocusedElement(
            element: AXElement(FakeAXNode()),
            role: role,
            subrole: subrole,
            value: value,
            selectedRange: nil
        )
    }
}

private final class FakeAXNode: NSObject {}
