import Foundation

protocol ActiveAgentRunRequestMaking {
    func makePreparedRequest(
        privacyOptions: AgentRunPrivacyOptions
    ) throws -> AgentRunPreparedRequest
}

extension AgentRunRequestFactory: ActiveAgentRunRequestMaking {}

protocol ActiveAgentCorrectionRunning {
    func run(_ request: AgentRunRequest) async throws -> [AgentCorrectionResult]
}

extension CorrectionEngine: ActiveAgentCorrectionRunning {}

protocol ActiveAgentSuggestionPresenting: AnyObject {
    @discardableResult
    func showStatus(
        anchor: OverlayAnchorGeometry,
        title: String,
        detail: String
    ) -> OverlayPanelPlacement

    @discardableResult
    func showSuggestions(
        anchor: OverlayAnchorGeometry,
        suggestions: [AgentSuggestion],
        onApply: @escaping (AgentSuggestion) -> Bool,
        onDismiss: @escaping (AgentSuggestion?) -> Void
    ) -> OverlayPanelPlacement
}

protocol RunActiveAgentsCoordinating: AnyObject {
    func runActiveAgents() async -> ActiveAgentRunSummary
}

enum ActiveAgentRunFailureStage: Equatable {
    case request
    case engine
    case cancelled
    case emptyInput
}

struct ActiveAgentRunSummary: Equatable {
    var requestedAgentCount: Int
    var totalResults: Int
    var successfulResults: Int
    var failedResults: Int
    var didShowOverlay: Bool
    var failureStage: ActiveAgentRunFailureStage?
}

final class RunActiveAgentsCoordinator: RunActiveAgentsCoordinating {
    typealias AnchorProvider = () -> OverlayAnchorGeometry
    typealias Logger = (String) -> Void

    private let requestFactory: any ActiveAgentRunRequestMaking
    private let correctionEngine: any ActiveAgentCorrectionRunning
    private let overlayPresenter: any ActiveAgentSuggestionPresenting
    private let suggestionApplyCoordinator: any SuggestionApplyCoordinating
    private let privacyOptions: AgentRunPrivacyOptions
    private let anchorProvider: AnchorProvider
    private let logger: Logger

    init(
        requestFactory: any ActiveAgentRunRequestMaking,
        correctionEngine: any ActiveAgentCorrectionRunning,
        overlayPresenter: any ActiveAgentSuggestionPresenting,
        suggestionApplyCoordinator: any SuggestionApplyCoordinating,
        privacyOptions: AgentRunPrivacyOptions = AgentRunPrivacyOptions(),
        anchorProvider: @escaping AnchorProvider = { OverlayAnchorGeometry() },
        logger: @escaping Logger = SafeLogger.default.log
    ) {
        self.requestFactory = requestFactory
        self.correctionEngine = correctionEngine
        self.overlayPresenter = overlayPresenter
        self.suggestionApplyCoordinator = suggestionApplyCoordinator
        self.privacyOptions = privacyOptions
        self.anchorProvider = anchorProvider
        self.logger = logger
    }

    func runActiveAgents() async -> ActiveAgentRunSummary {
        let preparedRequest: AgentRunPreparedRequest
        do {
            preparedRequest = try requestFactory.makePreparedRequest(
                privacyOptions: privacyOptions
            )
        } catch {
            if let factoryError = error as? AgentRunRequestFactoryError,
               factoryError == .emptyInput {
                logger("Agent run skipped because focused input is empty.")
                return ActiveAgentRunSummary(
                    requestedAgentCount: 0,
                    totalResults: 0,
                    successfulResults: 0,
                    failedResults: 0,
                    didShowOverlay: false,
                    failureStage: .emptyInput
                )
            }

            let detail = Self.describe(error)
            logger("Agent run request failed: \(detail)")
            await presentStatus(
                title: "Could not read the current input",
                detail: detail,
                anchor: anchorProvider()
            )
            return ActiveAgentRunSummary(
                requestedAgentCount: 0,
                totalResults: 0,
                successfulResults: 0,
                failedResults: 0,
                didShowOverlay: true,
                failureStage: .request
            )
        }

        let runAnchor = overlayAnchor(for: preparedRequest)
        do {
            await presentStatus(
                title: "Running agents",
                detail: Self.runningDetail(agentCount: preparedRequest.request.activeAgents.count),
                anchor: runAnchor
            )
            let results = try await correctionEngine.run(preparedRequest.request)
            return await presentSuccessfulResults(results, for: preparedRequest, anchor: runAnchor)
        } catch is CancellationError {
            logger("Agent run cancelled.")
            return ActiveAgentRunSummary(
                requestedAgentCount: preparedRequest.request.activeAgents.count,
                totalResults: 0,
                successfulResults: 0,
                failedResults: 0,
                didShowOverlay: false,
                failureStage: .cancelled
            )
        } catch {
            let detail = Self.describe(error)
            logger("Agent correction engine failed: \(detail)")
            await presentStatus(
                title: "Agent run failed",
                detail: detail,
                anchor: runAnchor
            )
            return ActiveAgentRunSummary(
                requestedAgentCount: preparedRequest.request.activeAgents.count,
                totalResults: 0,
                successfulResults: 0,
                failedResults: 0,
                didShowOverlay: true,
                failureStage: .engine
            )
        }
    }

    private func presentSuccessfulResults(
        _ results: [AgentCorrectionResult],
        for preparedRequest: AgentRunPreparedRequest,
        anchor: OverlayAnchorGeometry
    ) async -> ActiveAgentRunSummary {
        let request = preparedRequest.request
        let suggestions = Self.displayModels(from: results)
        let failedResults = results.count - suggestions.count

        logFailedResults(in: results)

        guard suggestions.isEmpty == false else {
            let detail = Self.noSuccessfulSuggestionDetail(results: results)
            logger("Agent run completed with no successful suggestions.")
            await presentStatus(
                title: "No suggestions shown",
                detail: detail,
                anchor: anchor
            )
            return ActiveAgentRunSummary(
                requestedAgentCount: request.activeAgents.count,
                totalResults: results.count,
                successfulResults: 0,
                failedResults: failedResults,
                didShowOverlay: true,
                failureStage: nil
            )
        }

        await MainActor.run {
            _ = overlayPresenter.showSuggestions(
                anchor: anchor,
                suggestions: suggestions,
                onApply: applyHandler(for: preparedRequest, failureAnchor: anchor),
                onDismiss: dismissHandler()
            )
        }

        return ActiveAgentRunSummary(
            requestedAgentCount: request.activeAgents.count,
            totalResults: results.count,
            successfulResults: suggestions.count,
            failedResults: failedResults,
            didShowOverlay: true,
            failureStage: nil
        )
    }

    private func overlayAnchor(for preparedRequest: AgentRunPreparedRequest) -> OverlayAnchorGeometry {
        let geometry = preparedRequest.geometry
        let fallbackAnchor = anchorProvider()

        return OverlayAnchorGeometry(
            caretRect: geometry.caretBounds ?? geometry.selectionBounds,
            inputRect: geometry.inputFrame ?? fallbackAnchor.inputRect,
            fallbackRect: fallbackAnchor.fallbackRect
        )
    }

    private func presentStatus(
        title: String,
        detail: String,
        anchor: OverlayAnchorGeometry
    ) async {
        await MainActor.run {
            _ = overlayPresenter.showStatus(
                anchor: anchor,
                title: title,
                detail: detail
            )
        }
    }

    private func logFailedResults(in results: [AgentCorrectionResult]) {
        let failures = results.compactMap { result -> String? in
            guard let failure = result.failure else {
                return nil
            }

            return "agent \(result.agentID.uuidString): \(failure.description)"
        }

        guard failures.isEmpty == false else {
            return
        }

        logger("Agent run completed with \(failures.count) failed result(s): \(failures.joined(separator: " | "))")
    }

    private func applyHandler(
        for preparedRequest: AgentRunPreparedRequest,
        failureAnchor: OverlayAnchorGeometry
    ) -> (AgentSuggestion) -> Bool {
        return { [logger, overlayPresenter, suggestionApplyCoordinator] suggestion in
            let outcome = suggestionApplyCoordinator.apply(suggestion, preparedRequest: preparedRequest)
            if let failure = outcome.failure {
                logger(
                    "Apply failed for suggestion \(outcome.suggestionID.uuidString): \(failure.description)"
                )
                _ = overlayPresenter.showStatus(
                    anchor: failureAnchor,
                    title: "Could not apply suggestion",
                    detail: failure.description
                )
                return false
            }

            logger(
                "Applied suggestion \(outcome.suggestionID.uuidString) using \(outcome.applyMode?.rawValue ?? "unknown") with \(outcome.appliedPlans.count) edit(s)."
            )
            return true
        }
    }

    private func dismissHandler() -> (AgentSuggestion?) -> Void {
        { [logger] suggestion in
            if let suggestion {
                logger("Dismissed suggestion \(suggestion.id.uuidString).")
            } else {
                logger("Dismissed suggestion overlay.")
            }
        }
    }

    static func displayModels(from results: [AgentCorrectionResult]) -> [AgentSuggestion] {
        results.compactMap { result in
            guard result.isSuccess,
                  let correctionResult = result.result
            else {
                return nil
            }

            return AgentSuggestion(
                id: result.agentID,
                agentName: result.agentName,
                result: correctionResult
            )
        }
    }

    private static func noSuccessfulSuggestionDetail(results: [AgentCorrectionResult]) -> String {
        guard let firstFailure = results.compactMap(\.failure).first else {
            return "The agents returned no usable corrections."
        }

        return SafeLogger.redacted(firstFailure.description)
    }

    private static func runningDetail(agentCount: Int) -> String {
        if agentCount == 1 {
            return "Asking 1 active agent to review the current input."
        }

        return "Asking \(agentCount) active agents to review the current input."
    }

    private static func describe(_ error: Error) -> String {
        if let privacyError = error as? PrivacyGuardError {
            return privacyError.safeDescription
        }

        return SafeLogger.redacted(String(describing: error))
    }
}
