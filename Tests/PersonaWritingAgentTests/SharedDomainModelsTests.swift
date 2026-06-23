import Foundation
import XCTest
@testable import PersonaWritingAgent

final class SharedDomainModelsTests: XCTestCase {
    func testLLMProviderConfigCodableRoundTrip() throws {
        let provider = LLMProviderConfig(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "OpenAI Compatible",
            baseURL: URL(string: "https://api.example.com/v1")!,
            defaultModel: "gpt-4.1-mini",
            reasoningEffort: .low,
            temperature: 0.2,
            maxTokens: 1_200,
            timeoutSeconds: 30,
            keychainServiceName: "PersonaWritingAgent.OpenAI"
        )

        XCTAssertEqual(try roundTrip(provider), provider)
    }

    func testLLMProviderConfigDecodesLegacyProviderWithoutReasoningEffort() throws {
        let data = Data(
            """
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "name": "OpenAI Compatible",
              "baseURL": "https://api.example.com/v1",
              "defaultModel": "gpt-4.1-mini",
              "temperature": 0.2,
              "maxTokens": 1200,
              "timeoutSeconds": 30,
              "keychainServiceName": "PersonaWritingAgent.OpenAI"
            }
            """.utf8
        )

        let provider = try JSONDecoder().decode(LLMProviderConfig.self, from: data)

        XCTAssertNil(provider.reasoningEffort)
    }

    func testAgentRunRequestCodableRoundTrip() throws {
        let providerID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let terminologyRule = TerminologyRule(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            match: "make deploy",
            replacement: "deploy it",
            note: "Prefer natural engineering phrasing.",
            isCaseSensitive: false
        )
        let agent = AgentProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            name: "Coding Terms",
            description: "Keeps developer terminology natural.",
            isEnabled: true,
            isActive: true,
            providerID: providerID,
            modelOverride: "gpt-4.1",
            systemPrompt: "Preserve code identifiers and technical names.",
            instruction: "Improve developer English without changing intent.",
            tone: .technical,
            aggressiveness: .conservative,
            scope: .selectedText,
            terminologyRules: [terminologyRule],
            enabledBundleIDs: ["com.tinyspeck.slackmacgap"],
            disabledBundleIDs: ["com.apple.Safari"],
            applyMode: .askEveryTime
        )
        let snapshot = TextSnapshot(
            text: "I will make deploy when PR approved.",
            selectedRange: 7..<18,
            sourceBundleID: "com.tinyspeck.slackmacgap",
            sourceElementRole: "AXTextArea",
            contentHash: "sha256:example"
        )
        let context = ConversationContext(
            appBundleID: "com.tinyspeck.slackmacgap",
            conversationTitle: "#release",
            visibleMessages: [
                ConversationMessage(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
                    author: "Sam",
                    timestamp: Date(timeIntervalSince1970: 1_771_000_000),
                    text: "Can we ship this after review?"
                )
            ]
        )
        let memory = AgentMemory(
            terminologyRules: [terminologyRule],
            tonePreferences: ["concise", "friendly"],
            writingRules: ["Keep file paths unchanged."]
        )
        let privacyPolicy = PrivacyPolicy(
            includeConversationContext: true,
            maxVisibleMessages: 5,
            allowClipboardFallback: false,
            redactionRules: ["apiKey", "password"]
        )
        let request = AgentRunRequest(
            input: snapshot,
            activeAgents: [agent],
            appContext: context,
            memory: memory,
            privacyPolicy: privacyPolicy
        )

        XCTAssertEqual(try roundTrip(request), request)
    }

    private func roundTrip<Value: Codable & Equatable>(_ value: Value) throws -> Value {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(Value.self, from: data)
    }
}
