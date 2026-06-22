import Foundation
import XCTest
@testable import PersonaWritingAgent

final class OpenAICompatibleProviderTests: XCTestCase {
    func testCompleteBuildsOpenAICompatibleRequestAndReturnsAssistantContent() async throws {
        let apiKey = "sk-test-secret"
        let httpClient = MockLLMProviderHTTPClient(
            result: .success((
                responseData(content: "Corrected text."),
                httpResponse(statusCode: 200)
            ))
        )
        let provider = OpenAICompatibleProvider(httpClient: httpClient)
        let config = providerConfig(
            baseURL: URL(string: "https://api.example.com/v1")!,
            defaultModel: "default-model",
            temperature: 0.35,
            maxTokens: 700,
            timeoutSeconds: 12
        )
        let bundle = messageBundle(
            resolvedModel: "agent-model",
            messages: [
                AgentMessage(role: .system, content: "System prompt"),
                AgentMessage(role: .developer, content: "Developer instructions"),
                AgentMessage(role: .user, content: "Original text")
            ]
        )

        let content = try await provider.complete(
            bundle: bundle,
            provider: config,
            apiKey: apiKey
        )

        XCTAssertEqual(content, "Corrected text.")
        XCTAssertEqual(httpClient.capturedRequests.count, 1)

        let request = try XCTUnwrap(httpClient.capturedRequests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 12)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(apiKey)")

        let body = try XCTUnwrap(request.httpBody)
        let capturedPayload = try JSONDecoder().decode(CapturedChatCompletionRequest.self, from: body)
        XCTAssertEqual(capturedPayload.model, "agent-model")
        XCTAssertEqual(capturedPayload.temperature, 0.35)
        XCTAssertEqual(capturedPayload.maxCompletionTokens, 700)
        XCTAssertEqual(capturedPayload.responseFormat.type, "json_schema")
        XCTAssertEqual(capturedPayload.responseFormat.jsonSchema.name, "correction_result")
        XCTAssertTrue(capturedPayload.responseFormat.jsonSchema.strict)
        XCTAssertEqual(
            capturedPayload.responseFormat.jsonSchema.schema.required,
            ["summary", "edits", "fullRewrite"]
        )
        XCTAssertFalse(capturedPayload.responseFormat.jsonSchema.schema.additionalProperties)
        XCTAssertEqual(
            capturedPayload.messages,
            [
                CapturedChatCompletionRequest.Message(role: "system", content: "System prompt"),
                CapturedChatCompletionRequest.Message(role: "developer", content: "Developer instructions"),
                CapturedChatCompletionRequest.Message(role: "user", content: "Original text")
            ]
        )

        XCTAssertFalse(request.url?.absoluteString.contains(apiKey) ?? false)
        XCTAssertFalse(String(data: body, encoding: .utf8)?.contains(apiKey) ?? true)
        for (name, value) in request.allHTTPHeaderFields ?? [:] where name != "Authorization" {
            XCTAssertFalse(value.contains(apiKey))
        }
    }

    func testCompleteUsesDefaultModelAndNormalizesTrailingSlashEndpoint() async throws {
        let httpClient = MockLLMProviderHTTPClient(
            result: .success((
                responseData(content: "Default model response"),
                httpResponse(statusCode: 200)
            ))
        )
        let provider = OpenAICompatibleProvider(httpClient: httpClient)
        let config = providerConfig(
            baseURL: URL(string: "https://api.example.com/v1/")!,
            defaultModel: "fallback-model"
        )

        _ = try await provider.complete(
            bundle: messageBundle(resolvedModel: nil),
            provider: config,
            apiKey: "sk-test-secret"
        )

        let request = try XCTUnwrap(httpClient.capturedRequests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/v1/chat/completions")

        let body = try XCTUnwrap(request.httpBody)
        let capturedPayload = try JSONDecoder().decode(CapturedChatCompletionRequest.self, from: body)
        XCTAssertEqual(capturedPayload.model, "fallback-model")
    }

    func testCompleteNormalizesNestedBaseEndpoint() async throws {
        let httpClient = MockLLMProviderHTTPClient(
            result: .success((
                responseData(content: "Nested response"),
                httpResponse(statusCode: 200)
            ))
        )
        let provider = OpenAICompatibleProvider(httpClient: httpClient)
        let config = providerConfig(
            baseURL: URL(string: "https://gateway.example.com/openai/v1/")!
        )

        _ = try await provider.complete(
            bundle: messageBundle(),
            provider: config,
            apiKey: "sk-test-secret"
        )

        XCTAssertEqual(
            httpClient.capturedRequests.first?.url?.absoluteString,
            "https://gateway.example.com/openai/v1/chat/completions"
        )
    }

    func testCompleteRejectsMissingAPIKeyBeforeHTTP() async {
        let httpClient = MockLLMProviderHTTPClient(
            result: .success((
                responseData(content: "Should not be used"),
                httpResponse(statusCode: 200)
            ))
        )
        let provider = OpenAICompatibleProvider(httpClient: httpClient)

        await assertThrowsLLMProviderError(.missingAPIKey) {
            _ = try await provider.complete(
                bundle: messageBundle(),
                provider: providerConfig(),
                apiKey: "  "
            )
        }
        XCTAssertEqual(httpClient.capturedRequests.count, 0)
    }

    func testCompleteRejectsHTTPStatusWithoutLeakingAPIKey() async {
        let apiKey = "sk-test-secret"
        let httpClient = MockLLMProviderHTTPClient(
            result: .success((
                Data("{\"error\":\"\(apiKey)\"}".utf8),
                httpResponse(statusCode: 401)
            ))
        )
        let provider = OpenAICompatibleProvider(httpClient: httpClient)

        do {
            _ = try await provider.complete(
                bundle: messageBundle(),
                provider: providerConfig(),
                apiKey: apiKey
            )
            XCTFail("Expected provider to reject non-success HTTP status.")
        } catch let error as LLMProviderError {
            XCTAssertEqual(error, .httpStatus(401, message: nil))
            XCTAssertFalse(String(describing: error).contains(apiKey))
            XCTAssertFalse((error as NSError).localizedDescription.contains(apiKey))
        } catch {
            XCTFail("Expected LLMProviderError, got \(error).")
        }
    }

    func testCompleteIncludesRedactedProviderErrorMessageForHTTPStatus() async {
        let apiKey = "sk-test-secret"
        let httpClient = MockLLMProviderHTTPClient(
            result: .success((
                Data(#"{"error":{"message":"Unsupported parameter: max_tokens for sk-test-secret"}}"#.utf8),
                httpResponse(statusCode: 400)
            ))
        )
        let provider = OpenAICompatibleProvider(httpClient: httpClient)

        do {
            _ = try await provider.complete(
                bundle: messageBundle(),
                provider: providerConfig(),
                apiKey: apiKey
            )
            XCTFail("Expected provider to reject non-success HTTP status.")
        } catch let error as LLMProviderError {
            XCTAssertEqual(
                error,
                .httpStatus(400, message: "Unsupported parameter: max_tokens for [REDACTED_CUSTOM]")
            )
            XCTAssertFalse(String(describing: error).contains(apiKey))
            XCTAssertFalse((error as NSError).localizedDescription.contains(apiKey))
        } catch {
            XCTFail("Expected LLMProviderError, got \(error).")
        }
    }

    func testCompleteRejectsInvalidJSON() async {
        let httpClient = MockLLMProviderHTTPClient(
            result: .success((
                Data("not-json".utf8),
                httpResponse(statusCode: 200)
            ))
        )
        let provider = OpenAICompatibleProvider(httpClient: httpClient)

        await assertThrowsLLMProviderError(.invalidResponseJSON) {
            _ = try await provider.complete(
                bundle: messageBundle(),
                provider: providerConfig(),
                apiKey: "sk-test-secret"
            )
        }
    }

    func testCompleteRejectsEmptyChoices() async {
        let httpClient = MockLLMProviderHTTPClient(
            result: .success((
                Data(#"{"choices":[]}"#.utf8),
                httpResponse(statusCode: 200)
            ))
        )
        let provider = OpenAICompatibleProvider(httpClient: httpClient)

        await assertThrowsLLMProviderError(.emptyChoices) {
            _ = try await provider.complete(
                bundle: messageBundle(),
                provider: providerConfig(),
                apiKey: "sk-test-secret"
            )
        }
    }

    func testCompleteRejectsEmptyContent() async {
        let httpClient = MockLLMProviderHTTPClient(
            result: .success((
                Data(#"{"choices":[{"message":{"content":""}}]}"#.utf8),
                httpResponse(statusCode: 200)
            ))
        )
        let provider = OpenAICompatibleProvider(httpClient: httpClient)

        await assertThrowsLLMProviderError(.emptyContent) {
            _ = try await provider.complete(
                bundle: messageBundle(),
                provider: providerConfig(),
                apiKey: "sk-test-secret"
            )
        }
    }

    func testCompleteRejectsMissingContent() async {
        let httpClient = MockLLMProviderHTTPClient(
            result: .success((
                Data(#"{"choices":[{"message":{}}]}"#.utf8),
                httpResponse(statusCode: 200)
            ))
        )
        let provider = OpenAICompatibleProvider(httpClient: httpClient)

        await assertThrowsLLMProviderError(.emptyContent) {
            _ = try await provider.complete(
                bundle: messageBundle(),
                provider: providerConfig(),
                apiKey: "sk-test-secret"
            )
        }
    }

    private func assertThrowsLLMProviderError(
        _ expectedError: LLMProviderError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expectedError), but operation succeeded.", file: file, line: line)
        } catch let error as LLMProviderError {
            XCTAssertEqual(error, expectedError, file: file, line: line)
        } catch {
            XCTFail("Expected \(expectedError), got \(error).", file: file, line: line)
        }
    }

    private func messageBundle(
        resolvedModel: String? = "gpt-4.1-mini",
        messages: [AgentMessage] = [
            AgentMessage(role: .system, content: "System prompt"),
            AgentMessage(role: .user, content: "Original text")
        ]
    ) -> AgentMessageBundle {
        AgentMessageBundle(
            agentID: UUID(uuidString: "00000000-0000-0000-0000-000000000501")!,
            agentName: "Test Agent",
            providerID: UUID(uuidString: "00000000-0000-0000-0000-000000000502")!,
            resolvedModel: resolvedModel,
            messages: messages,
            outputSchemaID: "CorrectionResult.v1",
            budgetMetadata: budgetMetadata()
        )
    }

    private func budgetMetadata() -> AgentMessageBudgetMetadata {
        AgentMessageBudgetMetadata(
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
    }

    private func providerConfig(
        baseURL: URL = URL(string: "https://api.example.com/v1")!,
        defaultModel: String = "gpt-4.1-mini",
        temperature: Double = 0.2,
        maxTokens: Int = 1_200,
        timeoutSeconds: Double = 30
    ) -> LLMProviderConfig {
        LLMProviderConfig(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000503")!,
            name: "OpenAI Compatible",
            baseURL: baseURL,
            defaultModel: defaultModel,
            temperature: temperature,
            maxTokens: maxTokens,
            timeoutSeconds: timeoutSeconds,
            keychainServiceName: "PersonaWritingAgent.LLMProvider.test"
        )
    }

    private func responseData(content: String) -> Data {
        Data(#"{"choices":[{"message":{"content":"\#(content)"}}]}"#.utf8)
    }

    private func httpResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.example.com/v1/chat/completions")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }
}

private final class MockLLMProviderHTTPClient: LLMProviderHTTPClient {
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

private struct CapturedChatCompletionRequest: Decodable {
    struct Message: Decodable, Equatable {
        var role: String
        var content: String
    }

    var model: String
    var messages: [Message]
    var temperature: Double
    var maxCompletionTokens: Int
    var responseFormat: ResponseFormat

    struct ResponseFormat: Decodable {
        var type: String
        var jsonSchema: JSONSchemaEnvelope

        private enum CodingKeys: String, CodingKey {
            case type
            case jsonSchema = "json_schema"
        }
    }

    struct JSONSchemaEnvelope: Decodable {
        var name: String
        var strict: Bool
        var schema: RootSchema
    }

    struct RootSchema: Decodable {
        var required: [String]
        var additionalProperties: Bool
    }

    private enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxCompletionTokens = "max_completion_tokens"
        case responseFormat = "response_format"
    }
}
