import CoreGraphics
import Foundation
import XCTest
@testable import Overlaygent

final class RunActiveAgentsCoordinatorTests: XCTestCase {
    func testActiveRunInvokesFactoryEngineAndOverlayWithSuccessfulResultsOnly() async {
        let request = runRequest(activeAgents: [
            agent(idSuffix: 1, name: "Natural English"),
            agent(idSuffix: 2, name: "Technical")
        ])
        let successfulResult = successResult(agentID: agentID(1), agentName: "Natural English")
        let failedResult = failureResult(agentID: agentID(2), agentName: "Technical")
        let factory = RecordingRunRequestFactory(result: .success(preparedRequest(request)))
        let engine = RecordingCorrectionEngine(result: .success([successfulResult, failedResult]))
        let overlay = RecordingSuggestionPresenter()
        let applyCoordinator = RecordingSuggestionApplyCoordinator()
        let anchor = OverlayAnchorGeometry(fallbackRect: CGRect(x: 40, y: 50, width: 10, height: 12))
        var logs: [String] = []
        let coordinator = RunActiveAgentsCoordinator(
            requestFactory: factory,
            correctionEngine: engine,
            overlayPresenter: overlay,
            suggestionApplyCoordinator: applyCoordinator,
            anchorProvider: { anchor },
            logger: { logs.append($0) }
        )

        let summary = await coordinator.runActiveAgents()

        XCTAssertEqual(factory.callCount, 1)
        XCTAssertEqual(factory.privacyOptions, [AgentRunPrivacyOptions()])
        XCTAssertEqual(engine.requests, [request])
        XCTAssertEqual(overlay.showCallCount, 2)
        XCTAssertEqual(overlay.presentedStatusTitles, ["Running agents"])
        XCTAssertEqual(overlay.presentedAnchor, anchor)
        XCTAssertEqual(overlay.presentedSuggestions, [
            AgentSuggestion(
                id: successfulResult.agentID,
                agentName: successfulResult.agentName,
                result: successfulResult.result!
            )
        ])
        XCTAssertEqual(
            summary,
            ActiveAgentRunSummary(
                requestedAgentCount: 2,
                totalResults: 2,
                successfulResults: 1,
                failedResults: 1,
                didShowOverlay: true,
                failureStage: nil
            )
        )
        XCTAssertTrue(logs.contains { $0.contains(agentID(2).uuidString) && $0.contains("missing") })
        XCTAssertFalse(logs.contains { $0.contains("Technical") })

        let didApply = overlay.onApply?(overlay.presentedSuggestions[0])

        XCTAssertEqual(didApply, true)
        XCTAssertEqual(applyCoordinator.appliedSuggestions, [overlay.presentedSuggestions[0]])
        XCTAssertTrue(logs.contains { $0.contains("Applied suggestion") })
        XCTAssertFalse(logs.contains { $0.contains("Natural English preview") })
        XCTAssertFalse(logs.contains { $0.contains(request.input.contentHash) })
    }

    func testActiveRunUsesPreparedRequestGeometryForOverlayAnchor() async {
        let request = runRequest(activeAgents: [
            agent(idSuffix: 1, name: "Natural English")
        ])
        let caretBounds = CGRect(x: 120, y: 320, width: 2, height: 18)
        let selectionBounds = CGRect(x: 40, y: 320, width: 82, height: 18)
        let inputFrame = CGRect(x: 36, y: 300, width: 460, height: 64)
        let fallbackAnchor = OverlayAnchorGeometry(fallbackRect: CGRect(x: 10, y: 20, width: 30, height: 40))
        let factory = RecordingRunRequestFactory(
            result: .success(
                preparedRequest(
                    request,
                    geometry: AXTextGeometry(
                        inputFrame: inputFrame,
                        selectionBounds: selectionBounds,
                        caretBounds: caretBounds
                    )
                )
            )
        )
        let engine = RecordingCorrectionEngine(result: .success([
            successResult(agentID: agentID(1), agentName: "Natural English")
        ]))
        let overlay = RecordingSuggestionPresenter()
        let coordinator = RunActiveAgentsCoordinator(
            requestFactory: factory,
            correctionEngine: engine,
            overlayPresenter: overlay,
            suggestionApplyCoordinator: RecordingSuggestionApplyCoordinator(),
            anchorProvider: { fallbackAnchor }
        )

        let summary = await coordinator.runActiveAgents()

        XCTAssertTrue(summary.didShowOverlay)
        XCTAssertEqual(overlay.showCallCount, 2)
        XCTAssertEqual(overlay.presentedStatusTitles, ["Running agents"])
        XCTAssertEqual(
            overlay.presentedAnchor,
            OverlayAnchorGeometry(
                caretRect: caretBounds,
                inputRect: inputFrame,
                fallbackRect: fallbackAnchor.fallbackRect
            )
        )
    }

    func testActiveRunDoesNotPromoteSelectionBoundsToInputFrame() async {
        let request = runRequest(activeAgents: [
            agent(idSuffix: 1, name: "Natural English")
        ])
        let caretBounds = CGRect(x: 120, y: 320, width: 2, height: 18)
        let selectionBounds = CGRect(x: 40, y: 320, width: 82, height: 18)
        let fallbackInputFrame = CGRect(x: 20, y: 280, width: 520, height: 56)
        let fallbackAnchor = OverlayAnchorGeometry(
            inputRect: fallbackInputFrame,
            fallbackRect: CGRect(x: 10, y: 20, width: 30, height: 40)
        )
        let factory = RecordingRunRequestFactory(
            result: .success(
                preparedRequest(
                    request,
                    geometry: AXTextGeometry(
                        inputFrame: nil,
                        selectionBounds: selectionBounds,
                        caretBounds: caretBounds
                    )
                )
            )
        )
        let engine = RecordingCorrectionEngine(result: .success([
            successResult(agentID: agentID(1), agentName: "Natural English")
        ]))
        let overlay = RecordingSuggestionPresenter()
        let coordinator = RunActiveAgentsCoordinator(
            requestFactory: factory,
            correctionEngine: engine,
            overlayPresenter: overlay,
            suggestionApplyCoordinator: RecordingSuggestionApplyCoordinator(),
            anchorProvider: { fallbackAnchor }
        )

        let summary = await coordinator.runActiveAgents()

        XCTAssertTrue(summary.didShowOverlay)
        XCTAssertEqual(overlay.showCallCount, 2)
        XCTAssertEqual(overlay.presentedStatusTitles, ["Running agents"])
        XCTAssertEqual(
            overlay.presentedAnchor,
            OverlayAnchorGeometry(
                caretRect: caretBounds,
                inputRect: fallbackInputFrame,
                fallbackRect: fallbackAnchor.fallbackRect
            )
        )
    }

    func testNoSuccessfulResultsShowsSafeStatusOverlay() async {
        let request = runRequest(activeAgents: [
            agent(idSuffix: 3, name: "Technical")
        ])
        let factory = RecordingRunRequestFactory(result: .success(preparedRequest(request)))
        let engine = RecordingCorrectionEngine(result: .success([
            failureResult(agentID: agentID(3), agentName: "Technical")
        ]))
        let overlay = RecordingSuggestionPresenter()
        let applyCoordinator = RecordingSuggestionApplyCoordinator()
        var logs: [String] = []
        let coordinator = RunActiveAgentsCoordinator(
            requestFactory: factory,
            correctionEngine: engine,
            overlayPresenter: overlay,
            suggestionApplyCoordinator: applyCoordinator,
            logger: { logs.append($0) }
        )

        let summary = await coordinator.runActiveAgents()

        XCTAssertEqual(factory.callCount, 1)
        XCTAssertEqual(engine.requests, [request])
        XCTAssertEqual(overlay.showCallCount, 2)
        XCTAssertEqual(overlay.presentedStatusTitles, ["Running agents", "No suggestions shown"])
        XCTAssertEqual(overlay.presentedStatusTitle, "No suggestions shown")
        XCTAssertTrue(overlay.presentedStatusDetail?.contains("missing") == true)
        XCTAssertEqual(applyCoordinator.appliedSuggestions, [])
        XCTAssertEqual(
            summary,
            ActiveAgentRunSummary(
                requestedAgentCount: 1,
                totalResults: 1,
                successfulResults: 0,
                failedResults: 1,
                didShowOverlay: true,
                failureStage: nil
            )
        )
        XCTAssertTrue(logs.contains { $0.contains("no successful suggestions") })
    }

    func testRequestFailureIsHandledSafely() async {
        let factory = RecordingRunRequestFactory(result: .failure(CoordinatorTestError.requestFailed))
        let engine = RecordingCorrectionEngine(result: .success([]))
        let overlay = RecordingSuggestionPresenter()
        var logs: [String] = []
        let coordinator = RunActiveAgentsCoordinator(
            requestFactory: factory,
            correctionEngine: engine,
            overlayPresenter: overlay,
            suggestionApplyCoordinator: RecordingSuggestionApplyCoordinator(),
            logger: { logs.append($0) }
        )

        let summary = await coordinator.runActiveAgents()

        XCTAssertEqual(factory.callCount, 1)
        XCTAssertEqual(engine.requests, [])
        XCTAssertEqual(overlay.showCallCount, 1)
        XCTAssertEqual(overlay.presentedStatusTitle, "Could not read the current input")
        XCTAssertEqual(
            summary,
            ActiveAgentRunSummary(
                requestedAgentCount: 0,
                totalResults: 0,
                successfulResults: 0,
                failedResults: 0,
                didShowOverlay: true,
                failureStage: .request
            )
        )
        XCTAssertTrue(logs.contains { $0.contains("request failed") })
    }

    func testRequestFailureDoesNotLogRawPrivacyGuardValues() async {
        let factory = RecordingRunRequestFactory(
            result: .failure(
                PrivacyGuardError.secureSourceMetadata(
                    field: "input.sourceBundleID",
                    value: "com.example.SecretVault"
                )
            )
        )
        let engine = RecordingCorrectionEngine(result: .success([]))
        let overlay = RecordingSuggestionPresenter()
        var logs: [String] = []
        let coordinator = RunActiveAgentsCoordinator(
            requestFactory: factory,
            correctionEngine: engine,
            overlayPresenter: overlay,
            suggestionApplyCoordinator: RecordingSuggestionApplyCoordinator(),
            logger: { logs.append($0) }
        )

        let summary = await coordinator.runActiveAgents()

        XCTAssertEqual(summary.failureStage, .request)
        XCTAssertEqual(logs.count, 1)
        XCTAssertTrue(logs[0].contains("input.sourceBundleID"))
        XCTAssertFalse(logs[0].contains("SecretVault"))
        XCTAssertFalse(logs[0].contains("com.example"))
    }

    func testEngineFailureIsHandledSafely() async {
        let request = runRequest(activeAgents: [
            agent(idSuffix: 4, name: "Natural English")
        ])
        let factory = RecordingRunRequestFactory(result: .success(preparedRequest(request)))
        let engine = RecordingCorrectionEngine(result: .failure(CoordinatorTestError.engineFailed))
        let overlay = RecordingSuggestionPresenter()
        var logs: [String] = []
        let coordinator = RunActiveAgentsCoordinator(
            requestFactory: factory,
            correctionEngine: engine,
            overlayPresenter: overlay,
            suggestionApplyCoordinator: RecordingSuggestionApplyCoordinator(),
            logger: { logs.append($0) }
        )

        let summary = await coordinator.runActiveAgents()

        XCTAssertEqual(factory.callCount, 1)
        XCTAssertEqual(engine.requests, [request])
        XCTAssertEqual(overlay.showCallCount, 2)
        XCTAssertEqual(overlay.presentedStatusTitles, ["Running agents", "Agent run failed"])
        XCTAssertEqual(overlay.presentedStatusTitle, "Agent run failed")
        XCTAssertEqual(
            summary,
            ActiveAgentRunSummary(
                requestedAgentCount: 1,
                totalResults: 0,
                successfulResults: 0,
                failedResults: 0,
                didShowOverlay: true,
                failureStage: .engine
            )
        )
        XCTAssertTrue(logs.contains { $0.contains("engine failed") })
    }

    private func runRequest(activeAgents: [AgentProfile]) -> AgentRunRequest {
        AgentRunRequest(
            input: TextSnapshot(
                text: "hello there",
                selectedRange: 0..<5,
                sourceBundleID: "com.example.Editor",
                sourceElementRole: "AXTextArea",
                contentHash: "sha256:coordinator"
            ),
            activeAgents: activeAgents,
            appContext: nil,
            memory: AgentMemory(terminologyRules: [], tonePreferences: [], writingRules: []),
            privacyPolicy: PrivacyPolicy(
                includeConversationContext: false,
                maxVisibleMessages: 0,
                allowClipboardFallback: false,
                redactionRules: []
            )
        )
    }

    private func preparedRequest(
        _ request: AgentRunRequest,
        geometry: AXTextGeometry = AXTextGeometry(selectionBounds: nil, caretBounds: nil)
    ) -> AgentRunPreparedRequest {
        AgentRunPreparedRequest(request: request, geometry: geometry)
    }

    private func successResult(agentID: UUID, agentName: String) -> AgentCorrectionResult {
        AgentCorrectionResult(
            agentID: agentID,
            agentName: agentName,
            providerID: providerID,
            result: CorrectionResult(
                summary: "Improved greeting.",
                edits: [
                    CorrectionEdit(
                        rangeStart: 0,
                        rangeEnd: 5,
                        original: "hello",
                        replacement: "Hello",
                        reason: "Capitalization"
                    )
                ],
                fullRewrite: "Hello there"
            ),
            rawResponse: #"{"fullRewrite":"Hello there"}"#,
            failure: nil
        )
    }

    private func failureResult(agentID: UUID, agentName: String) -> AgentCorrectionResult {
        AgentCorrectionResult(
            agentID: agentID,
            agentName: agentName,
            providerID: providerID,
            result: nil,
            rawResponse: nil,
            failure: .missingProvider(providerID: providerID)
        )
    }

    private func agent(idSuffix: Int, name: String) -> AgentProfile {
        AgentProfile(
            id: agentID(idSuffix),
            name: name,
            description: "\(name) description",
            isEnabled: true,
            isActive: true,
            providerID: providerID,
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

    private func agentID(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 700 + suffix))!
    }

    private var providerID: UUID {
        UUID(uuidString: "00000000-0000-0000-0000-000000000799")!
    }
}

private enum CoordinatorTestError: Error, CustomStringConvertible {
    case requestFailed
    case engineFailed

    var description: String {
        switch self {
        case .requestFailed:
            return "request failed"
        case .engineFailed:
            return "engine failed"
        }
    }
}

private final class RecordingRunRequestFactory: ActiveAgentRunRequestMaking {
    private let result: Result<AgentRunPreparedRequest, Error>
    private(set) var callCount = 0
    private(set) var privacyOptions: [AgentRunPrivacyOptions] = []

    init(result: Result<AgentRunPreparedRequest, Error>) {
        self.result = result
    }

    func makePreparedRequest(
        privacyOptions: AgentRunPrivacyOptions
    ) throws -> AgentRunPreparedRequest {
        callCount += 1
        self.privacyOptions.append(privacyOptions)
        return try result.get()
    }
}

private final class RecordingCorrectionEngine: ActiveAgentCorrectionRunning {
    private let result: Result<[AgentCorrectionResult], Error>
    private(set) var requests: [AgentRunRequest] = []

    init(result: Result<[AgentCorrectionResult], Error>) {
        self.result = result
    }

    func run(_ request: AgentRunRequest) async throws -> [AgentCorrectionResult] {
        requests.append(request)
        return try result.get()
    }
}

private final class RecordingSuggestionPresenter: ActiveAgentSuggestionPresenting {
    private(set) var showCallCount = 0
    private(set) var presentedAnchor: OverlayAnchorGeometry?
    private(set) var presentedSuggestions: [AgentSuggestion] = []
    private(set) var presentedStatusTitle: String?
    private(set) var presentedStatusDetail: String?
    private(set) var presentedStatusTitles: [String] = []
    private(set) var onApply: ((AgentSuggestion) -> Bool)?
    private(set) var onDismiss: ((AgentSuggestion?) -> Void)?

    func showStatus(
        anchor: OverlayAnchorGeometry,
        title: String,
        detail: String
    ) -> OverlayPanelPlacement {
        showCallCount += 1
        presentedAnchor = anchor
        presentedStatusTitle = title
        presentedStatusDetail = detail
        presentedStatusTitles.append(title)

        return OverlayPanelPlacement(
            frame: CGRect(x: 0, y: 0, width: 552, height: 420),
            anchorSource: anchor.resolvedAnchor(in: OverlayPositioning.defaultVisibleFrame).source
        )
    }

    func showSuggestions(
        anchor: OverlayAnchorGeometry,
        suggestions: [AgentSuggestion],
        onApply: @escaping (AgentSuggestion) -> Bool,
        onDismiss: @escaping (AgentSuggestion?) -> Void
    ) -> OverlayPanelPlacement {
        showCallCount += 1
        presentedAnchor = anchor
        presentedSuggestions = suggestions
        self.onApply = onApply
        self.onDismiss = onDismiss

        return OverlayPanelPlacement(
            frame: CGRect(x: 0, y: 0, width: 552, height: 420),
            anchorSource: anchor.resolvedAnchor(in: OverlayPositioning.defaultVisibleFrame).source
        )
    }
}

private final class RecordingSuggestionApplyCoordinator: SuggestionApplyCoordinating {
    private(set) var appliedSuggestions: [AgentSuggestion] = []
    private(set) var preparedRequests: [AgentRunPreparedRequest] = []
    var failure: SuggestionApplyFailure?

    func apply(
        _ suggestion: AgentSuggestion,
        preparedRequest: AgentRunPreparedRequest
    ) -> SuggestionApplyOutcome {
        appliedSuggestions.append(suggestion)
        preparedRequests.append(preparedRequest)

        return SuggestionApplyOutcome(
            suggestionID: suggestion.id,
            agentID: suggestion.id,
            applyMode: .axSelectedText,
            appliedPlans: [],
            failure: failure
        )
    }
}
