import Foundation

enum AgentMessageRole: String, Codable, Equatable, CaseIterable {
    case system
    case developer
    case user
}

struct AgentMessage: Codable, Equatable {
    var role: AgentMessageRole
    var content: String
}

struct AgentMessageBudgetMetadata: Codable, Equatable {
    var characterBudget: Int?
    var maxVisibleMessages: Int
    var includeConversationContext: Bool
    var inputCharacterCount: Int
    var retainedInputCharacterCount: Int
    var originalAgentTerminologyRuleCount: Int
    var retainedAgentTerminologyRuleCount: Int
    var originalMemoryTerminologyRuleCount: Int
    var retainedMemoryTerminologyRuleCount: Int
    var originalTonePreferenceCount: Int
    var retainedTonePreferenceCount: Int
    var originalWritingRuleCount: Int
    var retainedWritingRuleCount: Int
    var originalVisibleMessageCount: Int
    var retainedVisibleMessageCount: Int
    var didTrimForCharacterBudget: Bool
    var didTrimVisibleMessages: Bool
}

struct AgentMessageBundle: Codable, Equatable {
    var agentID: UUID
    var agentName: String
    var providerID: UUID
    var resolvedModel: String?
    var messages: [AgentMessage]
    var outputSchemaID: String
    var budgetMetadata: AgentMessageBudgetMetadata
}
