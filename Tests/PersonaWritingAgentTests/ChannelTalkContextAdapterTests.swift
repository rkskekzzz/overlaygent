import Foundation
import XCTest
@testable import PersonaWritingAgent

final class ChannelTalkContextAdapterTests: XCTestCase {
    func testSupportsChannelTalkBundleID() {
        let adapter = ChannelTalkContextAdapter(treeReader: FakeChannelTalkAXTreeReader(tree: nil))
        let registry = AppContextAdapterRegistry()

        XCTAssertEqual(adapter.supportedBundleIDs, [ChannelTalkContextAdapter.bundleID])
        XCTAssertTrue(registry.adapter(for: ChannelTalkContextAdapter.bundleID) is ChannelTalkContextAdapter)
    }

    func testExtractsMessagesFromFixtureTree() throws {
        let rootElement = AXElement(FakeAXNode())
        let reader = FakeChannelTalkAXTreeReader(
            tree: ChannelTalkAXNode(
                role: "AXGroup",
                title: "Acme Support",
                children: [
                    messageRow(
                        author: "Mina",
                        timestamp: "2026-06-15T00:01:00Z",
                        text: "Can we ship after review?"
                    ),
                    messageRow(
                        author: "Joon",
                        timestamp: "2026-06-15T00:03:00Z",
                        text: "Please wait for QA signoff."
                    )
                ]
            )
        )
        let adapter = ChannelTalkContextAdapter(
            treeReader: reader,
            messageIDFactory: UUIDSequence([
                "00000000-0000-0000-0000-000000000701",
                "00000000-0000-0000-0000-000000000702"
            ]).next
        )

        let context = try XCTUnwrap(
            adapter.extractContext(
                for: request(focusedElement: rootElement, maxVisibleMessages: 5)
            )
        )

        XCTAssertEqual(reader.requestedRootElements, [rootElement])
        XCTAssertEqual(context.appBundleID, ChannelTalkContextAdapter.bundleID)
        XCTAssertEqual(context.conversationTitle, "Acme Support")
        XCTAssertEqual(context.visibleMessages.map(\.author), ["Mina", "Joon"])
        XCTAssertEqual(context.visibleMessages.map(\.text), [
            "Can we ship after review?",
            "Please wait for QA signoff."
        ])
        XCTAssertEqual(
            context.visibleMessages.map(\.timestamp),
            [
                ISO8601DateFormatter().date(from: "2026-06-15T00:01:00Z"),
                ISO8601DateFormatter().date(from: "2026-06-15T00:03:00Z")
            ]
        )
    }

    func testLimitsToMostRecentVisibleMessages() throws {
        let reader = FakeChannelTalkAXTreeReader(
            tree: ChannelTalkAXNode(
                role: "AXGroup",
                children: [
                    messageRow(author: "Mina", timestamp: "09:00", text: "First visible message"),
                    messageRow(author: "Joon", timestamp: "09:01", text: "Second visible message"),
                    messageRow(author: "Rae", timestamp: "09:02", text: "Third visible message")
                ]
            )
        )
        let adapter = ChannelTalkContextAdapter(treeReader: reader)

        let context = try XCTUnwrap(
            adapter.extractContext(
                for: request(focusedElement: AXElement(FakeAXNode()), maxVisibleMessages: 2)
            )
        )

        XCTAssertEqual(context.visibleMessages.map(\.text), [
            "Second visible message",
            "Third visible message"
        ])
    }

    func testMalformedTreeFallsBackToEmptyContextWithoutThrowing() throws {
        let adapter = ChannelTalkContextAdapter(
            treeReader: FakeChannelTalkAXTreeReader(
                tree: ChannelTalkAXNode(
                    role: "AXGroup",
                    children: [
                        ChannelTalkAXNode(role: "AXButton", title: "Send"),
                        ChannelTalkAXNode(role: "AXImage", label: "Avatar")
                    ]
                )
            )
        )

        let context = try XCTUnwrap(
            adapter.extractContext(
                for: request(focusedElement: AXElement(FakeAXNode()), maxVisibleMessages: 5)
            )
        )

        XCTAssertNil(context.conversationTitle)
        XCTAssertEqual(context.visibleMessages, [])
    }

    private func request(focusedElement: AXElement, maxVisibleMessages: Int) -> AppContextExtractionRequest {
        AppContextExtractionRequest(
            snapshot: TextSnapshot(
                text: "Draft reply",
                selectedRange: nil,
                sourceBundleID: ChannelTalkContextAdapter.bundleID,
                sourceElementRole: "AXTextArea",
                contentHash: "sha256:channel-talk"
            ),
            focusedElement: AXFocusedElement(
                element: focusedElement,
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

private func messageRow(author: String, timestamp: String, text: String) -> ChannelTalkAXNode {
    ChannelTalkAXNode(
        role: "AXGroup",
        children: [
            ChannelTalkAXNode(role: "AXStaticText", value: author),
            ChannelTalkAXNode(role: "AXStaticText", value: timestamp),
            ChannelTalkAXNode(role: "AXStaticText", value: text)
        ]
    )
}

private final class FakeChannelTalkAXTreeReader: ChannelTalkAXTreeReading {
    private let tree: ChannelTalkAXNode?
    private(set) var requestedRootElements: [AXElement] = []

    init(tree: ChannelTalkAXNode?) {
        self.tree = tree
    }

    func tree(rootedAt element: AXElement) -> ChannelTalkAXNode? {
        requestedRootElements.append(element)

        return tree
    }
}

private final class UUIDSequence {
    private var values: [UUID]

    init(_ values: [String]) {
        self.values = values.compactMap(UUID.init(uuidString:))
    }

    func next() -> UUID {
        values.removeFirst()
    }
}

private final class FakeAXNode: NSObject {}
