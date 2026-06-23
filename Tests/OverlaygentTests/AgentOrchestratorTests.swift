import XCTest
@testable import Overlaygent

final class AgentOrchestratorTests: XCTestCase {
    func testSelectsGrammarAndCodingTermsForTechnicalEnglishInput() {
        let agents = allDefaultAgentsActive()
        let orchestrator = RuleBasedAgentOrchestrator()

        let selectedAgents = orchestrator.selectAgents(
            from: agents,
            context: context(
                text: "Can we make deploy after PR approved? The API endpoint returns 500.",
                sourceBundleID: "com.microsoft.VSCode"
            )
        )

        XCTAssertEqual(selectedAgents.map(\.name), ["Grammar Fixer", "Coding Terms"])
    }

    func testSelectsGrammarAndNaturalEnglishForGeneralEnglishInput() {
        let agents = allDefaultAgentsActive()
        let orchestrator = RuleBasedAgentOrchestrator()

        let selectedAgents = orchestrator.selectAgents(
            from: agents,
            context: context(
                text: "I want to talk about next week's plan after lunch.",
                sourceBundleID: "com.tinyspeck.slackmacgap"
            )
        )

        XCTAssertEqual(selectedAgents.map(\.name), ["Grammar Fixer", "Natural English"])
    }

    func testSelectsGrammarAndTonePolishForPoliteWorkplaceInput() {
        let agents = allDefaultAgentsActive()
        let orchestrator = RuleBasedAgentOrchestrator()

        let selectedAgents = orchestrator.selectAgents(
            from: agents,
            context: context(
                text: "Could you please review this when you have a moment? I would appreciate your thoughts.",
                sourceBundleID: "com.tinyspeck.slackmacgap"
            )
        )

        XCTAssertEqual(selectedAgents.map(\.name), ["Grammar Fixer", "Tone Polish"])
    }

    func testSelectedAgentsPreserveCandidateOrderForOverlayPresentation() {
        let agents = allDefaultAgentsActive()
        let reorderedAgents = [
            agents[3],
            agents[0],
            agents[1],
            agents[2]
        ]
        let orchestrator = RuleBasedAgentOrchestrator()

        let selectedAgents = orchestrator.selectAgents(
            from: reorderedAgents,
            context: context(
                text: "Could you please review this when you have a moment? I would appreciate your thoughts.",
                sourceBundleID: "com.tinyspeck.slackmacgap"
            )
        )

        XCTAssertEqual(selectedAgents.map(\.name), ["Tone Polish", "Grammar Fixer"])
    }

    func testReturnsNoAgentsForMostlyNonEnglishInput() {
        let agents = allDefaultAgentsActive()
        let orchestrator = RuleBasedAgentOrchestrator()

        let selectedAgents = orchestrator.selectAgents(
            from: agents,
            context: context(
                text: "배포 끝나면 알려줘",
                sourceBundleID: "com.tinyspeck.slackmacgap"
            )
        )

        XCTAssertEqual(selectedAgents.map(\.name), [])
    }

    func testStoreBackedOrchestratorUsesPersistedSelectionLimit() {
        let agents = allDefaultAgentsActive()
        let orchestrator = StoreBackedAgentOrchestrator(
            settingsLoader: FixedOrchestratorSettingsLoader(
                settings: OrchestratorSettings(maximumSelectedAgents: 1)
            ),
            logger: { _ in }
        )

        let selectedAgents = orchestrator.selectAgents(
            from: agents,
            context: context(
                text: "Can we make deploy after PR approved? The API endpoint returns 500.",
                sourceBundleID: "com.microsoft.VSCode"
            )
        )

        XCTAssertEqual(selectedAgents.count, 1)
    }

    private func allDefaultAgentsActive() -> [AgentProfile] {
        var agents = AgentProfileStore.defaultAgents()
        for index in agents.indices {
            agents[index].isActive = true
        }
        return agents
    }

    private func context(
        text: String,
        sourceBundleID: String
    ) -> AgentOrchestrationContext {
        AgentOrchestrationContext(
            input: TextSnapshot(
                text: text,
                selectedRange: 0..<text.count,
                sourceBundleID: sourceBundleID,
                sourceElementRole: "AXTextArea",
                contentHash: "sha256:orchestrator-test"
            ),
            appContext: nil,
            privacyPolicy: PrivacyPolicy(
                includeConversationContext: false,
                maxVisibleMessages: 0,
                allowClipboardFallback: false,
                redactionRules: []
            )
        )
    }
}

private struct FixedOrchestratorSettingsLoader: OrchestratorSettingsLoading {
    var settings: OrchestratorSettings

    func loadSettings() throws -> OrchestratorSettings {
        settings
    }
}
