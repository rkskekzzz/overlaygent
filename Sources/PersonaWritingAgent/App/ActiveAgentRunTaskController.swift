import Foundation

protocol ActiveAgentRunTaskControlling: AnyObject {
    @discardableResult
    func startRun() -> Task<ActiveAgentRunSummary, Never>

    func cancelCurrentRun()
}

final class ActiveAgentRunTaskController: ActiveAgentRunTaskControlling {
    private let coordinator: any RunActiveAgentsCoordinating
    private var currentTask: Task<ActiveAgentRunSummary, Never>?

    init(coordinator: any RunActiveAgentsCoordinating) {
        self.coordinator = coordinator
    }

    deinit {
        cancelCurrentRun()
    }

    @discardableResult
    func startRun() -> Task<ActiveAgentRunSummary, Never> {
        cancelCurrentRun()

        let task = Task { [coordinator] in
            await coordinator.runActiveAgents()
        }
        currentTask = task
        return task
    }

    func cancelCurrentRun() {
        currentTask?.cancel()
        currentTask = nil
    }
}
