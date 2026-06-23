import Foundation

final class AgentProfileStore {
    static let defaultProviderID = DefaultSeedConfiguration.providerID
    static let defaultFileName = "AgentProfiles.json"

    static var defaultStore: AgentProfileStore {
        AgentProfileStore(fileURL: defaultFileURL())
    }

    private let fileURL: URL
    private let fileStore: JSONFileStore<[AgentProfile]>

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileStore = JSONFileStore(fileURL: fileURL, fileManager: fileManager)
    }

    func loadProfiles() throws -> [AgentProfile] {
        guard fileStore.fileExists else {
            let profiles = Self.defaultAgents()
            try saveProfiles(profiles)
            return profiles
        }

        return try fileStore.loadIfPresent() ?? []
    }

    func saveProfiles(_ profiles: [AgentProfile]) throws {
        try fileStore.save(profiles)
        NotificationCenter.default.post(name: .overlaygentAgentProfilesDidChange, object: self)
    }

    func resetToDefaultAgents() throws -> [AgentProfile] {
        let profiles = Self.defaultAgents()
        try saveProfiles(profiles)
        return profiles
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        ApplicationSupportPaths(fileManager: fileManager).fileURL(named: defaultFileName)
    }

    static func defaultAgents(providerID: UUID = defaultProviderID) -> [AgentProfile] {
        [
            AgentProfile(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
                name: "Grammar Fixer",
                description: "Fixes grammar, spelling, and punctuation while preserving meaning and tone.",
                isEnabled: true,
                isActive: true,
                providerID: providerID,
                modelOverride: nil,
                systemPrompt: "You are a careful grammar editor. Preserve the user's intended meaning and tone.",
                instruction: "Fix grammar, spelling, punctuation, and small clarity issues. Avoid changing meaning, style, technical names, code identifiers, commands, file paths, or product names.",
                tone: .neutral,
                aggressiveness: .minimal,
                scope: .currentInput,
                terminologyRules: [],
                enabledBundleIDs: [],
                disabledBundleIDs: [],
                applyMode: .askEveryTime
            ),
            AgentProfile(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
                name: "Natural English",
                description: "Makes writing sound natural and fluent while keeping the original intent.",
                isEnabled: true,
                isActive: true,
                providerID: providerID,
                modelOverride: nil,
                systemPrompt: "You are an editor who makes English sound natural to native speakers.",
                instruction: "Rewrite awkward phrasing into natural English. Keep the user's meaning, avoid over-polishing, and preserve technical terms, names, commands, and file paths.",
                tone: .natural,
                aggressiveness: .balanced,
                scope: .currentInput,
                terminologyRules: [],
                enabledBundleIDs: [],
                disabledBundleIDs: [],
                applyMode: .askEveryTime
            ),
            AgentProfile(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
                name: "Coding Terms",
                description: "Improves developer English for PRs, issues, deploy notes, APIs, and technical chat.",
                isEnabled: true,
                isActive: false,
                providerID: providerID,
                modelOverride: nil,
                systemPrompt: "You are a technical writing editor for software engineers.",
                instruction: "Improve developer English and terminology without changing intent. Preserve code identifiers, API names, commands, error text, branch names, file paths, versions, and quoted strings.",
                tone: .technical,
                aggressiveness: .conservative,
                scope: .currentInput,
                terminologyRules: [
                    TerminologyRule(
                        id: UUID(uuidString: "11000000-0000-0000-0000-000000000001")!,
                        match: "make deploy",
                        replacement: "deploy it",
                        note: "Prefer natural deploy phrasing.",
                        isCaseSensitive: false
                    )
                ],
                enabledBundleIDs: [],
                disabledBundleIDs: [],
                applyMode: .askEveryTime
            ),
            AgentProfile(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!,
                name: "Tone Polish",
                description: "Polishes messages into a polite, clear workplace tone.",
                isEnabled: true,
                isActive: false,
                providerID: providerID,
                modelOverride: nil,
                systemPrompt: "You are a concise workplace communication editor.",
                instruction: "Make the message more polite, clear, and work-appropriate for Slack, Notion, and email-style writing. Keep it concise and do not add new facts.",
                tone: .polite,
                aggressiveness: .conservative,
                scope: .currentInput,
                terminologyRules: [],
                enabledBundleIDs: [],
                disabledBundleIDs: [],
                applyMode: .askEveryTime
            )
        ]
    }

    static func newAgent(providerID: UUID = defaultProviderID) -> AgentProfile {
        AgentProfile(
            id: UUID(),
            name: "New Agent",
            description: "",
            isEnabled: true,
            isActive: false,
            providerID: providerID,
            modelOverride: nil,
            systemPrompt: "You are a helpful writing assistant.",
            instruction: "Improve the selected writing while preserving the user's intent.",
            tone: .neutral,
            aggressiveness: .conservative,
            scope: .currentInput,
            terminologyRules: [],
            enabledBundleIDs: [],
            disabledBundleIDs: [],
            applyMode: .askEveryTime
        )
    }

    static func duplicate(_ profile: AgentProfile) -> AgentProfile {
        AgentProfile(
            id: UUID(),
            name: "\(profile.name) Copy",
            description: profile.description,
            isEnabled: profile.isEnabled,
            isActive: false,
            providerID: profile.providerID,
            modelOverride: profile.modelOverride,
            systemPrompt: profile.systemPrompt,
            instruction: profile.instruction,
            tone: profile.tone,
            aggressiveness: profile.aggressiveness,
            scope: profile.scope,
            terminologyRules: profile.terminologyRules,
            enabledBundleIDs: profile.enabledBundleIDs,
            disabledBundleIDs: profile.disabledBundleIDs,
            applyMode: profile.applyMode
        )
    }
}
