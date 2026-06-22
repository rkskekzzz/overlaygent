import Foundation
import XCTest
@testable import PersonaWritingAgent

final class ContextBudgeterTests: XCTestCase {
    func testBudgetPreservesInputEvenWhenCharacterBudgetIsSmallerThanInput() {
        let targetAgent = agent()
        let request = runRequest(
            activeAgents: [targetAgent],
            memory: AgentMemory(
                terminologyRules: [],
                tonePreferences: ["concise"],
                writingRules: ["Keep identifiers unchanged."]
            ),
            visibleMessages: [],
            includeConversationContext: false,
            maxVisibleMessages: 0,
            inputText: "This input is longer than the budget."
        )
        let budgeter = ContextBudgeter(characterBudget: 5)

        let result = budgeter.budget(agent: targetAgent, request: request)

        XCTAssertEqual(result.input.text, "This input is longer than the budget.")
        XCTAssertEqual(result.metadata.inputCharacterCount, request.input.text.count)
        XCTAssertEqual(result.metadata.retainedInputCharacterCount, request.input.text.count)
        XCTAssertTrue(result.metadata.didTrimForCharacterBudget)
        XCTAssertNil(result.conversationContext)
        XCTAssertEqual(result.memory.tonePreferences, [])
        XCTAssertEqual(result.memory.writingRules, [])
    }

    func testBudgetLimitsVisibleMessagesAndKeepsNewestMessagesWithinCharacterBudget() {
        let targetAgent = agent(terminologyRules: [])
        let messages = [
            conversationMessage(index: 0, text: "message-0"),
            conversationMessage(index: 1, text: "message-1"),
            conversationMessage(index: 2, text: "message-2"),
            conversationMessage(index: 3, text: "message-3")
        ]
        let request = runRequest(
            activeAgents: [targetAgent],
            memory: AgentMemory(terminologyRules: [], tonePreferences: [], writingRules: []),
            visibleMessages: messages,
            includeConversationContext: true,
            maxVisibleMessages: 3,
            inputText: "Input"
        )
        let budgeter = ContextBudgeter(characterBudget: 36)

        let result = budgeter.budget(agent: targetAgent, request: request)

        XCTAssertEqual(result.conversationContext?.visibleMessages.map(\.text), ["message-3"])
        XCTAssertEqual(result.metadata.originalVisibleMessageCount, 4)
        XCTAssertEqual(result.metadata.retainedVisibleMessageCount, 1)
        XCTAssertTrue(result.metadata.didTrimVisibleMessages)
        XCTAssertTrue(result.metadata.didTrimForCharacterBudget)
    }

    func testBudgetIncludesConversationContextOnlyWhenOptedIn() {
        let targetAgent = agent(terminologyRules: [])
        let messages = [conversationMessage(index: 0, text: "visible")]
        let request = runRequest(
            activeAgents: [targetAgent],
            memory: AgentMemory(terminologyRules: [], tonePreferences: [], writingRules: []),
            visibleMessages: messages,
            includeConversationContext: false,
            maxVisibleMessages: 5,
            inputText: "Input"
        )
        let budgeter = ContextBudgeter()

        let result = budgeter.budget(agent: targetAgent, request: request)

        XCTAssertNil(result.conversationContext)
        XCTAssertEqual(result.metadata.originalVisibleMessageCount, 0)
        XCTAssertEqual(result.metadata.retainedVisibleMessageCount, 0)
        XCTAssertFalse(result.metadata.didTrimVisibleMessages)
    }

    private func runRequest(
        activeAgents: [AgentProfile],
        memory: AgentMemory,
        visibleMessages: [ConversationMessage],
        includeConversationContext: Bool,
        maxVisibleMessages: Int,
        inputText: String
    ) -> AgentRunRequest {
        AgentRunRequest(
            input: TextSnapshot(
                text: inputText,
                selectedRange: nil,
                sourceBundleID: "com.example.App",
                sourceElementRole: "AXTextArea",
                contentHash: "sha256:budget"
            ),
            activeAgents: activeAgents,
            appContext: ConversationContext(
                appBundleID: "com.example.App",
                conversationTitle: "General",
                visibleMessages: visibleMessages
            ),
            memory: memory,
            privacyPolicy: PrivacyPolicy(
                includeConversationContext: includeConversationContext,
                maxVisibleMessages: maxVisibleMessages,
                allowClipboardFallback: false,
                redactionRules: []
            )
        )
    }

    private func conversationMessage(index: Int, text: String) -> ConversationMessage {
        ConversationMessage(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 950 + index))!,
            author: "Me",
            timestamp: nil,
            text: text
        )
    }

    private func agent(
        terminologyRules: [TerminologyRule] = [
            TerminologyRule(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000951")!,
                match: "make deploy",
                replacement: "deploy it",
                note: nil,
                isCaseSensitive: false
            )
        ]
    ) -> AgentProfile {
        AgentProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000952")!,
            name: "Budget Test Agent",
            description: "Tests budget behavior.",
            isEnabled: true,
            isActive: true,
            providerID: UUID(uuidString: "00000000-0000-0000-0000-000000000953")!,
            modelOverride: nil,
            systemPrompt: "System prompt.",
            instruction: "Instruction.",
            tone: .neutral,
            aggressiveness: .balanced,
            scope: .currentInput,
            terminologyRules: terminologyRules,
            enabledBundleIDs: [],
            disabledBundleIDs: [],
            applyMode: .askEveryTime
        )
    }
}
