import Foundation

protocol EditApplierMaking {
    func makeApplier(
        applyMode: ApplyMode,
        focusedElement: AXFocusedElement,
        privacyPolicy: PrivacyPolicy
    ) -> (any EditApplier)?
}

struct DefaultEditApplierFactory: EditApplierMaking {
    func makeApplier(
        applyMode: ApplyMode,
        focusedElement: AXFocusedElement,
        privacyPolicy: PrivacyPolicy
    ) -> (any EditApplier)? {
        switch applyMode {
        case .askEveryTime:
            return AXSelectedTextApplier(element: focusedElement.element)
        case .axSelectedText:
            return AXSelectedTextApplier(element: focusedElement.element)
        case .axValue:
            return AXValueApplier(element: focusedElement.element)
        case .clipboardPaste:
            return AXClipboardPasteApplier(
                element: focusedElement.element,
                isEnabled: privacyPolicy.allowClipboardFallback
            )
        }
    }
}

enum SuggestionApplyFailure: Equatable, CustomStringConvertible {
    case agentNotFound
    case focusedElementMissing
    case noEdits
    case unsupportedApplyMode
    case applyFailed

    var description: String {
        switch self {
        case .agentNotFound:
            return "No matching agent was found for the suggestion."
        case .focusedElementMissing:
            return "Focused input reference is no longer available."
        case .noEdits:
            return "Suggestion has no granular edits to apply."
        case .unsupportedApplyMode:
            return "Agent apply mode is not supported by the current input."
        case .applyFailed:
            return "Suggestion apply failed."
        }
    }
}

struct SuggestionApplyOutcome: Equatable {
    var suggestionID: UUID
    var agentID: UUID
    var applyMode: ApplyMode?
    var appliedPlans: [EditApplicationPlan]
    var failure: SuggestionApplyFailure?

    var isSuccess: Bool {
        failure == nil
    }
}

protocol SuggestionApplyCoordinating {
    func apply(
        _ suggestion: AgentSuggestion,
        preparedRequest: AgentRunPreparedRequest
    ) -> SuggestionApplyOutcome
}

struct SuggestionApplyCoordinator: SuggestionApplyCoordinating {
    private let applierFactory: any EditApplierMaking

    init(applierFactory: any EditApplierMaking = DefaultEditApplierFactory()) {
        self.applierFactory = applierFactory
    }

    func apply(
        _ suggestion: AgentSuggestion,
        preparedRequest: AgentRunPreparedRequest
    ) -> SuggestionApplyOutcome {
        guard let agent = preparedRequest.request.activeAgents.first(where: { $0.id == suggestion.id }) else {
            return failureOutcome(.agentNotFound, suggestion: suggestion, applyMode: nil)
        }

        guard let focusedElement = preparedRequest.focusedElement else {
            return failureOutcome(.focusedElementMissing, suggestion: suggestion, applyMode: agent.applyMode)
        }

        guard let edits = editsToApply(from: suggestion, input: preparedRequest.request.input) else {
            return failureOutcome(.noEdits, suggestion: suggestion, applyMode: agent.applyMode)
        }

        var didCreateApplier = false
        for applyMode in applyModes(for: agent.applyMode, privacyPolicy: preparedRequest.request.privacyPolicy) {
            guard let applier = applierFactory.makeApplier(
                applyMode: applyMode,
                focusedElement: focusedElement,
                privacyPolicy: preparedRequest.request.privacyPolicy
            ) else {
                continue
            }
            didCreateApplier = true

            do {
                let plans = try applier.apply(edits, to: preparedRequest.request.input)
                return SuggestionApplyOutcome(
                    suggestionID: suggestion.id,
                    agentID: suggestion.id,
                    applyMode: applyMode,
                    appliedPlans: plans,
                    failure: nil
                )
            } catch {
                continue
            }
        }

        return failureOutcome(
            didCreateApplier ? .applyFailed : .unsupportedApplyMode,
            suggestion: suggestion,
            applyMode: agent.applyMode
        )
    }

    private func editsToApply(
        from suggestion: AgentSuggestion,
        input: TextSnapshot
    ) -> [CorrectionEdit]? {
        let granularEdits = nonOverlappingGranularEdits(from: suggestion.edits)
        if granularEdits.isEmpty == false {
            return granularEdits
        }

        guard let fullRewrite = suggestion.fullRewrite?.trimmingCharacters(in: .whitespacesAndNewlines),
              fullRewrite.isEmpty == false,
              fullRewrite != input.text else {
            return nil
        }

        return [CorrectionEdit(
            rangeStart: 0,
            rangeEnd: input.text.count,
            original: input.text,
            replacement: fullRewrite,
            reason: "Apply full rewrite"
        )]
    }

    private func nonOverlappingGranularEdits(from edits: [CorrectionEdit]) -> [CorrectionEdit] {
        let sortedEdits = edits.sorted { lhs, rhs in
            if lhs.rangeStart == rhs.rangeStart {
                return lhs.rangeEnd > rhs.rangeEnd
            }

            return lhs.rangeStart > rhs.rangeStart
        }

        var lowerBoundOfPreviouslyAppliedEdit = Int.max
        var nonOverlappingEdits: [CorrectionEdit] = []
        for edit in sortedEdits {
            guard edit.rangeStart >= 0,
                  edit.rangeEnd >= edit.rangeStart,
                  edit.rangeEnd <= lowerBoundOfPreviouslyAppliedEdit else {
                return []
            }

            lowerBoundOfPreviouslyAppliedEdit = edit.rangeStart
            nonOverlappingEdits.append(edit)
        }

        return nonOverlappingEdits
    }

    private func applyModes(
        for applyMode: ApplyMode,
        privacyPolicy: PrivacyPolicy
    ) -> [ApplyMode] {
        guard applyMode == .askEveryTime else {
            return [applyMode]
        }

        var modes: [ApplyMode] = [.axSelectedText]
        if privacyPolicy.allowClipboardFallback {
            modes.append(.clipboardPaste)
        }
        modes.append(.axValue)
        return modes
    }

    private func failureOutcome(
        _ failure: SuggestionApplyFailure,
        suggestion: AgentSuggestion,
        applyMode: ApplyMode?
    ) -> SuggestionApplyOutcome {
        SuggestionApplyOutcome(
            suggestionID: suggestion.id,
            agentID: suggestion.id,
            applyMode: applyMode,
            appliedPlans: [],
            failure: failure
        )
    }
}
