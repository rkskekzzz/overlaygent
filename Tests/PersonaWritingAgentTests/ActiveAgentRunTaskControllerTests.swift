import Foundation
import XCTest
@testable import PersonaWritingAgent

final class ActiveAgentRunTaskControllerTests: XCTestCase {
    func testStartingNewRunCancelsPreviousRun() async {
        let state = RunTaskControllerTestState()
        let coordinator = BlockingRunActiveAgentsCoordinator(state: state)
        let controller = ActiveAgentRunTaskController(coordinator: coordinator)

        let firstTask = controller.startRun()
        await state.waitForStartedRuns(1)

        let secondTask = controller.startRun()
        await state.waitForStartedRuns(2)

        let firstSummary = await firstTask.value
        XCTAssertEqual(firstSummary.failureStage, .cancelled)
        XCTAssertFalse(secondTask.isCancelled)

        controller.cancelCurrentRun()
        let secondSummary = await secondTask.value
        XCTAssertEqual(secondSummary.failureStage, .cancelled)
    }

    func testCancelCurrentRunCancelsActiveRun() async {
        let state = RunTaskControllerTestState()
        let coordinator = BlockingRunActiveAgentsCoordinator(state: state)
        let controller = ActiveAgentRunTaskController(coordinator: coordinator)

        let task = controller.startRun()
        await state.waitForStartedRuns(1)

        controller.cancelCurrentRun()

        let summary = await task.value
        XCTAssertEqual(summary.failureStage, .cancelled)
    }
}

private final class BlockingRunActiveAgentsCoordinator: RunActiveAgentsCoordinating {
    private let state: RunTaskControllerTestState

    init(state: RunTaskControllerTestState) {
        self.state = state
    }

    func runActiveAgents() async -> ActiveAgentRunSummary {
        await state.markStarted()

        while Task.isCancelled == false {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }

        return ActiveAgentRunSummary(
            requestedAgentCount: 0,
            totalResults: 0,
            successfulResults: 0,
            failedResults: 0,
            didShowOverlay: false,
            failureStage: .cancelled
        )
    }
}

private actor RunTaskControllerTestState {
    private var startedRunCount = 0
    private var waiters: [(minimumCount: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func markStarted() {
        startedRunCount += 1
        resumeSatisfiedWaiters()
    }

    func waitForStartedRuns(_ minimumCount: Int) async {
        guard startedRunCount < minimumCount else {
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append((minimumCount, continuation))
        }
    }

    private func resumeSatisfiedWaiters() {
        var pendingWaiters: [(minimumCount: Int, continuation: CheckedContinuation<Void, Never>)] = []

        for waiter in waiters {
            if startedRunCount >= waiter.minimumCount {
                waiter.continuation.resume()
            } else {
                pendingWaiters.append(waiter)
            }
        }

        waiters = pendingWaiters
    }
}
