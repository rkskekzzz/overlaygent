import Foundation
import XCTest
@testable import Overlaygent

final class LLMResponseCacheTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("LLMResponseCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testSQLiteCacheStoresAndReadsRawResponseBeforeExpiration() throws {
        let cache = makeCache(ttl: 30 * 24 * 60 * 60)
        let cacheKey = "cache-key-before-expiration"
        let now = Date(timeIntervalSince1970: 1_000)
        let rawResponse = #"{"summary":null,"edits":[],"fullRewrite":"Can we deploy?"}"#

        try cache.storeRawResponse(rawResponse, forCacheKey: cacheKey, now: now)

        let cachedResponse = try cache.cachedRawResponse(
            forCacheKey: cacheKey,
            now: now.addingTimeInterval(60)
        )

        XCTAssertEqual(cachedResponse, rawResponse)
    }

    func testSQLiteCacheReturnsNilAndRemovesEntryAfterExpiration() throws {
        let cache = makeCache(ttl: 10)
        let cacheKey = "expired-cache-key"
        let now = Date(timeIntervalSince1970: 2_000)

        try cache.storeRawResponse("expired", forCacheKey: cacheKey, now: now)

        let expiredResponse = try cache.cachedRawResponse(
            forCacheKey: cacheKey,
            now: now.addingTimeInterval(11)
        )

        XCTAssertNil(expiredResponse)
    }

    func testCacheKeyChangesWhenProviderModelChanges() throws {
        let keyFactory = LLMResponseCacheKeyFactory()
        let bundle = messageBundle(input: "Same input")
        let firstProvider = providerConfig(defaultModel: "gpt-a")
        let secondProvider = providerConfig(defaultModel: "gpt-b")

        let firstKey = try keyFactory.cacheKey(for: bundle, provider: firstProvider)
        let secondKey = try keyFactory.cacheKey(for: bundle, provider: secondProvider)

        XCTAssertNotEqual(firstKey, secondKey)
    }

    func testCacheKeyIgnoresSelectedRangeLineForSameInput() throws {
        let keyFactory = LLMResponseCacheKeyFactory()
        let provider = providerConfig()
        let selectedBundle = messageBundle(
            input: "hello woorld",
            selectedRangeLine: "Selected range: 0..<11"
        )
        let caretBundle = messageBundle(
            input: "hello woorld",
            selectedRangeLine: "Selected range: 11..<11"
        )

        let selectedKey = try keyFactory.cacheKey(for: selectedBundle, provider: provider)
        let caretKey = try keyFactory.cacheKey(for: caretBundle, provider: provider)

        XCTAssertEqual(selectedKey, caretKey)
    }

    func testCacheKeyStillChangesWhenInputTextChanges() throws {
        let keyFactory = LLMResponseCacheKeyFactory()
        let provider = providerConfig()
        let firstBundle = messageBundle(input: "hello woorld")
        let secondBundle = messageBundle(input: "hello world")

        let firstKey = try keyFactory.cacheKey(for: firstBundle, provider: provider)
        let secondKey = try keyFactory.cacheKey(for: secondBundle, provider: provider)

        XCTAssertNotEqual(firstKey, secondKey)
    }

    private func makeCache(ttl: TimeInterval) -> SQLiteLLMResponseCache {
        SQLiteLLMResponseCache(
            fileURL: temporaryDirectory.appendingPathComponent("cache.sqlite3", isDirectory: false),
            ttl: ttl
        )
    }

    private func messageBundle(
        input: String,
        selectedRangeLine: String = "Selected range: None"
    ) -> AgentMessageBundle {
        AgentMessageBundle(
            agentID: UUID(uuidString: "00000000-0000-0000-0000-000000000701")!,
            agentName: "Grammar Fixer",
            providerID: UUID(uuidString: "00000000-0000-0000-0000-000000000702")!,
            resolvedModel: nil,
            messages: [
                AgentMessage(role: .system, content: "System"),
                AgentMessage(role: .developer, content: "Developer"),
                AgentMessage(
                    role: .user,
                    content: """
                    # Source
                    Bundle ID: com.example.Editor
                    Element role: AXTextArea
                    \(selectedRangeLine)

                    # Input
                    \(input)
                    """
                )
            ],
            outputSchemaID: "CorrectionResult",
            budgetMetadata: AgentMessageBudgetMetadata(
                characterBudget: nil,
                maxVisibleMessages: 0,
                includeConversationContext: false,
                inputCharacterCount: input.count,
                retainedInputCharacterCount: input.count,
                originalAgentTerminologyRuleCount: 0,
                retainedAgentTerminologyRuleCount: 0,
                originalMemoryTerminologyRuleCount: 0,
                retainedMemoryTerminologyRuleCount: 0,
                originalTonePreferenceCount: 0,
                retainedTonePreferenceCount: 0,
                originalWritingRuleCount: 0,
                retainedWritingRuleCount: 0,
                originalVisibleMessageCount: 0,
                retainedVisibleMessageCount: 0,
                didTrimForCharacterBudget: false,
                didTrimVisibleMessages: false
            )
        )
    }

    private func providerConfig(defaultModel: String = "gpt-cache") -> LLMProviderConfig {
        LLMProviderConfig.defaultOpenAICompatible(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000702")!,
            defaultModel: defaultModel
        )
    }
}
