import Foundation
import XCTest
@testable import PersonaWritingAgent

final class SuggestionApplyCoordinatorTests: XCTestCase {
    func testAppliesSingleEditUsingAgentApplyModeFocusedElementAndPrivacyPolicy() throws {
        let agentID = UUID(uuidString: "00000000-0000-0000-0000-000000001101")!
        let focusedElement = AXFocusedElement(
            element: AXElement(FakeAXNode()),
            role: "AXTextArea",
            subrole: nil,
            value: "I will make deploy.",
            selectedRange: AXTextRange(location: 7, length: 11)
        )
        let edit = correctionEdit(range: 7..<18, original: "make deploy", replacement: "deploy it")
        let snapshot = textSnapshot("I will make deploy.")
        let request = runRequest(
            input: snapshot,
            agents: [agent(id: agentID, applyMode: .axSelectedText)],
            privacyPolicy: PrivacyPolicy(
                includeConversationContext: false,
                maxVisibleMessages: 0,
                allowClipboardFallback: true,
                redactionRules: []
            )
        )
        let expectedPlan = try EditApplicationPlanner().plan(for: edit, in: snapshot)
        let applier = RecordingEditApplier(result: .success(expectedPlan))
        let factory = RecordingEditApplierFactory(applier: applier)
        let coordinator = SuggestionApplyCoordinator(applierFactory: factory)

        let outcome = coordinator.apply(
            suggestion(id: agentID, edits: [edit]),
            preparedRequest: AgentRunPreparedRequest(
                request: request,
                geometry: AXTextGeometry(),
                focusedElement: focusedElement
            )
        )

        XCTAssertTrue(outcome.isSuccess)
        XCTAssertEqual(outcome.applyMode, .axSelectedText)
        XCTAssertEqual(outcome.appliedPlans, [expectedPlan])
        XCTAssertEqual(factory.requests.count, 1)
        XCTAssertEqual(factory.requests[0].applyMode, .axSelectedText)
        XCTAssertEqual(factory.requests[0].focusedElement, focusedElement)
        XCTAssertEqual(factory.requests[0].privacyPolicy.allowClipboardFallback, true)
        XCTAssertEqual(applier.calls, [RecordingEditApplier.Call(edit: edit, snapshot: snapshot)])
    }

    func testAskEveryTimeFallsBackAcrossSafeApplyModes() throws {
        let agentID = UUID(uuidString: "00000000-0000-0000-0000-000000001102")!
        let edit = correctionEdit(range: 0..<4, original: "Make", replacement: "Ship")
        let snapshot = textSnapshot("Make it")
        let expectedPlan = try EditApplicationPlanner().plan(for: edit, in: snapshot)
        let factory = RecordingEditApplierFactory(
            appliers: [
                RecordingEditApplier(result: .failure(TestApplyError.failed)),
                RecordingEditApplier(result: .success(expectedPlan))
            ]
        )
        let coordinator = SuggestionApplyCoordinator(applierFactory: factory)

        let outcome = coordinator.apply(
            suggestion(
                id: agentID,
                edits: [edit]
            ),
            preparedRequest: AgentRunPreparedRequest(
                request: runRequest(
                    input: snapshot,
                    agents: [agent(id: agentID, applyMode: .askEveryTime)]
                ),
                geometry: AXTextGeometry(),
                focusedElement: focusedElement()
            )
        )

        XCTAssertTrue(outcome.isSuccess)
        XCTAssertEqual(outcome.applyMode, .axValue)
        XCTAssertEqual(outcome.appliedPlans, [expectedPlan])
        XCTAssertEqual(factory.requests.map(\.applyMode), [.axSelectedText, .axValue])
    }

    func testAskEveryTimeUsesClipboardFallbackBeforeAXValueWhenPrivacyAllows() throws {
        let agentID = UUID(uuidString: "00000000-0000-0000-0000-000000001105")!
        let edit = correctionEdit(range: 0..<4, original: "Make", replacement: "Ship")
        let snapshot = textSnapshot("Make it")
        let expectedPlan = try EditApplicationPlanner().plan(for: edit, in: snapshot)
        let factory = RecordingEditApplierFactory(
            appliers: [
                RecordingEditApplier(result: .failure(TestApplyError.failed)),
                RecordingEditApplier(result: .success(expectedPlan))
            ]
        )
        let coordinator = SuggestionApplyCoordinator(applierFactory: factory)

        let outcome = coordinator.apply(
            suggestion(id: agentID, edits: [edit]),
            preparedRequest: AgentRunPreparedRequest(
                request: runRequest(
                    input: snapshot,
                    agents: [agent(id: agentID, applyMode: .askEveryTime)],
                    privacyPolicy: PrivacyPolicy(
                        includeConversationContext: false,
                        maxVisibleMessages: 0,
                        allowClipboardFallback: true,
                        redactionRules: []
                    )
                ),
                geometry: AXTextGeometry(),
                focusedElement: focusedElement()
            )
        )

        XCTAssertTrue(outcome.isSuccess)
        XCTAssertEqual(outcome.applyMode, .clipboardPaste)
        XCTAssertEqual(outcome.appliedPlans, [expectedPlan])
        XCTAssertEqual(factory.requests.map(\.applyMode), [.axSelectedText, .clipboardPaste])
    }

    func testAppliesMultipleGranularEditsFromEndToStart() throws {
        let agentID = UUID(uuidString: "00000000-0000-0000-0000-000000001103")!
        let snapshot = textSnapshot("Make it")
        let firstAppliedEdit = correctionEdit(range: 5..<7, original: "it", replacement: "this")
        let secondAppliedEdit = correctionEdit(range: 0..<4, original: "Make", replacement: "Ship")
        let firstPlan = try EditApplicationPlanner().plan(for: firstAppliedEdit, in: snapshot)
        let secondSnapshot = textSnapshot(firstPlan.resultingText)
        let secondPlan = try EditApplicationPlanner().plan(for: secondAppliedEdit, in: secondSnapshot)
        let applier = RecordingEditApplier(results: [.success(firstPlan), .success(secondPlan)])
        let factory = RecordingEditApplierFactory(applier: applier)
        let coordinator = SuggestionApplyCoordinator(applierFactory: factory)

        let outcome = coordinator.apply(
            suggestion(
                id: agentID,
                edits: [
                    secondAppliedEdit,
                    firstAppliedEdit
                ],
                fullRewrite: "Ship it"
            ),
            preparedRequest: AgentRunPreparedRequest(
                request: runRequest(
                    input: snapshot,
                    agents: [agent(id: agentID, applyMode: .axValue)]
                ),
                geometry: AXTextGeometry(),
                focusedElement: focusedElement()
            )
        )

        XCTAssertTrue(outcome.isSuccess)
        XCTAssertEqual(outcome.appliedPlans, [firstPlan, secondPlan])
        XCTAssertEqual(
            applier.calls,
            [
                RecordingEditApplier.Call(edit: firstAppliedEdit, snapshot: snapshot),
                RecordingEditApplier.Call(edit: secondAppliedEdit, snapshot: secondSnapshot)
            ]
        )
    }

    func testMapsApplierErrorsToSafeFailure() {
        let agentID = UUID(uuidString: "00000000-0000-0000-0000-000000001104")!
        let applier = RecordingEditApplier(result: .failure(TestApplyError.failed))
        let factory = RecordingEditApplierFactory(applier: applier)
        let coordinator = SuggestionApplyCoordinator(applierFactory: factory)

        let outcome = coordinator.apply(
            suggestion(
                id: agentID,
                edits: [correctionEdit(range: 0..<4, original: "Make", replacement: "Ship")]
            ),
            preparedRequest: AgentRunPreparedRequest(
                request: runRequest(agents: [agent(id: agentID, applyMode: .clipboardPaste)]),
                geometry: AXTextGeometry(),
                focusedElement: focusedElement()
            )
        )

        XCTAssertEqual(outcome.failure, .applyFailed)
        XCTAssertEqual(outcome.appliedPlans, [])
        XCTAssertEqual(factory.requests.map(\.applyMode), [.clipboardPaste])
    }

    func testDefaultFactoryClipboardPasteHonorsPrivacyOptOutBeforeClipboardSideEffects() {
        let focusedElement = focusedElement()
        let factory = DefaultEditApplierFactory()
        let applier = factory.makeApplier(
            applyMode: .clipboardPaste,
            focusedElement: focusedElement,
            privacyPolicy: PrivacyPolicy(
                includeConversationContext: false,
                maxVisibleMessages: 0,
                allowClipboardFallback: false,
                redactionRules: []
            )
        )

        XCTAssertThrowsError(
            try applier?.apply(
                correctionEdit(range: 0..<4, original: "Make", replacement: "Ship"),
                to: textSnapshot("Make it")
            )
        ) { error in
            XCTAssertEqual(error as? EditApplicationPlanningError, .clipboardFallbackNotAllowed)
        }
    }

    private func runRequest(
        input: TextSnapshot? = nil,
        agents: [AgentProfile],
        privacyPolicy: PrivacyPolicy = PrivacyPolicy(
            includeConversationContext: false,
            maxVisibleMessages: 0,
            allowClipboardFallback: false,
            redactionRules: []
        )
    ) -> AgentRunRequest {
        AgentRunRequest(
            input: input ?? textSnapshot("Make it"),
            activeAgents: agents,
            appContext: nil,
            memory: AgentMemory(terminologyRules: [], tonePreferences: [], writingRules: []),
            privacyPolicy: privacyPolicy
        )
    }

    private func textSnapshot(_ text: String) -> TextSnapshot {
        TextSnapshot(
            text: text,
            selectedRange: nil,
            sourceBundleID: "com.example.Editor",
            sourceElementRole: "AXTextArea",
            contentHash: "sha256:test"
        )
    }

    private func focusedElement() -> AXFocusedElement {
        AXFocusedElement(
            element: AXElement(FakeAXNode()),
            role: "AXTextArea",
            subrole: nil,
            value: "Make it",
            selectedRange: AXTextRange(location: 0, length: 4)
        )
    }

    private func suggestion(
        id: UUID,
        edits: [CorrectionEdit],
        fullRewrite: String? = nil
    ) -> AgentSuggestion {
        AgentSuggestion(
            id: id,
            agentName: "Test Agent",
            result: CorrectionResult(summary: "Apply test", edits: edits, fullRewrite: fullRewrite)
        )
    }

    private func correctionEdit(
        range: Range<Int>,
        original: String,
        replacement: String
    ) -> CorrectionEdit {
        CorrectionEdit(
            rangeStart: range.lowerBound,
            rangeEnd: range.upperBound,
            original: original,
            replacement: replacement,
            reason: "test"
        )
    }

    private func agent(id: UUID, applyMode: ApplyMode) -> AgentProfile {
        AgentProfile(
            id: id,
            name: "Test Agent",
            description: "Test agent",
            isEnabled: true,
            isActive: true,
            providerID: AgentProfileStore.defaultProviderID,
            modelOverride: nil,
            systemPrompt: "Edit carefully.",
            instruction: "Improve text.",
            tone: .neutral,
            aggressiveness: .conservative,
            scope: .currentInput,
            terminologyRules: [],
            enabledBundleIDs: [],
            disabledBundleIDs: [],
            applyMode: applyMode
        )
    }
}

private final class FakeAXNode: NSObject {}

private enum TestApplyError: Error {
    case failed
}

private final class RecordingEditApplier: EditApplier {
    struct Call: Equatable {
        var edit: CorrectionEdit
        var snapshot: TextSnapshot
    }

    private var results: [Result<EditApplicationPlan, Error>]
    private(set) var calls: [Call] = []

    init(result: Result<EditApplicationPlan, Error>) {
        self.results = [result]
    }

    init(results: [Result<EditApplicationPlan, Error>]) {
        self.results = results
    }

    func apply(_ edit: CorrectionEdit, to snapshot: TextSnapshot) throws -> EditApplicationPlan {
        calls.append(Call(edit: edit, snapshot: snapshot))
        guard results.isEmpty == false else {
            throw TestApplyError.failed
        }

        return try results.removeFirst().get()
    }
}

private final class RecordingEditApplierFactory: EditApplierMaking {
    struct Request: Equatable {
        var applyMode: ApplyMode
        var focusedElement: AXFocusedElement
        var privacyPolicy: PrivacyPolicy
    }

    private let appliers: [any EditApplier]
    private(set) var requests: [Request] = []

    init(applier: any EditApplier) {
        self.appliers = [applier]
    }

    init(appliers: [any EditApplier]) {
        self.appliers = appliers
    }

    func makeApplier(
        applyMode: ApplyMode,
        focusedElement: AXFocusedElement,
        privacyPolicy: PrivacyPolicy
    ) -> (any EditApplier)? {
        requests.append(
            Request(
                applyMode: applyMode,
                focusedElement: focusedElement,
                privacyPolicy: privacyPolicy
            )
        )
        return appliers[min(requests.count - 1, appliers.count - 1)]
    }
}
