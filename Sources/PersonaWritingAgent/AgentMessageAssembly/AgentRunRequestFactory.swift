import Foundation

extension FocusedTextSession: AgentRunInputCapturing {}

protocol AgentProfileLoading {
    func loadProfiles() throws -> [AgentProfile]
}

extension AgentProfileStore: AgentProfileLoading {}

protocol AgentMemoryLoading {
    func loadMemory() throws -> AgentMemory
}

extension AgentMemoryStore: AgentMemoryLoading {}

protocol AgentRunContextResolving {
    func context(for request: AppContextExtractionRequest) -> ConversationContext?
}

extension AppContextAdapterRegistry: AgentRunContextResolving {}

struct AgentRunPrivacyOptions: Equatable {
    var includeConversationContext: Bool
    var maxVisibleMessages: Int
    var allowClipboardFallback: Bool
    var redactionRules: [String]

    init(
        includeConversationContext: Bool = false,
        maxVisibleMessages: Int = 0,
        allowClipboardFallback: Bool = false,
        redactionRules: [String] = []
    ) {
        self.includeConversationContext = includeConversationContext
        self.maxVisibleMessages = max(0, maxVisibleMessages)
        self.allowClipboardFallback = allowClipboardFallback
        self.redactionRules = redactionRules
    }

    var privacyPolicy: PrivacyPolicy {
        PrivacyPolicy(
            includeConversationContext: includeConversationContext,
            maxVisibleMessages: maxVisibleMessages,
            allowClipboardFallback: allowClipboardFallback,
            redactionRules: redactionRules
        )
    }
}

struct AgentRunPreparedRequest: Equatable {
    var request: AgentRunRequest
    var geometry: AXTextGeometry
    var focusedElement: AXFocusedElement?

    init(
        request: AgentRunRequest,
        geometry: AXTextGeometry,
        focusedElement: AXFocusedElement? = nil
    ) {
        self.request = request
        self.geometry = geometry
        self.focusedElement = focusedElement
    }
}

enum AgentRunRequestFactoryError: Error, Equatable {
    case noActiveEnabledAgents
}

struct AgentRunRequestFactory {
    private let textSession: any AgentRunInputCapturing
    private let agentProfileStore: any AgentProfileLoading
    private let memoryStore: any AgentMemoryLoading
    private let contextResolver: any AgentRunContextResolving

    init(
        textSession: any AgentRunInputCapturing,
        agentProfileStore: any AgentProfileLoading,
        memoryStore: any AgentMemoryLoading,
        contextResolver: any AgentRunContextResolving
    ) {
        self.textSession = textSession
        self.agentProfileStore = agentProfileStore
        self.memoryStore = memoryStore
        self.contextResolver = contextResolver
    }

    func makeRequest(
        focusedElement: AXFocusedElement? = nil,
        privacyOptions: AgentRunPrivacyOptions = AgentRunPrivacyOptions()
    ) throws -> AgentRunRequest {
        let activeAgents = try agentProfileStore.loadProfiles().filter { profile in
            profile.isActive && profile.isEnabled
        }
        guard activeAgents.isEmpty == false else {
            throw AgentRunRequestFactoryError.noActiveEnabledAgents
        }

        let capture = try textSession.capture()
        return try makeRequest(
            activeAgents: activeAgents,
            capture: capture,
            focusedElement: focusedElement ?? capture.focusedElement,
            privacyOptions: privacyOptions
        )
    }

    func makePreparedRequest(
        privacyOptions: AgentRunPrivacyOptions = AgentRunPrivacyOptions()
    ) throws -> AgentRunPreparedRequest {
        let activeAgents = try agentProfileStore.loadProfiles().filter { profile in
            profile.isActive && profile.isEnabled
        }
        guard activeAgents.isEmpty == false else {
            throw AgentRunRequestFactoryError.noActiveEnabledAgents
        }

        let capture = try textSession.capture()
        let request = try makeRequest(
            activeAgents: activeAgents,
            capture: capture,
            focusedElement: capture.focusedElement,
            privacyOptions: privacyOptions
        )

        return AgentRunPreparedRequest(
            request: request,
            geometry: capture.geometry,
            focusedElement: capture.focusedElement
        )
    }

    private func makeRequest(
        activeAgents: [AgentProfile],
        capture: FocusedTextCapture,
        focusedElement: AXFocusedElement?,
        privacyOptions: AgentRunPrivacyOptions
    ) throws -> AgentRunRequest {
        let snapshot = capture.snapshot
        let memory = try memoryStore.loadMemory()
        let privacyPolicy = privacyOptions.privacyPolicy
        let appContext = resolveContext(
            snapshot: snapshot,
            focusedElement: focusedElement,
            privacyPolicy: privacyPolicy
        )

        return AgentRunRequest(
            input: snapshot,
            activeAgents: activeAgents,
            appContext: appContext,
            memory: memory,
            privacyPolicy: privacyPolicy
        )
    }

    private func resolveContext(
        snapshot: TextSnapshot,
        focusedElement: AXFocusedElement?,
        privacyPolicy: PrivacyPolicy
    ) -> ConversationContext? {
        guard privacyPolicy.includeConversationContext else {
            return nil
        }

        let request = AppContextExtractionRequest(
            snapshot: snapshot,
            focusedElement: focusedElement,
            includeConversationContext: privacyPolicy.includeConversationContext,
            maxVisibleMessages: privacyPolicy.maxVisibleMessages
        )
        return contextResolver.context(for: request)
    }
}
