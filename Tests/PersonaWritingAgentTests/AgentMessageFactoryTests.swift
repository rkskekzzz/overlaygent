import Foundation
import XCTest
@testable import PersonaWritingAgent

final class AgentMessageFactoryTests: XCTestCase {
    func testMakeBundlesCreatesProviderNeutralBundleForEachActiveAgent() {
        let providerID = UUID(uuidString: "00000000-0000-0000-0000-000000000901")!
        let firstAgent = agent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000902")!,
            name: "Coding Terms",
            providerID: providerID,
            modelOverride: " gpt-4.1-mini "
        )
        let secondAgent = agent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000903")!,
            name: "Friendly Rewrite",
            providerID: providerID,
            modelOverride: " "
        )
        let request = runRequest(
            activeAgents: [firstAgent, secondAgent],
            includeConversationContext: true
        )
        let factory = AgentMessageFactory(outputSchemaID: "CorrectionResult.v1")

        let bundles = factory.makeBundles(for: request)

        XCTAssertEqual(bundles.count, 2)
        XCTAssertEqual(bundles.map(\.agentID), [firstAgent.id, secondAgent.id])
        XCTAssertEqual(bundles.map(\.agentName), ["Coding Terms", "Friendly Rewrite"])
        XCTAssertEqual(bundles.map(\.providerID), [providerID, providerID])
        XCTAssertEqual(bundles.map(\.resolvedModel), ["gpt-4.1-mini", nil])
        XCTAssertEqual(bundles.map(\.outputSchemaID), ["CorrectionResult.v1", "CorrectionResult.v1"])
        XCTAssertEqual(bundles[0].messages.map(\.role), [.system, .developer, .user])
    }

    func testMakeBundleAssemblesStableSystemDeveloperAndUserSections() {
        let agentID = UUID(uuidString: "00000000-0000-0000-0000-000000000904")!
        let providerID = UUID(uuidString: "00000000-0000-0000-0000-000000000905")!
        let targetAgent = agent(id: agentID, name: "Coding Terms", providerID: providerID)
        let request = runRequest(activeAgents: [targetAgent], includeConversationContext: true)
        let factory = AgentMessageFactory()

        let bundle = factory.makeBundle(for: targetAgent, request: request)

        XCTAssertEqual(
            bundle.messages[0].content,
            """
            # Agent
            ID: 00000000-0000-0000-0000-000000000904
            Name: Coding Terms
            Provider ID: 00000000-0000-0000-0000-000000000905

            # System Prompt
            Preserve technical names.
            """
        )
        XCTAssertEqual(
            bundle.messages[1].content,
            """
            # Instruction
            Improve developer English without changing intent.

            # Controls
            Tone: technical
            Aggressiveness: conservative
            Scope: selectedText

            # Agent Terminology Rules
            1. make deploy -> deploy it (case-insensitive; note: Use natural deployment phrasing.)

            # Agent Memory
            Terminology:
              1. PR -> pull request (case-sensitive)
            Tone preferences:
              1. concise
              2. friendly
            Writing rules:
              1. Keep file paths unchanged.

            # Output Contract
            Return exactly one JSON object and no Markdown or prose.
            Schema ID: CorrectionResult
            Required top-level keys: "summary", "edits", "fullRewrite".
            Use "summary" as a short string or null.
            Use "edits" as an array of objects with rangeStart, rangeEnd, original, replacement, and reason.
            Ranges are zero-based character offsets into the Input section.
            Use "fullRewrite" as a complete corrected version string or null.
            If the text is already good, set fullRewrite to the original input and explain that no change is needed in summary.
            """
        )
        XCTAssertEqual(
            bundle.messages[2].content,
            """
            # Source
            Bundle ID: com.tinyspeck.slackmacgap
            Element role: AXTextArea
            Selected range: 7..<18

            # Conversation Context
            App bundle ID: com.tinyspeck.slackmacgap
            Title: #release
            Visible messages:
            1. No timestamp | Sam: Can we ship this after review?
            2. No timestamp | Me: I will make deploy when PR approved.

            # Input
            I will make deploy when PR approved.
            """
        )
        XCTAssertEqual(bundle.outputSchemaID, AgentMessageFactory.defaultOutputSchemaID)
        XCTAssertEqual(bundle.budgetMetadata.retainedInputCharacterCount, request.input.text.count)
        XCTAssertFalse(bundle.budgetMetadata.didTrimForCharacterBudget)
        XCTAssertFalse(bundle.messages[2].content.contains("sha256:message-factory"))
    }

    func testMakeBundleDoesNotIncludeConversationMessagesWhenPrivacyOptsOut() {
        let targetAgent = agent()
        let request = runRequest(activeAgents: [targetAgent], includeConversationContext: false)
        let factory = AgentMessageFactory()

        let bundle = factory.makeBundle(for: targetAgent, request: request)

        XCTAssertTrue(bundle.messages[2].content.contains("# Conversation Context\nNot included."))
        XCTAssertFalse(bundle.messages[2].content.contains("Can we ship this after review?"))
        XCTAssertEqual(bundle.budgetMetadata.originalVisibleMessageCount, 0)
        XCTAssertEqual(bundle.budgetMetadata.retainedVisibleMessageCount, 0)
    }

    private func runRequest(
        activeAgents: [AgentProfile],
        includeConversationContext: Bool
    ) -> AgentRunRequest {
        AgentRunRequest(
            input: TextSnapshot(
                text: "I will make deploy when PR approved.",
                selectedRange: 7..<18,
                sourceBundleID: "com.tinyspeck.slackmacgap",
                sourceElementRole: "AXTextArea",
                contentHash: "sha256:message-factory"
            ),
            activeAgents: activeAgents,
            appContext: ConversationContext(
                appBundleID: "com.tinyspeck.slackmacgap",
                conversationTitle: "#release",
                visibleMessages: [
                    ConversationMessage(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000906")!,
                        author: "Sam",
                        timestamp: nil,
                        text: "Can we ship this after review?"
                    ),
                    ConversationMessage(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000907")!,
                        author: "Me",
                        timestamp: nil,
                        text: "I will make deploy when PR approved."
                    )
                ]
            ),
            memory: AgentMemory(
                terminologyRules: [
                    TerminologyRule(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000908")!,
                        match: "PR",
                        replacement: "pull request",
                        note: nil,
                        isCaseSensitive: true
                    )
                ],
                tonePreferences: ["concise", "friendly"],
                writingRules: ["Keep file paths unchanged."]
            ),
            privacyPolicy: PrivacyPolicy(
                includeConversationContext: includeConversationContext,
                maxVisibleMessages: 5,
                allowClipboardFallback: false,
                redactionRules: []
            )
        )
    }

    private func agent(
        id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000900")!,
        name: String = "Coding Terms",
        providerID: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000901")!,
        modelOverride: String? = nil
    ) -> AgentProfile {
        AgentProfile(
            id: id,
            name: name,
            description: "\(name) description",
            isEnabled: true,
            isActive: true,
            providerID: providerID,
            modelOverride: modelOverride,
            systemPrompt: "Preserve technical names.",
            instruction: "Improve developer English without changing intent.",
            tone: .technical,
            aggressiveness: .conservative,
            scope: .selectedText,
            terminologyRules: [
                TerminologyRule(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000909")!,
                    match: "make deploy",
                    replacement: "deploy it",
                    note: "Use natural deployment phrasing.",
                    isCaseSensitive: false
                )
            ],
            enabledBundleIDs: [],
            disabledBundleIDs: [],
            applyMode: .askEveryTime
        )
    }
}
