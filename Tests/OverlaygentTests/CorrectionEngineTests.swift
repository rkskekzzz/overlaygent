import Foundation
import XCTest
@testable import Overlaygent

final class CorrectionEngineTests: XCTestCase {
    func testRunAppliesPrivacyGuardBeforeBuildingBundlesAndCallingProvider() async throws {
        let providerID = UUID(uuidString: "00000000-0000-0000-0000-000000000601")!
        let secret = "Project Nebula"
        let providerConfig = providerConfig(id: providerID)
        let llmProvider = MockLLMProvider(
            responsesByAgentID: [
                agentID(1): .success(successResponse(replacement: "Launch [REDACTED_CUSTOM]."))
            ]
        )
        let engine = correctionEngine(
            providers: [providerConfig],
            apiKeys: [providerID: "sk-test-secret"],
            llmProvider: llmProvider
        )
        let request = runRequest(
            inputText: "Launch \(secret).",
            activeAgents: [
                agent(idSuffix: 1, providerID: providerID, systemPrompt: "Do not reveal \(secret).")
            ],
            privacyPolicy: privacyPolicy(redactionRules: [secret])
        )

        let results = try await engine.run(request)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].result?.fullRewrite, "Launch [REDACTED_CUSTOM].")

        let capturedBundle = try XCTUnwrap(llmProvider.capturedCalls.first?.bundle)
        let encodedBundle = String(data: try JSONEncoder().encode(capturedBundle), encoding: .utf8)!
        XCTAssertFalse(encodedBundle.contains(secret))
        XCTAssertTrue(encodedBundle.contains("[REDACTED_CUSTOM]"))
    }

    func testRunUsesBundleProviderConfigurationModelOverrideAndAPIKey() async throws {
        let providerID = UUID(uuidString: "00000000-0000-0000-0000-000000000602")!
        let providerConfig = providerConfig(
            id: providerID,
            name: "Primary Provider",
            defaultModel: "provider-default-model"
        )
        let llmProvider = MockLLMProvider(
            responsesByAgentID: [
                agentID(2): .success(successResponse(replacement: "Can we deploy it?"))
            ]
        )
        let engine = correctionEngine(
            providers: [providerConfig],
            apiKeys: [providerID: "sk-test-primary"],
            llmProvider: llmProvider
        )
        let request = runRequest(
            activeAgents: [
                agent(
                    idSuffix: 2,
                    providerID: providerID,
                    modelOverride: " gpt-agent-model "
                )
            ]
        )

        _ = try await engine.run(request)

        let capturedCall = try XCTUnwrap(llmProvider.capturedCalls.first)
        XCTAssertEqual(capturedCall.provider, providerConfig)
        XCTAssertEqual(capturedCall.apiKey, "sk-test-primary")
        XCTAssertEqual(capturedCall.bundle.providerID, providerID)
        XCTAssertEqual(capturedCall.bundle.resolvedModel, "gpt-agent-model")
    }

    func testRunReturnsParsedResultAndRawResponseForSuccessfulAgent() async throws {
        let providerID = UUID(uuidString: "00000000-0000-0000-0000-000000000603")!
        let rawResponse = """
        Here is the result:
        {
          "summary": "Improved deployment phrasing.",
          "edits": [
            {
              "rangeStart": 8,
              "rangeEnd": 19,
              "original": "make deploy",
              "replacement": "deploy it",
              "reason": "Natural engineering phrasing"
            }
          ],
          "fullRewrite": "Can we deploy it after review?"
        }
        """
        let engine = correctionEngine(
            providers: [providerConfig(id: providerID)],
            apiKeys: [providerID: "sk-test-success"],
            llmProvider: MockLLMProvider(responsesByAgentID: [agentID(3): .success(rawResponse)])
        )
        let request = runRequest(activeAgents: [agent(idSuffix: 3, providerID: providerID)])

        let results = try await engine.run(request)

        let result = try XCTUnwrap(results.first)
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.rawResponse, rawResponse)
        XCTAssertNil(result.failure)
        XCTAssertEqual(result.result?.summary, "Improved deployment phrasing.")
        XCTAssertEqual(result.result?.fullRewrite, "Can we deploy it after review?")
        XCTAssertEqual(result.result?.edits.first?.range, 8..<19)
        XCTAssertEqual(result.result?.edits.first?.replacement, "deploy it")
    }

    func testRunUsesCachedResponseWithoutCallingProvider() async throws {
        let providerID = UUID(uuidString: "00000000-0000-0000-0000-000000000631")!
        let rawResponse = successResponse(replacement: "Cached rewrite.")
        let llmProvider = MockLLMProvider(responsesByAgentID: [:])
        let responseCache = FakeLLMResponseCache(cachedRawResponse: rawResponse)
        let engine = correctionEngine(
            providers: [providerConfig(id: providerID)],
            apiKeys: [providerID: "sk-test-cache"],
            llmProvider: llmProvider,
            responseCache: responseCache
        )
        let request = runRequest(activeAgents: [agent(idSuffix: 31, providerID: providerID)])

        let results = try await engine.run(request)

        XCTAssertEqual(results.first?.result?.fullRewrite, "Cached rewrite.")
        XCTAssertTrue(llmProvider.capturedCalls.isEmpty)
        XCTAssertEqual(responseCache.cachedLookups.count, 1)
        XCTAssertTrue(responseCache.storedResponses.isEmpty)
    }

    func testRunUsesCachedResponseBeforeReadingAPIKey() async throws {
        let providerID = UUID(uuidString: "00000000-0000-0000-0000-000000000633")!
        let rawResponse = successResponse(replacement: "Cached without keychain.")
        let llmProvider = MockLLMProvider(responsesByAgentID: [:])
        let responseCache = FakeLLMResponseCache(cachedRawResponse: rawResponse)
        let apiKeyStore = FakeAPIKeyStore(apiKeysByProviderID: [:])
        let engine = CorrectionEngine(
            providerConfigLoader: FakeProviderConfigLoader(providers: [providerConfig(id: providerID)]),
            apiKeyStore: apiKeyStore,
            llmProvider: llmProvider,
            responseCache: responseCache
        )
        let request = runRequest(activeAgents: [agent(idSuffix: 33, providerID: providerID)])

        let results = try await engine.run(request)

        XCTAssertEqual(results.first?.result?.fullRewrite, "Cached without keychain.")
        XCTAssertTrue(apiKeyStore.readProviderIDs.isEmpty)
        XCTAssertTrue(llmProvider.capturedCalls.isEmpty)
    }

    func testRunStoresSuccessfulProviderResponseInCache() async throws {
        let providerID = UUID(uuidString: "00000000-0000-0000-0000-000000000632")!
        let rawResponse = successResponse(replacement: "Fresh rewrite.")
        let responseCache = FakeLLMResponseCache()
        let engine = correctionEngine(
            providers: [providerConfig(id: providerID)],
            apiKeys: [providerID: "sk-test-cache-store"],
            llmProvider: MockLLMProvider(responsesByAgentID: [agentID(32): .success(rawResponse)]),
            responseCache: responseCache
        )
        let request = runRequest(activeAgents: [agent(idSuffix: 32, providerID: providerID)])

        let results = try await engine.run(request)

        XCTAssertEqual(results.first?.result?.fullRewrite, "Fresh rewrite.")
        XCTAssertEqual(responseCache.storedResponses.map(\.rawResponse), [rawResponse])
        XCTAssertEqual(responseCache.storedResponses.first?.cacheKey.isEmpty, false)
    }

    func testRunKeepsProcessingAfterPerAgentFailures() async throws {
        let successProviderID = UUID(uuidString: "00000000-0000-0000-0000-000000000604")!
        let missingKeyProviderID = UUID(uuidString: "00000000-0000-0000-0000-000000000605")!
        let providerFailureID = UUID(uuidString: "00000000-0000-0000-0000-000000000606")!
        let parserFailureID = UUID(uuidString: "00000000-0000-0000-0000-000000000607")!
        let missingProviderID = UUID(uuidString: "00000000-0000-0000-0000-000000000608")!
        let secretAPIKey = "sk-test-provider-secret"
        let llmProvider = MockLLMProvider(
            responsesByAgentID: [
                agentID(4): .success(successResponse(replacement: "Successful rewrite.")),
                agentID(6): .failure(MockProviderError.transport),
                agentID(7): .success("not-json")
            ]
        )
        let engine = correctionEngine(
            providers: [
                providerConfig(id: successProviderID),
                providerConfig(id: missingKeyProviderID),
                providerConfig(id: providerFailureID),
                providerConfig(id: parserFailureID)
            ],
            apiKeys: [
                successProviderID: "sk-test-success",
                providerFailureID: secretAPIKey,
                parserFailureID: "sk-test-parser"
            ],
            llmProvider: llmProvider
        )
        let request = runRequest(
            activeAgents: [
                agent(idSuffix: 4, name: "Success", providerID: successProviderID),
                agent(idSuffix: 5, name: "Missing API Key", providerID: missingKeyProviderID),
                agent(idSuffix: 6, name: "Provider Failure", providerID: providerFailureID),
                agent(idSuffix: 7, name: "Parser Failure", providerID: parserFailureID),
                agent(idSuffix: 8, name: "Missing Provider", providerID: missingProviderID)
            ]
        )

        let results = try await engine.run(request)

        XCTAssertEqual(results.map(\.agentName), [
            "Success",
            "Missing API Key",
            "Provider Failure",
            "Parser Failure",
            "Missing Provider"
        ])
        XCTAssertEqual(results[0].result?.fullRewrite, "Successful rewrite.")
        XCTAssertEqual(results[1].failure, .missingAPIKey(providerID: missingKeyProviderID))
        XCTAssertEqual(
            results[2].failure,
            .providerFailed(providerID: providerFailureID, reason: "transport")
        )
        XCTAssertEqual(results[3].failure, .parseFailed(providerID: parserFailureID))
        XCTAssertEqual(results[4].failure, .missingProvider(providerID: missingProviderID))
        XCTAssertEqual(llmProvider.capturedCalls.map(\.bundle.agentID), [agentID(4), agentID(6), agentID(7)])
        XCTAssertFalse(String(describing: results[2].failure).contains(secretAPIKey))
    }

    private func correctionEngine(
        providers: [LLMProviderConfig],
        apiKeys: [UUID: String],
        llmProvider: MockLLMProvider,
        responseCache: any LLMResponseCaching = NoopLLMResponseCache()
    ) -> CorrectionEngine {
        CorrectionEngine(
            providerConfigLoader: FakeProviderConfigLoader(providers: providers),
            apiKeyStore: FakeAPIKeyStore(apiKeysByProviderID: apiKeys),
            llmProvider: llmProvider,
            responseCache: responseCache
        )
    }

    private func runRequest(
        inputText: String = "Can we make deploy after review?",
        activeAgents: [AgentProfile],
        privacyPolicy: PrivacyPolicy = privacyPolicy()
    ) -> AgentRunRequest {
        AgentRunRequest(
            input: TextSnapshot(
                text: inputText,
                selectedRange: 0..<inputText.count,
                sourceBundleID: "com.example.Editor",
                sourceElementRole: "AXTextArea",
                contentHash: "sha256:correction-engine"
            ),
            activeAgents: activeAgents,
            appContext: ConversationContext(
                appBundleID: "com.example.Editor",
                conversationTitle: "#release",
                visibleMessages: [
                    ConversationMessage(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000620")!,
                        author: "Sam",
                        timestamp: nil,
                        text: "Can we ship this?"
                    )
                ]
            ),
            memory: AgentMemory(
                terminologyRules: [
                    TerminologyRule(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000621")!,
                        match: "make deploy",
                        replacement: "deploy it",
                        note: nil,
                        isCaseSensitive: false
                    )
                ],
                tonePreferences: ["concise"],
                writingRules: ["Keep intent."]
            ),
            privacyPolicy: privacyPolicy
        )
    }

    private static func privacyPolicy(
        includeConversationContext: Bool = true,
        maxVisibleMessages: Int = 5,
        allowClipboardFallback: Bool = false,
        redactionRules: [String] = []
    ) -> PrivacyPolicy {
        PrivacyPolicy(
            includeConversationContext: includeConversationContext,
            maxVisibleMessages: maxVisibleMessages,
            allowClipboardFallback: allowClipboardFallback,
            redactionRules: redactionRules
        )
    }

    private func privacyPolicy(
        includeConversationContext: Bool = true,
        maxVisibleMessages: Int = 5,
        allowClipboardFallback: Bool = false,
        redactionRules: [String] = []
    ) -> PrivacyPolicy {
        Self.privacyPolicy(
            includeConversationContext: includeConversationContext,
            maxVisibleMessages: maxVisibleMessages,
            allowClipboardFallback: allowClipboardFallback,
            redactionRules: redactionRules
        )
    }

    private func agent(
        idSuffix: Int,
        name: String = "Grammar Fixer",
        providerID: UUID,
        modelOverride: String? = nil,
        systemPrompt: String = "You are a careful editor."
    ) -> AgentProfile {
        AgentProfile(
            id: agentID(idSuffix),
            name: name,
            description: "\(name) description",
            isEnabled: true,
            isActive: true,
            providerID: providerID,
            modelOverride: modelOverride,
            systemPrompt: systemPrompt,
            instruction: "Improve the text while preserving intent.",
            tone: .neutral,
            aggressiveness: .conservative,
            scope: .currentInput,
            terminologyRules: [],
            enabledBundleIDs: [],
            disabledBundleIDs: [],
            applyMode: .askEveryTime
        )
    }

    private func agentID(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 600 + suffix))!
    }

    private func providerConfig(
        id: UUID,
        name: String = "OpenAI Compatible",
        defaultModel: String = "gpt-4.1-mini"
    ) -> LLMProviderConfig {
        LLMProviderConfig(
            id: id,
            name: name,
            baseURL: URL(string: "https://api.example.com/v1")!,
            defaultModel: defaultModel,
            temperature: 0.2,
            maxTokens: 1_200,
            timeoutSeconds: 30,
            keychainServiceName: "Overlaygent.LLMProvider.\(id.uuidString)"
        )
    }

    private func successResponse(replacement: String) -> String {
        """
        {
          "edits": [
            {
              "rangeStart": 0,
              "rangeEnd": 3,
              "original": "Can",
              "replacement": "Could",
              "reason": "Softer wording"
            }
          ],
          "fullRewrite": "\(replacement)"
        }
        """
    }
}

private struct FakeProviderConfigLoader: LLMProviderConfigLoading {
    var providers: [LLMProviderConfig]

    func loadProviders() throws -> [LLMProviderConfig] {
        providers
    }
}

private final class FakeAPIKeyStore: LLMProviderAPIKeyStoring {
    private let apiKeysByProviderID: [UUID: String]
    private(set) var readProviderIDs: [UUID] = []

    init(apiKeysByProviderID: [UUID: String]) {
        self.apiKeysByProviderID = apiKeysByProviderID
    }

    func saveAPIKey(_ apiKey: String, for provider: LLMProviderConfig) throws {}

    func readAPIKey(for provider: LLMProviderConfig) throws -> String? {
        readProviderIDs.append(provider.id)
        return apiKeysByProviderID[provider.id]
    }

    func deleteAPIKey(for provider: LLMProviderConfig) throws {}
}

private final class MockLLMProvider: LLMProvider {
    struct CapturedCall {
        var bundle: AgentMessageBundle
        var provider: LLMProviderConfig
        var apiKey: String?
    }

    private let responsesByAgentID: [UUID: Result<String, Error>]
    private(set) var capturedCalls: [CapturedCall] = []

    init(responsesByAgentID: [UUID: Result<String, Error>]) {
        self.responsesByAgentID = responsesByAgentID
    }

    func complete(
        bundle: AgentMessageBundle,
        provider: LLMProviderConfig,
        apiKey: String?
    ) async throws -> String {
        capturedCalls.append(CapturedCall(bundle: bundle, provider: provider, apiKey: apiKey))
        guard let response = responsesByAgentID[bundle.agentID] else {
            throw MockProviderError.missingResponse
        }

        return try response.get()
    }
}

private final class FakeLLMResponseCache: LLMResponseCaching {
    struct Lookup {
        var cacheKey: String
        var now: Date
    }

    struct StoredResponse {
        var rawResponse: String
        var cacheKey: String
        var now: Date
    }

    private let cachedRawResponseValue: String?
    private(set) var cachedLookups: [Lookup] = []
    private(set) var storedResponses: [StoredResponse] = []
    private(set) var removeExpiredDates: [Date] = []

    init(cachedRawResponse: String? = nil) {
        self.cachedRawResponseValue = cachedRawResponse
    }

    func cachedRawResponse(
        forCacheKey cacheKey: String,
        now: Date
    ) throws -> String? {
        cachedLookups.append(Lookup(cacheKey: cacheKey, now: now))
        return cachedRawResponseValue
    }

    func storeRawResponse(
        _ rawResponse: String,
        forCacheKey cacheKey: String,
        now: Date
    ) throws {
        storedResponses.append(
            StoredResponse(
                rawResponse: rawResponse,
                cacheKey: cacheKey,
                now: now
            )
        )
    }

    func removeExpiredResponses(now: Date) throws {
        removeExpiredDates.append(now)
    }
}

private enum MockProviderError: Error, CustomStringConvertible {
    case missingResponse
    case transport

    var description: String {
        switch self {
        case .missingResponse:
            return "missing response"
        case .transport:
            return "transport"
        }
    }
}
