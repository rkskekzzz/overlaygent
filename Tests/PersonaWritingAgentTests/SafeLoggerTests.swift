import XCTest
@testable import PersonaWritingAgent

final class SafeLoggerTests: XCTestCase {
    func testLoggerRedactsBuiltInAndCustomSensitiveValuesBeforeSink() {
        var messages: [String] = []
        let logger = SafeLogger(
            redactionRules: ["Project Nebula"],
            sink: { messages.append($0) }
        )

        logger.log(
            "Email sam@example.com with apiKey=sk-test1234567890ABCDEF and password=hunter2 for Project Nebula."
        )

        XCTAssertEqual(messages.count, 1)
        XCTAssertFalse(messages[0].contains("sam@example.com"))
        XCTAssertFalse(messages[0].contains("sk-test1234567890ABCDEF"))
        XCTAssertFalse(messages[0].contains("hunter2"))
        XCTAssertFalse(messages[0].contains("Project Nebula"))
        XCTAssertTrue(messages[0].contains("[REDACTED_EMAIL]"))
        XCTAssertTrue(messages[0].contains("[REDACTED_API_KEY]"))
        XCTAssertTrue(messages[0].contains("[REDACTED_PASSWORD]"))
        XCTAssertTrue(messages[0].contains("[REDACTED_CUSTOM]"))
    }
}
