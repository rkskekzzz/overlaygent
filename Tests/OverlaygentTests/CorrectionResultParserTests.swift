import Foundation
import XCTest
@testable import Overlaygent

final class CorrectionResultParserTests: XCTestCase {
    func testParsesPRDExampleJSONObject() throws {
        let response = """
        {
          "summary": "Made the message more natural and concise.",
          "edits": [
            {
              "rangeStart": 12,
              "rangeEnd": 28,
              "original": "make a deploy",
              "replacement": "deploy it",
              "reason": "More natural engineering phrasing"
            }
          ],
          "fullRewrite": "Can we deploy it after the PR is approved?"
        }
        """

        let result = try CorrectionResultParser().parse(response)

        XCTAssertEqual(result.summary, "Made the message more natural and concise.")
        XCTAssertEqual(result.fullRewrite, "Can we deploy it after the PR is approved?")
        XCTAssertEqual(result.edits.count, 1)
        XCTAssertEqual(result.edits[0].rangeStart, 12)
        XCTAssertEqual(result.edits[0].rangeEnd, 28)
        XCTAssertEqual(result.edits[0].range, 12..<28)
        XCTAssertEqual(result.edits[0].original, "make a deploy")
        XCTAssertEqual(result.edits[0].replacement, "deploy it")
        XCTAssertEqual(result.edits[0].reason, "More natural engineering phrasing")
    }

    func testParsesMarkdownFencedJSON() throws {
        let response = """
        Here is the correction result:

        ```json
        {
          "summary": "Shortened the sentence.",
          "edits": [
            {
              "rangeStart": 0,
              "rangeEnd": 8,
              "original": "I think ",
              "replacement": "",
              "reason": "Remove filler wording"
            }
          ]
        }
        ```
        """

        let result = try CorrectionResultParser().parse(response)

        XCTAssertEqual(result.summary, "Shortened the sentence.")
        XCTAssertNil(result.fullRewrite)
        XCTAssertEqual(result.edits[0].replacement, "")
    }

    func testParsesJSONObjectWrappedInExplanatoryText() throws {
        let response = """
        Sure, I would apply this:
        {
          "edits": [
            {
              "rangeStart": 5,
              "rangeEnd": 9,
              "original": "ship",
              "replacement": "deploy",
              "reason": "Use project terminology"
            }
          ]
        }
        Let me know if you want a stronger rewrite.
        """

        let result = try CorrectionResultParser().parse(response)

        XCTAssertNil(result.summary)
        XCTAssertNil(result.fullRewrite)
        XCTAssertEqual(result.edits[0].range, 5..<9)
        XCTAssertEqual(result.edits[0].replacement, "deploy")
    }

    func testAllowsFullRewriteFallbackWithoutEdits() throws {
        let response = """
        {
          "fullRewrite": "Can we deploy it after the pull request is approved?"
        }
        """

        let result = try CorrectionResultParser().parse(response)

        XCTAssertEqual(result.edits, [])
        XCTAssertEqual(result.fullRewrite, "Can we deploy it after the pull request is approved?")
    }

    func testAllowsEmptyReplacementForDeletionEdits() throws {
        let response = """
        {
          "edits": [
            {
              "rangeStart": 4,
              "rangeEnd": 9,
              "original": " just",
              "replacement": "",
              "reason": "Delete filler"
            }
          ]
        }
        """

        let result = try CorrectionResultParser().parse(response)

        XCTAssertEqual(result.edits[0].original, " just")
        XCTAssertEqual(result.edits[0].replacement, "")
    }

    func testRejectsEmptyOriginalForEdit() {
        let response = """
        {
          "edits": [
            {
              "rangeStart": 4,
              "rangeEnd": 4,
              "original": "",
              "replacement": "please ",
              "reason": "Insert politeness"
            }
          ]
        }
        """

        XCTAssertThrowsError(try CorrectionResultParser().parse(response)) { error in
            XCTAssertEqual(error as? CorrectionResultParserError, .emptyOriginal(editIndex: 0))
        }
    }

    func testRejectsNegativeRangeStart() {
        let response = """
        {
          "edits": [
            {
              "rangeStart": -1,
              "rangeEnd": 4,
              "original": "test",
              "replacement": "demo",
              "reason": "Invalid start"
            }
          ]
        }
        """

        XCTAssertThrowsError(try CorrectionResultParser().parse(response)) { error in
            XCTAssertEqual(
                error as? CorrectionResultParserError,
                .invalidRange(editIndex: 0, start: -1, end: 4)
            )
        }
    }

    func testRejectsRangeEndBeforeStart() {
        let response = """
        {
          "edits": [
            {
              "rangeStart": 9,
              "rangeEnd": 4,
              "original": "test",
              "replacement": "demo",
              "reason": "Invalid end"
            }
          ]
        }
        """

        XCTAssertThrowsError(try CorrectionResultParser().parse(response)) { error in
            XCTAssertEqual(
                error as? CorrectionResultParserError,
                .invalidRange(editIndex: 0, start: 9, end: 4)
            )
        }
    }

    func testRejectsMalformedJSON() {
        let response = """
        {
          "edits": [
            {
              "rangeStart": 0,
              "rangeEnd": 4
              "original": "ship",
              "replacement": "deploy",
              "reason": "Use project terminology"
            }
          ]
        }
        """

        XCTAssertThrowsError(try CorrectionResultParser().parse(response)) { error in
            guard case .malformedJSON = error as? CorrectionResultParserError else {
                return XCTFail("Expected malformedJSON, got \(error)")
            }
        }
    }

    func testRejectsMissingUsableFields() {
        let response = """
        {
          "summary": "No edits needed.",
          "edits": [],
          "fullRewrite": "   "
        }
        """

        XCTAssertThrowsError(try CorrectionResultParser().parse(response)) { error in
            XCTAssertEqual(error as? CorrectionResultParserError, .missingUsableFields)
        }
    }
}
