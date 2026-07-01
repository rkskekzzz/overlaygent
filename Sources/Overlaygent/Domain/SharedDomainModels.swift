import Foundation

struct LLMProviderConfig: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var category: LLMProviderCategory
    var kind: LLMProviderKind
    var endpoint: LLMProviderEndpointConfig
    var auth: LLMProviderAuthConfig
    var defaultModel: String
    var reasoningEffort: ReasoningEffort? = nil
    var temperature: Double
    var maxTokens: Int
    var timeoutSeconds: Double

    var baseURL: URL {
        get {
            endpoint.baseURL ?? URL(string: "https://api.openai.com/v1")!
        }
        set {
            endpoint.baseURL = newValue
        }
    }

    var keychainServiceName: String {
        get {
            auth.keychainServiceName ?? "Overlaygent.LLMProvider.\(id.uuidString)"
        }
        set {
            auth.keychainServiceName = newValue
        }
    }

    init(
        id: UUID,
        name: String,
        category: LLMProviderCategory = .api,
        kind: LLMProviderKind = .openAICompatibleAPI,
        endpoint: LLMProviderEndpointConfig? = nil,
        auth: LLMProviderAuthConfig? = nil,
        baseURL: URL,
        defaultModel: String,
        reasoningEffort: ReasoningEffort? = nil,
        temperature: Double,
        maxTokens: Int,
        timeoutSeconds: Double,
        keychainServiceName: String
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.kind = kind
        self.endpoint = endpoint ?? LLMProviderEndpointConfig(
            baseURL: baseURL,
            wireAPI: kind.defaultWireAPI,
            extraHeaders: [:]
        )
        self.auth = auth ?? LLMProviderAuthConfig(
            mode: kind.defaultAuthMode,
            keychainServiceName: keychainServiceName,
            subscriptionService: kind.subscriptionService,
            profileID: nil,
            credentialCommand: nil
        )
        self.defaultModel = defaultModel
        self.reasoningEffort = reasoningEffort
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.timeoutSeconds = timeoutSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case kind
        case endpoint
        case auth
        case baseURL
        case defaultModel
        case reasoningEffort
        case temperature
        case maxTokens
        case timeoutSeconds
        case keychainServiceName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let category = try container.decodeIfPresent(LLMProviderCategory.self, forKey: .category) ?? .api
        let kind = try container.decodeIfPresent(LLMProviderKind.self, forKey: .kind) ?? .openAICompatibleAPI
        let legacyBaseURL = try container.decodeIfPresent(URL.self, forKey: .baseURL)
        var endpoint = try container.decodeIfPresent(LLMProviderEndpointConfig.self, forKey: .endpoint)
        if endpoint == nil {
            endpoint = LLMProviderEndpointConfig(
                baseURL: legacyBaseURL ?? kind.defaultBaseURL,
                wireAPI: kind.defaultWireAPI,
                extraHeaders: [:]
            )
        }

        let legacyKeychainServiceName = try container.decodeIfPresent(String.self, forKey: .keychainServiceName)
            ?? "Overlaygent.LLMProvider.\(id.uuidString)"
        var auth = try container.decodeIfPresent(LLMProviderAuthConfig.self, forKey: .auth)
        if auth == nil {
            auth = LLMProviderAuthConfig(
                mode: kind.defaultAuthMode,
                keychainServiceName: legacyKeychainServiceName,
                subscriptionService: kind.subscriptionService,
                profileID: nil,
                credentialCommand: nil
            )
        }

        self.id = id
        self.name = name
        self.category = category
        self.kind = kind
        self.endpoint = endpoint!
        self.auth = auth!
        self.defaultModel = try container.decode(String.self, forKey: .defaultModel)
        self.reasoningEffort = try container.decodeIfPresent(ReasoningEffort.self, forKey: .reasoningEffort)
        self.temperature = try container.decode(Double.self, forKey: .temperature)
        self.maxTokens = try container.decode(Int.self, forKey: .maxTokens)
        self.timeoutSeconds = try container.decode(Double.self, forKey: .timeoutSeconds)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(category, forKey: .category)
        try container.encode(kind, forKey: .kind)
        try container.encode(endpoint, forKey: .endpoint)
        try container.encode(auth, forKey: .auth)
        try container.encode(defaultModel, forKey: .defaultModel)
        try container.encodeIfPresent(reasoningEffort, forKey: .reasoningEffort)
        try container.encode(temperature, forKey: .temperature)
        try container.encode(maxTokens, forKey: .maxTokens)
        try container.encode(timeoutSeconds, forKey: .timeoutSeconds)
    }
}

enum LLMProviderCategory: String, Codable, Equatable, CaseIterable, Identifiable {
    case subscription
    case api
    case local

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .subscription:
            return "Subscription"
        case .api:
            return "API"
        case .local:
            return "Local"
        }
    }
}

enum LLMProviderKind: String, Codable, Equatable, CaseIterable {
    case chatGPTSubscription
    case openAICompatibleAPI
    case localOpenAICompatible

    var defaultAuthMode: LLMProviderAuthMode {
        switch self {
        case .chatGPTSubscription:
            return .subscriptionOAuth
        case .openAICompatibleAPI:
            return .apiKey
        case .localOpenAICompatible:
            return .none
        }
    }

    var defaultWireAPI: LLMProviderWireAPI {
        switch self {
        case .chatGPTSubscription:
            return .codexBackendResponses
        case .openAICompatibleAPI, .localOpenAICompatible:
            return .openAIChatCompletions
        }
    }

    var defaultBaseURL: URL {
        switch self {
        case .chatGPTSubscription:
            return URL(string: "https://chatgpt.com/backend-api/codex")!
        case .openAICompatibleAPI:
            return URL(string: "https://api.openai.com/v1")!
        case .localOpenAICompatible:
            return URL(string: "http://localhost:11434/v1")!
        }
    }

    var subscriptionService: SubscriptionService? {
        switch self {
        case .chatGPTSubscription:
            return .chatGPT
        case .openAICompatibleAPI, .localOpenAICompatible:
            return nil
        }
    }
}

enum LLMProviderWireAPI: String, Codable, Equatable {
    case openAIChatCompletions
    case openAIResponses
    case codexBackendResponses
}

enum LLMProviderAuthMode: String, Codable, Equatable {
    case subscriptionOAuth
    case apiKey
    case bearerTokenCommand
    case none
}

enum SubscriptionService: String, Codable, Equatable {
    case chatGPT
}

struct LLMProviderAuthConfig: Codable, Equatable {
    var mode: LLMProviderAuthMode
    var keychainServiceName: String?
    var subscriptionService: SubscriptionService?
    var profileID: String?
    var credentialCommand: CredentialCommandConfig?
}

struct LLMProviderEndpointConfig: Codable, Equatable {
    var baseURL: URL?
    var wireAPI: LLMProviderWireAPI
    var extraHeaders: [String: String]
}

struct CredentialCommandConfig: Codable, Equatable {
    var command: String
    var arguments: [String]
    var timeoutSeconds: Double
}

enum ReasoningEffort: String, Codable, Equatable, CaseIterable, Identifiable {
    case none
    case minimal
    case low
    case medium
    case high
    case xhigh

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .none:
            return "None"
        case .minimal:
            return "Minimal"
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        case .xhigh:
            return "XHigh"
        }
    }
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
