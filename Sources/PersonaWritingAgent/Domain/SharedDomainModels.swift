import Foundation

struct LLMProviderConfig: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var baseURL: URL
    var defaultModel: String
    var temperature: Double
    var maxTokens: Int
    var timeoutSeconds: Double
    var keychainServiceName: String
}

struct AgentProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var description: String
    var isEnabled: Bool
    var isActive: Bool
    var providerID: UUID
    var modelOverride: String?
    var systemPrompt: String
    var instruction: String
    var tone: TonePreset
    var aggressiveness: RewriteAggressiveness
    var scope: CorrectionScope
    var terminologyRules: [TerminologyRule]
    var enabledBundleIDs: [String]
    var disabledBundleIDs: [String]
    var applyMode: ApplyMode
}

struct TerminologyRule: Codable, Identifiable, Equatable {
    var id: UUID
    var match: String
    var replacement: String
    var note: String?
    var isCaseSensitive: Bool
}

struct TextSnapshot: Codable, Equatable {
    var text: String
    var selectedRange: Range<Int>?
    var sourceBundleID: String
    var sourceElementRole: String?
    var contentHash: String
}

struct ConversationContext: Codable, Equatable {
    var appBundleID: String
    var conversationTitle: String?
    var visibleMessages: [ConversationMessage]
}

struct ConversationMessage: Codable, Identifiable, Equatable {
    var id: UUID
    var author: String?
    var timestamp: Date?
    var text: String
}

struct AgentRunRequest: Codable, Equatable {
    var input: TextSnapshot
    var activeAgents: [AgentProfile]
    var appContext: ConversationContext?
    var memory: AgentMemory
    var privacyPolicy: PrivacyPolicy
}

struct AgentMemory: Codable, Equatable {
    var terminologyRules: [TerminologyRule]
    var tonePreferences: [String]
    var writingRules: [String]
}

struct PrivacyPolicy: Codable, Equatable {
    var includeConversationContext: Bool
    var maxVisibleMessages: Int
    var allowClipboardFallback: Bool
    var redactionRules: [String]
}

enum CorrectionScope: String, Codable, Equatable, CaseIterable {
    case selectedText
    case currentInput
    case currentParagraph
}

enum ApplyMode: String, Codable, Equatable, CaseIterable {
    case askEveryTime
    case axSelectedText
    case axValue
    case clipboardPaste
}

enum TonePreset: String, Codable, Equatable, CaseIterable {
    case neutral
    case natural
    case friendly
    case professional
    case polite
    case technical
}

enum RewriteAggressiveness: String, Codable, Equatable, CaseIterable {
    case minimal
    case conservative
    case balanced
    case assertive
}
