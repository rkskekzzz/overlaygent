import Foundation

struct OrchestratorSettings: Codable, Equatable, Identifiable {
    static let defaultID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!

    var id: UUID
    var name: String
    var description: String
    var maximumSelectedAgents: Int

    init(
        id: UUID = OrchestratorSettings.defaultID,
        name: String = "Root Orchestrator",
        description: String = "Chooses which active agents should run for the current input.",
        maximumSelectedAgents: Int = 2
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.maximumSelectedAgents = Self.clampedMaximumSelectedAgents(maximumSelectedAgents)
    }

    static func clampedMaximumSelectedAgents(_ value: Int) -> Int {
        min(max(value, 1), 4)
    }
}

struct AgentOrchestrationContext: Equatable {
    var input: TextSnapshot
    var appContext: ConversationContext?
    var privacyPolicy: PrivacyPolicy
}

protocol OrchestratorSettingsLoading {
    func loadSettings() throws -> OrchestratorSettings
}

protocol AgentOrchestrating {
    func selectAgents(
        from candidates: [AgentProfile],
        context: AgentOrchestrationContext
    ) -> [AgentProfile]
}

struct StoreBackedAgentOrchestrator: AgentOrchestrating {
    typealias Logger = (String) -> Void

    private let settingsLoader: any OrchestratorSettingsLoading
    private let logger: Logger

    init(
        settingsLoader: any OrchestratorSettingsLoading,
        logger: @escaping Logger = SafeLogger.default.log
    ) {
        self.settingsLoader = settingsLoader
        self.logger = logger
    }

    func selectAgents(
        from candidates: [AgentProfile],
        context: AgentOrchestrationContext
    ) -> [AgentProfile] {
        let settings: OrchestratorSettings
        do {
            settings = try settingsLoader.loadSettings()
        } catch {
            logger("Failed to load orchestrator settings: \(SafeLogger.redacted(String(describing: error)))")
            settings = OrchestratorSettings()
        }

        return RuleBasedAgentOrchestrator(settings: settings).selectAgents(
            from: candidates,
            context: context
        )
    }
}

struct RuleBasedAgentOrchestrator: AgentOrchestrating, Equatable {
    var maximumSelectedAgents: Int

    init(maximumSelectedAgents: Int = 2) {
        self.maximumSelectedAgents = OrchestratorSettings.clampedMaximumSelectedAgents(maximumSelectedAgents)
    }

    init(settings: OrchestratorSettings) {
        self.init(maximumSelectedAgents: settings.maximumSelectedAgents)
    }

    func selectAgents(
        from candidates: [AgentProfile],
        context: AgentOrchestrationContext
    ) -> [AgentProfile] {
        guard candidates.isEmpty == false else {
            return []
        }

        let signals = InputSignals(context: context)
        let scoredAgents = candidates.enumerated().compactMap { index, agent -> ScoredAgent? in
            let score = score(agent: agent, signals: signals)
            guard score > 0 else {
                return nil
            }

            return ScoredAgent(index: index, agent: agent, score: score)
        }

        let selectedIDs = Set(
            scoredAgents
                .sorted { lhs, rhs in
                    if lhs.score == rhs.score {
                        return lhs.index < rhs.index
                    }

                    return lhs.score > rhs.score
                }
                .prefix(maximumSelectedAgents)
                .map(\.agent.id)
        )

        return candidates.filter { selectedIDs.contains($0.id) }
    }

    private func score(agent: AgentProfile, signals: InputSignals) -> Int {
        guard signals.isMostlyEnglish else {
            return 0
        }

        let profileText = searchableText(for: agent)
        var score = 5

        if isGrammarAgent(profileText) {
            score += 80
        }

        if signals.isTechnical {
            if isTechnicalAgent(profileText, agent: agent) {
                score += 90
            }
        } else if signals.needsTonePolish {
            if isToneAgent(profileText, agent: agent) {
                score += 85
            } else if isNaturalAgent(profileText, agent: agent) {
                score += 40
            }
        } else if isNaturalAgent(profileText, agent: agent) {
            score += 75
        }

        if terminologyMatches(agent: agent, inputText: signals.lowercasedText) {
            score += 25
        }

        return score
    }

    private func searchableText(for agent: AgentProfile) -> String {
        let terminologyText = agent.terminologyRules
            .flatMap { rule in
                [rule.match, rule.replacement, rule.note ?? ""]
            }
            .joined(separator: " ")

        return [
            agent.name,
            agent.description,
            agent.systemPrompt,
            agent.instruction,
            agent.tone.rawValue,
            terminologyText
        ]
        .joined(separator: " ")
        .lowercased()
    }

    private func isGrammarAgent(_ profileText: String) -> Bool {
        profileText.contains("grammar")
            || profileText.contains("spelling")
            || profileText.contains("punctuation")
    }

    private func isTechnicalAgent(_ profileText: String, agent: AgentProfile) -> Bool {
        agent.tone == .technical
            || profileText.contains("coding")
            || profileText.contains("developer")
            || profileText.contains("technical")
            || profileText.contains("api")
            || profileText.contains("pull request")
            || profileText.contains("deploy")
    }

    private func isNaturalAgent(_ profileText: String, agent: AgentProfile) -> Bool {
        agent.tone == .natural
            || profileText.contains("natural english")
            || profileText.contains("fluent")
            || profileText.contains("native speakers")
    }

    private func isToneAgent(_ profileText: String, agent: AgentProfile) -> Bool {
        agent.tone == .polite
            || agent.tone == .professional
            || profileText.contains("tone")
            || profileText.contains("polite")
            || profileText.contains("workplace")
    }

    private func terminologyMatches(agent: AgentProfile, inputText: String) -> Bool {
        agent.terminologyRules.contains { rule in
            let match = rule.isCaseSensitive ? rule.match : rule.match.lowercased()
            return match.isEmpty == false && inputText.contains(match)
        }
    }
}

private struct ScoredAgent {
    var index: Int
    var agent: AgentProfile
    var score: Int
}

private struct InputSignals {
    var lowercasedText: String
    var words: Set<String>
    var isMostlyEnglish: Bool
    var isTechnical: Bool
    var needsTonePolish: Bool

    init(context: AgentOrchestrationContext) {
        let contextText = [
            context.input.text,
            context.appContext?.conversationTitle ?? "",
            context.appContext?.visibleMessages.map(\.text).joined(separator: " ") ?? ""
        ]
        .joined(separator: " ")

        lowercasedText = contextText.lowercased()
        words = Set(
            lowercasedText.split { character in
                character.isLetter == false && character.isNumber == false
            }.map(String.init)
        )

        isMostlyEnglish = Self.isMostlyEnglish(context.input.text)
        isTechnical = Self.detectTechnicalContext(
            lowercasedText: lowercasedText,
            words: words,
            sourceBundleID: context.input.sourceBundleID
        )
        needsTonePolish = Self.detectTonePolishNeed(
            lowercasedText: lowercasedText,
            words: words,
            sourceBundleID: context.input.sourceBundleID
        )
    }

    private static func isMostlyEnglish(_ text: String) -> Bool {
        let counts = text.unicodeScalars.reduce((latin: 0, hangul: 0)) { counts, scalar in
            let value = scalar.value
            if (65...90).contains(value) || (97...122).contains(value) {
                return (counts.latin + 1, counts.hangul)
            }

            if (0xAC00...0xD7A3).contains(value) {
                return (counts.latin, counts.hangul + 1)
            }

            return counts
        }

        return counts.latin >= 3 && counts.latin >= counts.hangul
    }

    private static func detectTechnicalContext(
        lowercasedText: String,
        words: Set<String>,
        sourceBundleID: String
    ) -> Bool {
        let technicalWords: Set<String> = [
            "api",
            "branch",
            "build",
            "cli",
            "commit",
            "db",
            "deploy",
            "diff",
            "endpoint",
            "error",
            "exception",
            "http",
            "json",
            "merge",
            "migration",
            "pr",
            "runtime",
            "sdk",
            "sql",
            "stack",
            "test"
        ]

        if words.isDisjoint(with: technicalWords) == false {
            return true
        }

        let technicalPhrases = [
            "pull request",
            "stack trace",
            "code review",
            "feature flag",
            "localhost",
            ".swift",
            ".ts",
            ".tsx",
            ".js",
            ".jsx",
            ".py",
            ".rb",
            ".go",
            ".rs",
            ".java",
            "src/",
            "sources/",
            "tests/",
            "```",
            "->",
            "=>",
            "==",
            "!="
        ]

        if technicalPhrases.contains(where: { lowercasedText.contains($0) }) {
            return true
        }

        let lowercasedBundleID = sourceBundleID.lowercased()
        return [
            "cursor",
            "iterm",
            "jetbrains",
            "terminal",
            "vscode",
            "warp",
            "xcode",
            "zed"
        ].contains { lowercasedBundleID.contains($0) }
    }

    private static func detectTonePolishNeed(
        lowercasedText: String,
        words: Set<String>,
        sourceBundleID: String
    ) -> Bool {
        let politeWords: Set<String> = [
            "appreciate",
            "could",
            "please",
            "thanks",
            "would"
        ]
        let lowercasedBundleID = sourceBundleID.lowercased()
        let isWorkApp = [
            "mail",
            "notion",
            "slack",
            "tinyspeck"
        ].contains { lowercasedBundleID.contains($0) }

        return words.isDisjoint(with: politeWords) == false
            || (isWorkApp && lowercasedText.count > 120)
    }
}
