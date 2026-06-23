import Foundation
import XCTest
@testable import Overlaygent

final class SlackContextAdapterTests: XCTestCase {
    func testSupportsSlackBundleID() {
        let adapter = SlackContextAdapter()

        XCTAssertEqual(adapter.supportedBundleIDs, ["com.tinyspeck.slackmacgap"])
    }

    func testExtractsMessagesFromFixtureTree() throws {
        let fixture = FixtureSlackAXTreeReader()
        let firstRow = fixture.messageRow(author: "Sam", time: "10:41 AM", text: "Can we ship after review?")
        let secondRow = fixture.messageRow(author: "Alex", time: "10:42 AM", text: "Looks good to me.")
        let messageList = fixture.makeNode(role: "AXGroup", children: [firstRow, secondRow])
        let input = fixture.makeNode(role: "AXTextArea", value: "Draft reply")
        let window = fixture.makeNode(role: "AXWindow", title: "#release", children: [messageList, input])
        fixture.setChildren([messageList, input], for: window)
        let adapter = SlackContextAdapter(
            accessibilityTree: fixture,
            uuidGenerator: SequentialUUIDGenerator().next
        )

        let context = try XCTUnwrap(adapter.extractContext(for: request(focusedElement: input, maxVisibleMessages: 10)))

        XCTAssertEqual(context.appBundleID, "com.tinyspeck.slackmacgap")
        XCTAssertEqual(context.conversationTitle, "#release")
        XCTAssertEqual(
            context.visibleMessages.map { message in
                ExtractedMessage(author: message.author, text: message.text)
            },
            [
                ExtractedMessage(author: "Sam", text: "Can we ship after review?"),
                ExtractedMessage(author: "Alex", text: "Looks good to me.")
            ]
        )
        XCTAssertTrue(context.visibleMessages.allSatisfy { $0.timestamp == nil })
    }

    func testLimitsToMostRecentVisibleMessages() throws {
        let fixture = FixtureSlackAXTreeReader()
        let messageList = fixture.makeNode(
            role: "AXGroup",
            children: [
                fixture.messageRow(author: "Sam", time: "10:40 AM", text: "First message"),
                fixture.messageRow(author: "Alex", time: "10:41 AM", text: "Second message"),
                fixture.messageRow(author: "Lee", time: "10:42 AM", text: "Third message")
            ]
        )
        let input = fixture.makeNode(role: "AXTextArea", value: "Draft reply")
        let window = fixture.makeNode(role: "AXWindow", title: "#release", children: [messageList, input])
        fixture.setChildren([messageList, input], for: window)
        let adapter = SlackContextAdapter(
            accessibilityTree: fixture,
            uuidGenerator: SequentialUUIDGenerator().next
        )

        let context = try XCTUnwrap(adapter.extractContext(for: request(focusedElement: input, maxVisibleMessages: 2)))

        XCTAssertEqual(context.visibleMessages.map(\.text), ["Second message", "Third message"])
        XCTAssertEqual(context.visibleMessages.map(\.author), ["Alex", "Lee"])
    }

    func testMalformedTreeFallsBackToEmptyContext() throws {
        let fixture = FixtureSlackAXTreeReader()
        let missingFixtureElement = AXElement(FixtureSlackAXNode())
        let adapter = SlackContextAdapter(accessibilityTree: fixture)

        let context = try XCTUnwrap(
            adapter.extractContext(
                for: request(
                    focusedElement: missingFixtureElement,
                    maxVisibleMessages: 5
                )
            )
        )

        XCTAssertEqual(context.appBundleID, "com.tinyspeck.slackmacgap")
        XCTAssertNil(context.conversationTitle)
        XCTAssertEqual(context.visibleMessages, [])
    }

    private func request(
        focusedElement element: AXElement,
        maxVisibleMessages: Int
    ) -> AppContextExtractionRequest {
        AppContextExtractionRequest(
            snapshot: TextSnapshot(
                text: "Draft reply",
                selectedRange: nil,
                sourceBundleID: "com.tinyspeck.slackmacgap",
                sourceElementRole: "AXTextArea",
                contentHash: "sha256:test"
            ),
            focusedElement: AXFocusedElement(
                element: element,
                role: "AXTextArea",
                subrole: nil,
                value: "Draft reply",
                selectedRange: nil
            ),
            includeConversationContext: true,
            maxVisibleMessages: maxVisibleMessages
        )
    }
}

private struct ExtractedMessage: Equatable {
    var author: String?
    var text: String
}

private final class SequentialUUIDGenerator {
    private var counter: UInt64 = 0

    func next() -> UUID {
        counter += 1

        return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llu", counter))!
    }
}

private final class FixtureSlackAXNode: NSObject {}

private final class FixtureSlackAXTreeReader: SlackAXTreeReading {
    private var snapshotsByElement: [AXElement: SlackAXNodeSnapshot] = [:]
    private var childrenByElement: [AXElement: [AXElement]] = [:]
    private var parentsByElement: [AXElement: AXElement] = [:]

    func snapshot(for element: AXElement) -> SlackAXNodeSnapshot? {
        snapshotsByElement[element]
    }

    func children(of element: AXElement) -> [AXElement] {
        childrenByElement[element] ?? []
    }

    func parent(of element: AXElement) -> AXElement? {
        parentsByElement[element]
    }

    func makeNode(
        role: String,
        subrole: String? = nil,
        title: String? = nil,
        value: String? = nil,
        description: String? = nil,
        identifier: String? = nil,
        children: [AXElement] = []
    ) -> AXElement {
        let element = AXElement(FixtureSlackAXNode())
        snapshotsByElement[element] = SlackAXNodeSnapshot(
            role: role,
            subrole: subrole,
            title: title,
            value: value,
            description: description,
            identifier: identifier
        )
        setChildren(children, for: element)

        return element
    }

    func messageRow(author: String, time: String, text: String) -> AXElement {
        makeNode(
            role: "AXGroup",
            identifier: "message-row",
            children: [
                makeNode(role: "AXStaticText", value: author),
                makeNode(role: "AXStaticText", value: time),
                makeNode(role: "AXStaticText", value: text)
            ]
        )
    }

    func setChildren(_ children: [AXElement], for element: AXElement) {
        childrenByElement[element] = children

        for child in children {
            parentsByElement[child] = element
        }
    }
}
