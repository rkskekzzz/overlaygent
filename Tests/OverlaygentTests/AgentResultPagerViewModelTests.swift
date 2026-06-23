import XCTest
@testable import Overlaygent

@MainActor
final class AgentResultPagerViewModelTests: XCTestCase {
    func testInitialPageIndexClampsIntoSuggestionRange() {
        let suggestions = [
            suggestion(id: UUID(), agentName: "First"),
            suggestion(id: UUID(), agentName: "Second")
        ]

        let belowRange = AgentResultPagerViewModel(suggestions: suggestions, initialPageIndex: -3)
        let aboveRange = AgentResultPagerViewModel(suggestions: suggestions, initialPageIndex: 8)

        XCTAssertEqual(belowRange.currentPageIndex, 0)
        XCTAssertEqual(aboveRange.currentPageIndex, 1)
        XCTAssertEqual(aboveRange.currentPageNumber, 2)
        XCTAssertEqual(aboveRange.pageStatusText, "2 of 2")
    }

    func testNextAndPreviousNavigationStopsAtBounds() {
        let viewModel = AgentResultPagerViewModel(
            suggestions: [
                suggestion(agentName: "First"),
                suggestion(agentName: "Second"),
                suggestion(agentName: "Third")
            ]
        )

        XCTAssertFalse(viewModel.canGoPrevious)
        XCTAssertTrue(viewModel.canGoNext)

        viewModel.goToPrevious()
        XCTAssertEqual(viewModel.currentPageIndex, 0)

        viewModel.goToNext()
        viewModel.goToNext()
        viewModel.goToNext()

        XCTAssertEqual(viewModel.currentPageIndex, 2)
        XCTAssertTrue(viewModel.canGoPrevious)
        XCTAssertFalse(viewModel.canGoNext)

        viewModel.goToPrevious()
        XCTAssertEqual(viewModel.currentSuggestion?.agentName, "Second")
    }

    func testSelectingPageUpdatesCurrentSuggestion() {
        let firstID = UUID()
        let secondID = UUID()
        let viewModel = AgentResultPagerViewModel(
            suggestions: [
                suggestion(id: firstID, agentName: "Friendly"),
                suggestion(id: secondID, agentName: "Technical")
            ]
        )

        viewModel.selectPage(at: 1)

        XCTAssertEqual(viewModel.currentPageIndex, 1)
        XCTAssertEqual(viewModel.currentSuggestion?.id, secondID)

        viewModel.selectPage(at: 10)

        XCTAssertEqual(viewModel.currentPageIndex, 1)
        XCTAssertEqual(viewModel.currentSuggestion?.id, secondID)
    }

    func testReplacingSuggestionsKeepsPageIndexValid() {
        let viewModel = AgentResultPagerViewModel(
            suggestions: [
                suggestion(agentName: "First"),
                suggestion(agentName: "Second"),
                suggestion(agentName: "Third")
            ],
            initialPageIndex: 2
        )

        viewModel.replaceSuggestions([
            suggestion(agentName: "Replacement")
        ])

        XCTAssertEqual(viewModel.currentPageIndex, 0)
        XCTAssertEqual(viewModel.currentSuggestion?.agentName, "Replacement")
        XCTAssertEqual(viewModel.pageStatusText, "1 of 1")

        viewModel.replaceSuggestions([])

        XCTAssertEqual(viewModel.currentPageIndex, 0)
        XCTAssertNil(viewModel.currentSuggestion)
        XCTAssertEqual(viewModel.pageStatusText, "0 of 0")
    }

    private func suggestion(
        id: UUID = UUID(),
        agentName: String
    ) -> AgentSuggestion {
        AgentSuggestion(
            id: id,
            agentName: agentName,
            result: CorrectionResult(
                summary: "\(agentName) summary",
                edits: [
                    CorrectionEdit(
                        rangeStart: 0,
                        rangeEnd: 5,
                        original: "hello",
                        replacement: "Hello",
                        reason: "Capitalization"
                    )
                ],
                fullRewrite: "\(agentName) rewrite"
            )
        )
    }
}
