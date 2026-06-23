import Foundation
import XCTest
@testable import Overlaygent

final class AppContextAdapterTests: XCTestCase {
    func testRequestDefaultsToContextOptOutAndClampsNegativeMessageLimit() {
        let request = AppContextExtractionRequest(
            snapshot: snapshot(sourceBundleID: "com.tinyspeck.slackmacgap"),
            maxVisibleMessages: -10
        )

        XCTAssertFalse(request.includeConversationContext)
        XCTAssertEqual(request.maxVisibleMessages, 0)
        XCTAssertEqual(request.sourceBundleID, "com.tinyspeck.slackmacgap")
        XCTAssertNil(request.focusedElement)
    }

    func testGenericAdapterReturnsNilForOptInRequestWithoutCrashing() {
        let adapter = GenericAXContextAdapter()
        let request = AppContextExtractionRequest(
            snapshot: snapshot(sourceBundleID: "com.unknown.App"),
            includeConversationContext: true,
            maxVisibleMessages: 5
        )

        let context = adapter.extractContext(for: request)

        XCTAssertNil(context)
        XCTAssertEqual(adapter.supportedBundleIDs, [])
    }

    func testRegistryDoesNotCallAdaptersWhenContextIsNotOptedIn() {
        let adapter = RecordingAppContextAdapter(
            supportedBundleIDs: ["com.tinyspeck.slackmacgap"],
            result: context(appBundleID: "com.tinyspeck.slackmacgap")
        )
        let registry = AppContextAdapterRegistry(adapters: [adapter])
        let request = AppContextExtractionRequest(
            snapshot: snapshot(sourceBundleID: "com.tinyspeck.slackmacgap"),
            includeConversationContext: false,
            maxVisibleMessages: 5
        )

        let resolvedContext = registry.context(for: request)

        XCTAssertNil(resolvedContext)
        XCTAssertEqual(adapter.requests, [])
    }

    func testRegistryUsesRegisteredAdapterForMatchingBundleID() {
        let expectedContext = context(appBundleID: "com.tinyspeck.slackmacgap")
        let adapter = RecordingAppContextAdapter(
            supportedBundleIDs: [" com.tinyspeck.slackmacgap "],
            result: expectedContext
        )
        let registry = AppContextAdapterRegistry(adapters: [adapter])
        let request = AppContextExtractionRequest(
            snapshot: snapshot(sourceBundleID: "com.tinyspeck.slackmacgap"),
            includeConversationContext: true,
            maxVisibleMessages: 3
        )

        let resolvedContext = registry.context(for: request)

        XCTAssertEqual(resolvedContext, expectedContext)
        XCTAssertEqual(adapter.requests, [request])
    }

    func testDefaultRegistryIncludesKnownElectronContextAdapters() {
        let registry = AppContextAdapterRegistry()

        XCTAssertTrue(registry.adapter(for: " COM.TINYSPECK.SLACKMACGAP ") is SlackContextAdapter)
        XCTAssertTrue(registry.adapter(for: "com.zoyi.channel.desk.osx") is ChannelTalkContextAdapter)
    }

    func testRegistryFallsBackToGenericAdapterForUnknownBundleID() {
        let adapter = RecordingAppContextAdapter(
            supportedBundleIDs: ["com.tinyspeck.slackmacgap"],
            result: context(appBundleID: "com.tinyspeck.slackmacgap")
        )
        let registry = AppContextAdapterRegistry(adapters: [adapter])
        let request = AppContextExtractionRequest(
            snapshot: snapshot(sourceBundleID: "com.apple.TextEdit"),
            includeConversationContext: true,
            maxVisibleMessages: 5
        )

        let resolvedContext = registry.context(for: request)

        XCTAssertNil(resolvedContext)
        XCTAssertEqual(adapter.requests, [])
    }

    func testRegistryTreatsAdapterFailureAsNoContextFallback() {
        let adapter = RecordingAppContextAdapter(
            supportedBundleIDs: ["com.zoyi.channel.desk.osx"],
            error: TestContextAdapterError.extractionFailed
        )
        let registry = AppContextAdapterRegistry(adapters: [adapter])
        let request = AppContextExtractionRequest(
            snapshot: snapshot(sourceBundleID: "com.zoyi.channel.desk.osx"),
            includeConversationContext: true,
            maxVisibleMessages: 5
        )

        let resolvedContext = registry.context(for: request)

        XCTAssertNil(resolvedContext)
        XCTAssertEqual(adapter.requests, [request])
    }

    private func snapshot(sourceBundleID: String) -> TextSnapshot {
        TextSnapshot(
            text: "Can we deploy it after review?",
            selectedRange: nil,
            sourceBundleID: sourceBundleID,
            sourceElementRole: "AXTextArea",
            contentHash: "sha256:test"
        )
    }

    private func context(appBundleID: String) -> ConversationContext {
        ConversationContext(
            appBundleID: appBundleID,
            conversationTitle: "#release",
            visibleMessages: [
                ConversationMessage(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000401")!,
                    author: "Sam",
                    timestamp: Date(timeIntervalSince1970: 1_780_000_000),
                    text: "Can we ship after review?"
                )
            ]
        )
    }
}

private enum TestContextAdapterError: Error {
    case extractionFailed
}

private final class RecordingAppContextAdapter: AppContextAdapter {
    let supportedBundleIDs: Set<String>
    private let result: ConversationContext?
    private let error: Error?
    private(set) var requests: [AppContextExtractionRequest] = []

    init(
        supportedBundleIDs: Set<String>,
        result: ConversationContext? = nil,
        error: Error? = nil
    ) {
        self.supportedBundleIDs = supportedBundleIDs
        self.result = result
        self.error = error
    }

    func extractContext(for request: AppContextExtractionRequest) throws -> ConversationContext? {
        requests.append(request)

        if let error {
            throw error
        }

        return result
    }
}
