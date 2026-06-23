import Foundation
import XCTest
@testable import Overlaygent

final class PrivacyGuardTests: XCTestCase {
    func testRejectsSecurePasswordAndPrivateSourceElementRolesBeforeRedaction() {
        for sourceElementRole in ["AXSecureTextField", "AXPasswordField", "AXPrivateTextField"] {
            let request = agentRunRequest(
                input: Self.textSnapshot(
                    text: "password=hunter2",
                    sourceElementRole: sourceElementRole
                ),
                privacyPolicy: Self.privacyPolicy(redactionRules: ["password"])
            )

            XCTAssertThrowsError(try PrivacyGuard().validateAndRedact(request)) { error in
                XCTAssertEqual(
                    error as? PrivacyGuardError,
                    .secureSourceMetadata(field: "input.sourceElementRole", value: sourceElementRole)
                )
            }
        }
    }

    func testRejectsSecureLikeSourceBundleMetadataBeforeRedaction() {
        let request = agentRunRequest(
            input: Self.textSnapshot(sourceBundleID: "com.example.SecretVault")
        )

        XCTAssertThrowsError(try PrivacyGuard().validateAndRedact(request)) { error in
            XCTAssertEqual(
                error as? PrivacyGuardError,
                .secureSourceMetadata(field: "input.sourceBundleID", value: "com.example.SecretVault")
            )
        }
    }

    func testFiltersAgentsByDisabledAndEnabledBundlePolicies() throws {
        let sourceBundleID = "com.tinyspeck.slackmacgap"
        let disabledForSlack = Self.agent(
            idSuffix: 1,
            name: "Disabled for Slack",
            disabledBundleIDs: [sourceBundleID]
        )
        let enabledForSlack = Self.agent(
            idSuffix: 2,
            name: "Enabled for Slack",
            enabledBundleIDs: [sourceBundleID]
        )
        let enabledForDiscord = Self.agent(
            idSuffix: 3,
            name: "Enabled for Discord",
            enabledBundleIDs: ["com.hnc.Discord"]
        )
        let unrestricted = Self.agent(idSuffix: 4, name: "Unrestricted")
        let request = agentRunRequest(
            input: Self.textSnapshot(sourceBundleID: sourceBundleID),
            activeAgents: [
                disabledForSlack,
                enabledForSlack,
                enabledForDiscord,
                unrestricted
            ]
        )

        let sanitizedRequest = try PrivacyGuard().validateAndRedact(request)

        XCTAssertEqual(sanitizedRequest.activeAgents.map { $0.id }, [enabledForSlack.id, unrestricted.id])
    }

    func testBundlePoliciesMatchCaseAndWhitespaceInsensitively() throws {
        let enabledForSlack = Self.agent(
            idSuffix: 1,
            name: "Enabled for Slack",
            enabledBundleIDs: ["com.tinyspeck.slackmacgap"]
        )
        let disabledForSlack = Self.agent(
            idSuffix: 2,
            name: "Disabled for Slack",
            disabledBundleIDs: ["com.tinyspeck.slackmacgap"]
        )
        let request = agentRunRequest(
            input: Self.textSnapshot(sourceBundleID: " COM.TINYSPECK.SLACKMACGAP "),
            activeAgents: [enabledForSlack, disabledForSlack]
        )

        let sanitizedRequest = try PrivacyGuard().validateAndRedact(request)

        XCTAssertEqual(sanitizedRequest.activeAgents.map(\.id), [enabledForSlack.id])
    }

    func testRejectsWhenAllAgentsAreBlockedForSourceBundle() {
        let sourceBundleID = "com.tinyspeck.slackmacgap"
        let request = agentRunRequest(
            input: Self.textSnapshot(sourceBundleID: sourceBundleID),
            activeAgents: [
                Self.agent(idSuffix: 1, disabledBundleIDs: [sourceBundleID]),
                Self.agent(idSuffix: 2, enabledBundleIDs: ["com.hnc.Discord"])
            ]
        )

        XCTAssertThrowsError(try PrivacyGuard().validateAndRedact(request)) { error in
            XCTAssertEqual(
                error as? PrivacyGuardError,
                .noAllowedAgentsForSourceBundle(sourceBundleID)
            )
        }
    }

    func testRemovesContextWhenConversationContextIsDisabled() throws {
        let request = agentRunRequest(
            appContext: Self.conversationContext(messageCount: 2),
            privacyPolicy: Self.privacyPolicy(includeConversationContext: false, maxVisibleMessages: 2)
        )

        let sanitizedRequest = try PrivacyGuard().validateAndRedact(request)

        XCTAssertNil(sanitizedRequest.appContext)
    }

    func testLimitsVisibleMessagesToMostRecentMessages() throws {
        let request = agentRunRequest(
            appContext: Self.conversationContext(messageCount: 4),
            privacyPolicy: Self.privacyPolicy(includeConversationContext: true, maxVisibleMessages: 2)
        )

        let sanitizedRequest = try PrivacyGuard().validateAndRedact(request)

        XCTAssertEqual(
            sanitizedRequest.appContext?.visibleMessages.map { $0.id },
            [
                UUID(uuidString: "00000000-0000-0000-0000-000000001002")!,
                UUID(uuidString: "00000000-0000-0000-0000-000000001003")!
            ]
        )
        XCTAssertEqual(
            sanitizedRequest.appContext?.visibleMessages.map { $0.text },
            ["Visible message 2", "Visible message 3"]
        )
    }

    func testRedactsBuiltInAndCustomRulesAcrossRequest() throws {
        let secretEmail = "sam@example.com"
        let secretPhone = "+1 202-555-0188"
        let secretAPIKey = "sk-test1234567890ABCDEF"
        let secretPassword = "hunter2"
        let customSecret = "Project Nebula"
        let request = agentRunRequest(
            input: Self.textSnapshot(
                text: "Email \(secretEmail), phone \(secretPhone), apiKey=\(secretAPIKey), password=\(secretPassword), codename \(customSecret)"
            ),
            activeAgents: [
                Self.agent(
                    idSuffix: 7,
                    name: "Agent for \(customSecret)",
                    systemPrompt: "Never expose \(secretEmail)",
                    instruction: "Use \(customSecret) style.",
                    terminologyRules: [
                        Self.terminologyRule(
                            match: customSecret,
                            replacement: "\(customSecret) launch",
                            note: "Contact \(secretPhone)"
                        )
                    ]
                )
            ],
            appContext: ConversationContext(
                appBundleID: "com.example.Editor",
                conversationTitle: "Thread with \(secretEmail)",
                visibleMessages: [
                    ConversationMessage(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000002001")!,
                        author: secretEmail,
                        timestamp: Date(timeIntervalSince1970: 1_780_000_100),
                        text: "Use apiKey=\(secretAPIKey) and call \(secretPhone)"
                    )
                ]
            ),
            memory: AgentMemory(
                terminologyRules: [
                    Self.terminologyRule(
                        match: secretEmail,
                        replacement: "owner",
                        note: "Password is password=\(secretPassword)"
                    )
                ],
                tonePreferences: ["Mention \(customSecret) quietly"],
                writingRules: ["Do not leak \(secretAPIKey)"]
            ),
            privacyPolicy: Self.privacyPolicy(
                includeConversationContext: true,
                maxVisibleMessages: 3,
                redactionRules: [customSecret]
            )
        )

        let sanitizedRequest = try PrivacyGuard().validateAndRedact(request)
        let encodedRequest = String(data: try JSONEncoder().encode(sanitizedRequest), encoding: .utf8)!

        XCTAssertEqual(
            sanitizedRequest.input.text,
            "Email [REDACTED_EMAIL], phone [REDACTED_PHONE], [REDACTED_API_KEY], [REDACTED_PASSWORD], codename [REDACTED_CUSTOM]"
        )
        XCTAssertEqual(sanitizedRequest.activeAgents[0].name, "Agent for [REDACTED_CUSTOM]")
        XCTAssertEqual(sanitizedRequest.activeAgents[0].systemPrompt, "Never expose [REDACTED_EMAIL]")
        XCTAssertEqual(sanitizedRequest.activeAgents[0].instruction, "Use [REDACTED_CUSTOM] style.")
        XCTAssertEqual(sanitizedRequest.activeAgents[0].terminologyRules[0].match, "[REDACTED_CUSTOM]")
        XCTAssertEqual(sanitizedRequest.activeAgents[0].terminologyRules[0].replacement, "[REDACTED_CUSTOM] launch")
        XCTAssertEqual(sanitizedRequest.activeAgents[0].terminologyRules[0].note, "Contact [REDACTED_PHONE]")
        XCTAssertEqual(sanitizedRequest.appContext?.conversationTitle, "Thread with [REDACTED_EMAIL]")
        XCTAssertEqual(sanitizedRequest.appContext?.visibleMessages[0].author, "[REDACTED_EMAIL]")
        XCTAssertEqual(sanitizedRequest.appContext?.visibleMessages[0].text, "Use [REDACTED_API_KEY] and call [REDACTED_PHONE]")
        XCTAssertEqual(sanitizedRequest.memory.terminologyRules[0].match, "[REDACTED_EMAIL]")
        XCTAssertEqual(sanitizedRequest.memory.terminologyRules[0].note, "Password is [REDACTED_PASSWORD]")
        XCTAssertEqual(sanitizedRequest.memory.tonePreferences, ["Mention [REDACTED_CUSTOM] quietly"])
        XCTAssertEqual(sanitizedRequest.memory.writingRules, ["Do not leak [REDACTED_API_KEY]"])
        XCTAssertEqual(sanitizedRequest.privacyPolicy.redactionRules, ["[REDACTED_CUSTOM]"])
        XCTAssertFalse(encodedRequest.contains(secretEmail))
        XCTAssertFalse(encodedRequest.contains(secretPhone))
        XCTAssertFalse(encodedRequest.contains(secretAPIKey))
        XCTAssertFalse(encodedRequest.contains(secretPassword))
        XCTAssertFalse(encodedRequest.contains(customSecret))
    }

    private func agentRunRequest(
        input: TextSnapshot = textSnapshot(),
        activeAgents: [AgentProfile] = [agent()],
        appContext: ConversationContext? = nil,
        memory: AgentMemory = AgentMemory(terminologyRules: [], tonePreferences: [], writingRules: []),
        privacyPolicy: PrivacyPolicy = privacyPolicy()
    ) -> AgentRunRequest {
        AgentRunRequest(
            input: input,
            activeAgents: activeAgents,
            appContext: appContext,
            memory: memory,
            privacyPolicy: privacyPolicy
        )
    }

    private static func textSnapshot(
        text: String = "Can we deploy after review?",
        sourceBundleID: String = "com.example.Editor",
        sourceElementRole: String? = "AXTextArea"
    ) -> TextSnapshot {
        TextSnapshot(
            text: text,
            selectedRange: nil,
            sourceBundleID: sourceBundleID,
            sourceElementRole: sourceElementRole,
            contentHash: "sha256:test"
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

    private static func conversationContext(messageCount: Int) -> ConversationContext {
        ConversationContext(
            appBundleID: "com.example.Editor",
            conversationTitle: "#release",
            visibleMessages: (0..<messageCount).map { index in
                ConversationMessage(
                    id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 1_000 + index))!,
                    author: index.isMultiple(of: 2) ? "Sam" : "Me",
                    timestamp: Date(timeIntervalSince1970: 1_780_000_000 + TimeInterval(index)),
                    text: "Visible message \(index)"
                )
            }
        )
    }

    private static func agent(
        idSuffix: Int = 1,
        name: String = "Grammar Fixer",
        enabledBundleIDs: [String] = [],
        disabledBundleIDs: [String] = [],
        systemPrompt: String = "You are a careful editor.",
        instruction: String = "Improve the text while preserving intent.",
        terminologyRules: [TerminologyRule] = []
    ) -> AgentProfile {
        AgentProfile(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 2_000 + idSuffix))!,
            name: name,
            description: "\(name) description",
            isEnabled: true,
            isActive: true,
            providerID: AgentProfileStore.defaultProviderID,
            modelOverride: nil,
            systemPrompt: systemPrompt,
            instruction: instruction,
            tone: .neutral,
            aggressiveness: .conservative,
            scope: .currentInput,
            terminologyRules: terminologyRules,
            enabledBundleIDs: enabledBundleIDs,
            disabledBundleIDs: disabledBundleIDs,
            applyMode: .askEveryTime
        )
    }

    private static func terminologyRule(
        match: String,
        replacement: String,
        note: String?
    ) -> TerminologyRule {
        TerminologyRule(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000003001")!,
            match: match,
            replacement: replacement,
            note: note,
            isCaseSensitive: false
        )
    }
}
