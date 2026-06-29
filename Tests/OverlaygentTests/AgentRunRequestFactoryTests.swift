import Foundation
import CoreGraphics
import XCTest
@testable import Overlaygent

final class AgentRunRequestFactoryTests: XCTestCase {
    func testMakeRequestCombinesActiveEnabledAgentsSnapshotContextMemoryAndPrivacyPolicy() throws {
        let snapshot = textSnapshot(sourceBundleID: "com.tinyspeck.slackmacgap")
        let activeEnabledAgent = agent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000701")!,
            name: "Natural English",
            isEnabled: true,
            isActive: true
        )
        let disabledActiveAgent = agent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000702")!,
            name: "Disabled Active",
            isEnabled: false,
            isActive: true
        )
        let enabledInactiveAgent = agent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000703")!,
            name: "Enabled Inactive",
            isEnabled: true,
            isActive: false
        )
        let memory = AgentMemory(
            terminologyRules: [
                TerminologyRule(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000704")!,
                    match: "make deploy",
                    replacement: "deploy it",
                    note: "Prefer natural engineering phrasing.",
                    isCaseSensitive: false
                )
            ],
            tonePreferences: ["concise", "friendly"],
            writingRules: ["Preserve code identifiers."]
        )
        let expectedContext = conversationContext(messageCount: 2)
        let focusedElement = AXFocusedElement(
            element: AXElement(FakeAXNode()),
            role: "AXTextArea",
            subrole: nil,
            value: snapshot.text,
            selectedRange: AXTextRange(location: 0, length: 6)
        )
        let contextResolver = RecordingContextResolver(result: expectedContext)
        let factory = AgentRunRequestFactory(
            textSession: FakeInputCapturer(snapshot: snapshot),
            agentProfileStore: FakeAgentProfileLoader(
                profiles: [activeEnabledAgent, disabledActiveAgent, enabledInactiveAgent]
            ),
            memoryStore: FakeAgentMemoryLoader(memory: memory),
            contextResolver: contextResolver
        )

        let request = try factory.makeRequest(
            focusedElement: focusedElement,
            privacyOptions: AgentRunPrivacyOptions(
                includeConversationContext: true,
                maxVisibleMessages: 5,
                allowClipboardFallback: true,
                redactionRules: ["email", "phone"]
            )
        )

        XCTAssertEqual(request.input, snapshot)
        XCTAssertEqual(request.activeAgents, [activeEnabledAgent])
        XCTAssertEqual(request.memory, memory)
        XCTAssertEqual(request.appContext, expectedContext)
        XCTAssertEqual(
            request.privacyPolicy,
            PrivacyPolicy(
                includeConversationContext: true,
                maxVisibleMessages: 5,
                allowClipboardFallback: true,
                redactionRules: ["email", "phone"]
            )
        )
        XCTAssertEqual(
            contextResolver.requests,
            [
                AppContextExtractionRequest(
                    snapshot: snapshot,
                    focusedElement: focusedElement,
                    includeConversationContext: true,
                    maxVisibleMessages: 5
                )
            ]
        )
    }

    func testMakeRequestOmitsContextAndDoesNotAskResolverWhenConversationContextIsDisabled() throws {
        let snapshot = textSnapshot(sourceBundleID: "com.apple.TextEdit")
        let contextResolver = RecordingContextResolver(result: conversationContext(messageCount: 1))
        let factory = AgentRunRequestFactory(
            textSession: FakeInputCapturer(snapshot: snapshot),
            agentProfileStore: FakeAgentProfileLoader(profiles: [agent(isEnabled: true, isActive: true)]),
            memoryStore: FakeAgentMemoryLoader(memory: AgentMemoryStore.defaultMemory()),
            contextResolver: contextResolver
        )

        let request = try factory.makeRequest(
            privacyOptions: AgentRunPrivacyOptions(
                includeConversationContext: false,
                maxVisibleMessages: 3,
                allowClipboardFallback: false,
                redactionRules: []
            )
        )

        XCTAssertNil(request.appContext)
        XCTAssertEqual(contextResolver.requests, [])
        XCTAssertEqual(request.privacyPolicy.includeConversationContext, false)
        XCTAssertEqual(request.privacyPolicy.maxVisibleMessages, 3)
    }

    func testMakePreparedRequestPassesCapturedFocusedElementAndGeometryToContext() throws {
        let snapshot = textSnapshot(sourceBundleID: "com.tinyspeck.slackmacgap")
        let focusedElement = AXFocusedElement(
            element: AXElement(FakeAXNode()),
            role: "AXTextArea",
            subrole: nil,
            value: snapshot.text,
            selectedRange: AXTextRange(location: 0, length: 6)
        )
        let geometry = AXTextGeometry(
            selectionBounds: CGRect(x: 120, y: 280, width: 220, height: 24),
            caretBounds: CGRect(x: 338, y: 280, width: 2, height: 24)
        )
        let contextResolver = RecordingContextResolver(result: conversationContext(messageCount: 1))
        let factory = AgentRunRequestFactory(
            textSession: FakeInputCapturer(
                snapshot: snapshot,
                focusedElement: focusedElement,
                geometry: geometry
            ),
            agentProfileStore: FakeAgentProfileLoader(profiles: [agent(isEnabled: true, isActive: true)]),
            memoryStore: FakeAgentMemoryLoader(memory: AgentMemoryStore.defaultMemory()),
            contextResolver: contextResolver
        )

        let preparedRequest = try factory.makePreparedRequest(
            privacyOptions: AgentRunPrivacyOptions(
                includeConversationContext: true,
                maxVisibleMessages: 3
            )
        )

        XCTAssertEqual(preparedRequest.geometry, geometry)
        XCTAssertEqual(preparedRequest.request.input, snapshot)
        XCTAssertEqual(
            contextResolver.requests,
            [
                AppContextExtractionRequest(
                    snapshot: snapshot,
                    focusedElement: focusedElement,
                    includeConversationContext: true,
                    maxVisibleMessages: 3
                )
            ]
        )
    }

    func testMakeRequestUsesOrchestratorSelectionFromActiveEnabledCandidates() throws {
        let snapshot = textSnapshot(sourceBundleID: "com.microsoft.VSCode")
        let grammar = agent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000721")!,
            name: "Grammar Fixer",
            isEnabled: true,
            isActive: true
        )
        let codingTerms = agent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000722")!,
            name: "Coding Terms",
            isEnabled: true,
            isActive: true
        )
        let disabledActiveAgent = agent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000723")!,
            name: "Disabled Active",
            isEnabled: false,
            isActive: true
        )
        let enabledInactiveAgent = agent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000724")!,
            name: "Enabled Inactive",
            isEnabled: true,
            isActive: false
        )
        let orchestrator = RecordingAgentOrchestrator(selectedAgentIDs: [codingTerms.id])
        let factory = AgentRunRequestFactory(
            textSession: FakeInputCapturer(snapshot: snapshot),
            agentProfileStore: FakeAgentProfileLoader(
                profiles: [grammar, codingTerms, disabledActiveAgent, enabledInactiveAgent]
            ),
            memoryStore: FakeAgentMemoryLoader(memory: AgentMemoryStore.defaultMemory()),
            contextResolver: RecordingContextResolver(result: nil),
            orchestrator: orchestrator
        )

        let request = try factory.makeRequest()

        XCTAssertEqual(request.activeAgents, [codingTerms])
        XCTAssertEqual(orchestrator.candidateNames, [["Grammar Fixer", "Coding Terms"]])
        XCTAssertEqual(orchestrator.contexts.map(\.input), [snapshot])
    }

    func testMakeRequestThrowsWhenOrchestratorSelectsNoAgents() {
        let snapshot = textSnapshot(sourceBundleID: "com.tinyspeck.slackmacgap")
        let inputCapturer = FakeInputCapturer(snapshot: snapshot)
        let memoryLoader = FakeAgentMemoryLoader(memory: AgentMemoryStore.defaultMemory())
        let factory = AgentRunRequestFactory(
            textSession: inputCapturer,
            agentProfileStore: FakeAgentProfileLoader(
                profiles: [agent(isEnabled: true, isActive: true)]
            ),
            memoryStore: memoryLoader,
            contextResolver: RecordingContextResolver(result: nil),
            orchestrator: RecordingAgentOrchestrator(selectedAgentIDs: [])
        )

        XCTAssertThrowsError(try factory.makeRequest()) { error in
            XCTAssertEqual(error as? AgentRunRequestFactoryError, .noSelectedAgents)
        }
        XCTAssertEqual(inputCapturer.callCount, 1)
        XCTAssertEqual(memoryLoader.callCount, 1)
    }

    func testMakeRequestThrowsWhenNoActiveEnabledAgents() {
        let inputCapturer = FakeInputCapturer(snapshot: textSnapshot(sourceBundleID: "com.example.App"))
        let memoryLoader = FakeAgentMemoryLoader(memory: AgentMemoryStore.defaultMemory())
        let contextResolver = RecordingContextResolver(result: conversationContext(messageCount: 1))
        let factory = AgentRunRequestFactory(
            textSession: inputCapturer,
            agentProfileStore: FakeAgentProfileLoader(
                profiles: [
                    agent(name: "Inactive", isEnabled: true, isActive: false),
                    agent(name: "Disabled", isEnabled: false, isActive: true)
                ]
            ),
            memoryStore: memoryLoader,
            contextResolver: contextResolver
        )

        XCTAssertThrowsError(try factory.makeRequest()) { error in
            XCTAssertEqual(error as? AgentRunRequestFactoryError, .noActiveEnabledAgents)
        }
        XCTAssertEqual(inputCapturer.callCount, 0)
        XCTAssertEqual(memoryLoader.callCount, 0)
        XCTAssertEqual(contextResolver.requests, [])
    }

    func testMakePreparedRequestThrowsWhenFocusedInputIsEmpty() {
        let inputCapturer = FakeInputCapturer(
            snapshot: textSnapshot(sourceBundleID: "com.example.App", text: " \n\t ")
        )
        let memoryLoader = FakeAgentMemoryLoader(memory: AgentMemoryStore.defaultMemory())
        let contextResolver = RecordingContextResolver(result: conversationContext(messageCount: 1))
        let orchestrator = RecordingAgentOrchestrator(selectedAgentIDs: [
            UUID(uuidString: "00000000-0000-0000-0000-000000000700")!
        ])
        let factory = AgentRunRequestFactory(
            textSession: inputCapturer,
            agentProfileStore: FakeAgentProfileLoader(
                profiles: [agent(isEnabled: true, isActive: true)]
            ),
            memoryStore: memoryLoader,
            contextResolver: contextResolver,
            orchestrator: orchestrator
        )

        XCTAssertThrowsError(try factory.makePreparedRequest()) { error in
            XCTAssertEqual(error as? AgentRunRequestFactoryError, .emptyInput)
        }
        XCTAssertEqual(inputCapturer.callCount, 1)
        XCTAssertEqual(memoryLoader.callCount, 0)
        XCTAssertEqual(contextResolver.requests, [])
        XCTAssertEqual(orchestrator.candidateNames, [])
    }

    func testPrivacyOptionsClampNegativeVisibleMessageLimit() {
        let options = AgentRunPrivacyOptions(
            includeConversationContext: true,
            maxVisibleMessages: -3,
            allowClipboardFallback: true,
            redactionRules: ["secret"]
        )

        XCTAssertEqual(options.maxVisibleMessages, 0)
        XCTAssertEqual(
            options.privacyPolicy,
            PrivacyPolicy(
                includeConversationContext: true,
                maxVisibleMessages: 0,
                allowClipboardFallback: true,
                redactionRules: ["secret"]
            )
        )
    }

    private func textSnapshot(
        sourceBundleID: String,
        text: String = "Can we make deploy after review?"
    ) -> TextSnapshot {
        TextSnapshot(
            text: text,
            selectedRange: text.isEmpty ? nil : 0..<min(6, text.count),
            sourceBundleID: sourceBundleID,
            sourceElementRole: "AXTextArea",
            contentHash: "sha256:test"
        )
    }

    private func conversationContext(messageCount: Int) -> ConversationContext {
        ConversationContext(
            appBundleID: "com.tinyspeck.slackmacgap",
            conversationTitle: "#release",
            visibleMessages: (0..<messageCount).map { index in
                ConversationMessage(
                    id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 800 + index))!,
                    author: index.isMultiple(of: 2) ? "Sam" : "Me",
                    timestamp: Date(timeIntervalSince1970: 1_780_000_000 + TimeInterval(index)),
                    text: "Visible message \(index)"
                )
            }
        )
    }

    private func agent(
        id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000700")!,
        name: String = "Grammar Fixer",
        isEnabled: Bool,
        isActive: Bool
    ) -> AgentProfile {
        AgentProfile(
            id: id,
            name: name,
            description: "\(name) description",
            isEnabled: isEnabled,
            isActive: isActive,
            providerID: AgentProfileStore.defaultProviderID,
            modelOverride: nil,
            systemPrompt: "You are a careful editor.",
            instruction: "Improve the text while preserving intent.",
            tone: .neutral,
            aggressiveness: .conservative,
            scope: .currentInput,
            terminologyRules: [],
            enabledBundleIDs: [],
            disabledBundleIDs: [],
            applyMode: .askEveryTime
        )
    }
}

private final class FakeAXNode: NSObject {}

private final class FakeInputCapturer: AgentRunInputCapturing {
    private let captureResult: Result<FocusedTextCapture, Error>
    private(set) var callCount = 0

    init(
        snapshot: TextSnapshot,
        focusedElement: AXFocusedElement? = nil,
        geometry: AXTextGeometry = AXTextGeometry(selectionBounds: nil, caretBounds: nil)
    ) {
        let resolvedFocusedElement = focusedElement ?? AXFocusedElement(
            element: AXElement(FakeAXNode()),
            role: snapshot.sourceElementRole,
            subrole: nil,
            value: snapshot.text,
            selectedRange: nil
        )
        self.captureResult = .success(
            FocusedTextCapture(
                focusedElement: resolvedFocusedElement,
                snapshot: snapshot,
                geometry: geometry
            )
        )
    }

    init(error: Error) {
        self.captureResult = .failure(error)
    }

    func capture() throws -> FocusedTextCapture {
        callCount += 1
        return try captureResult.get()
    }
}

private final class FakeAgentProfileLoader: AgentProfileLoading {
    let profiles: [AgentProfile]
    private(set) var callCount = 0

    init(profiles: [AgentProfile]) {
        self.profiles = profiles
    }

    func loadProfiles() throws -> [AgentProfile] {
        callCount += 1
        return profiles
    }
}

private final class FakeAgentMemoryLoader: AgentMemoryLoading {
    private let memory: AgentMemory
    private(set) var callCount = 0

    init(memory: AgentMemory) {
        self.memory = memory
    }

    func loadMemory() throws -> AgentMemory {
        callCount += 1
        return memory
    }
}

private final class RecordingContextResolver: AgentRunContextResolving {
    private let result: ConversationContext?
    private(set) var requests: [AppContextExtractionRequest] = []

    init(result: ConversationContext?) {
        self.result = result
    }

    func context(for request: AppContextExtractionRequest) -> ConversationContext? {
        requests.append(request)
        return result
    }
}

private final class RecordingAgentOrchestrator: AgentOrchestrating {
    private let selectedAgentIDs: [AgentProfile.ID]
    private(set) var candidateNames: [[String]] = []
    private(set) var contexts: [AgentOrchestrationContext] = []

    init(selectedAgentIDs: [AgentProfile.ID]) {
        self.selectedAgentIDs = selectedAgentIDs
    }

    func selectAgents(
        from candidates: [AgentProfile],
        context: AgentOrchestrationContext
    ) -> [AgentProfile] {
        candidateNames.append(candidates.map(\.name))
        contexts.append(context)

        return selectedAgentIDs.compactMap { id in
            candidates.first { $0.id == id }
        }
    }
}
