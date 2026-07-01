import Foundation
import XCTest
@testable import Overlaygent

final class ChatGPTSubscriptionProviderTests: XCTestCase {
    func testCompleteBuildsCodexResponsesRequestAndReturnsOutputText() async throws {
        let accessToken = "chatgpt-access-token"
        let accountID = "chatgpt-account-id"
        let httpClient = ChatGPTMockHTTPClient(
            result: .success((
                Data(#"{"output_text":"{\"summary\":null,\"edits\":[],\"fullRewrite\":\"Corrected.\"}"}"#.utf8),
                httpResponse(statusCode: 200)
            ))
        )
        let provider = ChatGPTSubscriptionProvider(httpClient: httpClient)
        let config = LLMProviderConfig.defaultChatGPTSubscription(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000801")!,
            baseURL: URL(string: "https://chatgpt.com/backend-api/codex/")!,
            defaultModel: "gpt-5.2",
            reasoningEffort: .medium,
            temperature: 0.4,
            maxTokens: 900,
            timeoutSeconds: 15
        )
        let bundle = AgentMessageBundle(
            agentID: UUID(uuidString: "00000000-0000-0000-0000-000000000802")!,
            agentName: "Test Agent",
            providerID: config.id,
            resolvedModel: "gpt-5.3-codex",
            messages: [
                AgentMessage(role: .system, content: "System prompt"),
                AgentMessage(role: .user, content: "Original text")
            ],
            outputSchemaID: "CorrectionResult.v1",
            budgetMetadata: AgentMessageBudgetMetadata(
                characterBudget: nil,
                maxVisibleMessages: 0,
                includeConversationContext: false,
                inputCharacterCount: 0,
                retainedInputCharacterCount: 0,
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

        let content = try await provider.complete(
            bundle: bundle,
            provider: config,
            credential: .chatGPTSubscription(accessToken: accessToken, accountID: accountID)
        )

        XCTAssertEqual(content, #"{"summary":null,"edits":[],"fullRewrite":"Corrected."}"#)
        let request = try XCTUnwrap(httpClient.capturedRequests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://chatgpt.com/backend-api/codex/responses")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 15)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(accessToken)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "chatgpt-account-id"), accountID)
        XCTAssertEqual(request.value(forHTTPHeaderField: "OpenAI-Beta"), "responses=experimental")

        let body = try XCTUnwrap(request.httpBody)
        let payload = try JSONDecoder().decode(CapturedCodexResponsesRequest.self, from: body)
        XCTAssertEqual(payload.model, "gpt-5.3-codex")
        XCTAssertEqual(payload.temperature, 0.4)
        XCTAssertEqual(payload.maxOutputTokens, 900)
        XCTAssertEqual(payload.reasoning?.effort, "medium")
        XCTAssertEqual(payload.text.format.type, "json_schema")
        XCTAssertEqual(payload.store, false)
        XCTAssertEqual(payload.stream, false)
        XCTAssertEqual(payload.input.map(\.role), ["system", "user"])
        XCTAssertFalse(String(data: body, encoding: .utf8)?.contains(accessToken) ?? true)
        XCTAssertFalse(String(data: body, encoding: .utf8)?.contains(accountID) ?? true)
    }

    func testListModelsBuildsCodexModelsRequestAndReturnsSortedUniqueSlugs() async throws {
        let accessToken = "chatgpt-access-token"
        let accountID = "chatgpt-account-id"
        let httpClient = ChatGPTMockHTTPClient(
            result: .success((
                Data(#"{"models":[{"slug":"gpt-5.3-codex"},{"slug":"gpt-5.2"},{"slug":"gpt-5.2"},{"slug":"  "} ]}"#.utf8),
                httpResponse(statusCode: 200, url: URL(string: "https://chatgpt.com/backend-api/codex/models")!)
            ))
        )
        let modelLister = ChatGPTSubscriptionModelLister(httpClient: httpClient, clientVersion: "overlaygent-test")
        let config = LLMProviderConfig.defaultChatGPTSubscription(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000803")!,
            baseURL: URL(string: "https://chatgpt.com/backend-api/codex/")!,
            timeoutSeconds: 9
        )

        let models = try await modelLister.listModels(
            provider: config,
            credential: .chatGPTSubscription(accessToken: accessToken, accountID: accountID)
        )

        XCTAssertEqual(models, ["gpt-5.2", "gpt-5.3-codex"])
        let request = try XCTUnwrap(httpClient.capturedRequests.first)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://chatgpt.com/backend-api/codex/models?client_version=overlaygent-test"
        )
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.timeoutInterval, 9)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(accessToken)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "chatgpt-account-id"), accountID)
        XCTAssertEqual(request.value(forHTTPHeaderField: "OpenAI-Beta"), "responses=experimental")
        XCTAssertNil(request.httpBody)
    }

    func testListModelsAcceptsOpenAICompatibleModelListShape() async throws {
        let httpClient = ChatGPTMockHTTPClient(
            result: .success((
                Data(#"{"data":[{"id":"gpt-5.2"},{"id":"gpt-4.1-mini"}]}"#.utf8),
                httpResponse(statusCode: 200, url: URL(string: "https://chatgpt.com/backend-api/codex/models")!)
            ))
        )
        let modelLister = ChatGPTSubscriptionModelLister(httpClient: httpClient)
        let config = LLMProviderConfig.defaultChatGPTSubscription(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000804")!
        )

        let models = try await modelLister.listModels(
            provider: config,
            credential: .chatGPTSubscription(accessToken: "access-token", accountID: "account-id")
        )

        XCTAssertEqual(models, ["gpt-4.1-mini", "gpt-5.2"])
    }
}

private final class ChatGPTMockHTTPClient: LLMProviderHTTPClient {
    private let result: Result<(Data, HTTPURLResponse), Error>
    private(set) var capturedRequests: [URLRequest] = []

    init(result: Result<(Data, HTTPURLResponse), Error>) {
        self.result = result
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        capturedRequests.append(request)
        return try result.get()
    }
}

private struct CapturedCodexResponsesRequest: Decodable {
    struct Input: Decodable {
        var role: String
    }

    struct Reasoning: Decodable {
        var effort: String
    }

    struct Text: Decodable {
        var format: Format
    }

    struct Format: Decodable {
        var type: String
    }

    var model: String
    var input: [Input]
    var temperature: Double
    var reasoning: Reasoning?
    var maxOutputTokens: Int
    var text: Text
    var store: Bool
    var stream: Bool

    private enum CodingKeys: String, CodingKey {
        case model
        case input
        case temperature
        case reasoning
        case maxOutputTokens = "max_output_tokens"
        case text
        case store
        case stream
    }
}

private func httpResponse(
    statusCode: Int,
    url: URL = URL(string: "https://chatgpt.com/backend-api/codex/responses")!
) -> HTTPURLResponse {
    HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
    )!
}
