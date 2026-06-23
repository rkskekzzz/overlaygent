import XCTest
@testable import Overlaygent

final class OnboardingPrivacyCopyTests: XCTestCase {
    func testOnboardingCopyExplainsAccessibilityAndCurrentInputOnly() {
        let text = OnboardingCopy.dashboard.searchableText.normalizedForCopyAssertion()

        XCTAssertContains(text, "accessibility permission")
        XCTAssertContains(text, "current focused input")
        XCTAssertContains(text, "os accessibility api")
        XCTAssertContains(text, "not a keylogger")
    }

    func testPrivacyCopyCoversProtectedFieldsOptInsAndProviderScope() {
        let text = PrivacyCopy.dashboard.searchableText.normalizedForCopyAssertion()

        XCTAssertContains(text, "password fields are never read")
        XCTAssertContains(text, "secure text fields")
        XCTAssertContains(text, "enable or disable")
        XCTAssertContains(text, "conversation context is opt-in")
        XCTAssertContains(text, "current input")
        XCTAssertContains(text, "llm provider receives")
        XCTAssertContains(text, "api key")
        XCTAssertContains(text, "clipboard fallback is opt-in")
    }

    private func XCTAssertContains(
        _ text: String,
        _ expectedPhrase: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let normalizedExpectedPhrase = expectedPhrase.normalizedForCopyAssertion()

        XCTAssertTrue(
            text.contains(normalizedExpectedPhrase),
            "Expected copy to contain '\(normalizedExpectedPhrase)' in: \(text)",
            file: file,
            line: line
        )
    }
}

private extension String {
    func normalizedForCopyAssertion() -> String {
        lowercased()
            .replacingOccurrences(of: "-", with: " ")
    }
}
