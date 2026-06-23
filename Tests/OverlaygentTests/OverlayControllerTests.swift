import AppKit
import Carbon
import CoreGraphics
import XCTest
@testable import Overlaygent

final class OverlayPositioningTests: XCTestCase {
    func testPlacesPanelAboveCaretWhenThereIsRoom() {
        let positioner = OverlayPositioning(defaultPanelSize: CGSize(width: 300, height: 120), spacing: 8, screenPadding: 12)
        let placement = positioner.placement(
            for: OverlayAnchorGeometry(caretRect: CGRect(x: 500, y: 500, width: 2, height: 18)),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800)
        )

        XCTAssertEqual(placement.anchorSource, .caret)
        XCTAssertEqual(placement.frame, CGRect(x: 351, y: 526, width: 300, height: 120))
    }

    func testKeepsPanelAboveCaretNearBottomEdge() {
        let positioner = OverlayPositioning(defaultPanelSize: CGSize(width: 300, height: 120), spacing: 8, screenPadding: 12)
        let placement = positioner.placement(
            for: OverlayAnchorGeometry(caretRect: CGRect(x: 220, y: 40, width: 2, height: 18)),
            visibleFrame: CGRect(x: 0, y: 0, width: 600, height: 500)
        )

        XCTAssertEqual(placement.anchorSource, .caret)
        XCTAssertEqual(placement.frame, CGRect(x: 71, y: 66, width: 300, height: 120))
    }

    func testClampsPanelInsideVisibleFrame() {
        let positioner = OverlayPositioning(defaultPanelSize: CGSize(width: 260, height: 120), spacing: 8, screenPadding: 12)
        let placement = positioner.placement(
            for: OverlayAnchorGeometry(caretRect: CGRect(x: 390, y: 250, width: 2, height: 18)),
            visibleFrame: CGRect(x: 0, y: 0, width: 420, height: 300)
        )

        XCTAssertEqual(placement.frame, CGRect(x: 148, y: 122, width: 260, height: 120))
        XCTAssertGreaterThanOrEqual(placement.frame.minX, 12)
        XCTAssertLessThanOrEqual(placement.frame.maxX, 408)
        XCTAssertGreaterThanOrEqual(placement.frame.minY, 12)
        XCTAssertLessThanOrEqual(placement.frame.maxY, 288)
    }

    func testUsesFallbackRectWhenBoundsAreUnavailable() {
        let positioner = OverlayPositioning(defaultPanelSize: CGSize(width: 200, height: 80), spacing: 10, screenPadding: 10)
        let placement = positioner.placement(
            for: OverlayAnchorGeometry(fallbackRect: CGRect(x: 300, y: 300, width: 100, height: 40)),
            visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )

        XCTAssertEqual(placement.anchorSource, .fallback)
        XCTAssertEqual(placement.frame, CGRect(x: 250, y: 350, width: 200, height: 80))
    }

    func testUsesInputRectWhenCaretIsOutsideInputFrame() {
        let positioner = OverlayPositioning(defaultPanelSize: CGSize(width: 200, height: 80), spacing: 10, screenPadding: 10)
        let placement = positioner.placement(
            for: OverlayAnchorGeometry(
                caretRect: CGRect(x: 10, y: 20, width: 2, height: 18),
                inputRect: CGRect(x: 300, y: 300, width: 220, height: 44)
            ),
            visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )

        XCTAssertEqual(placement.anchorSource, .input)
        XCTAssertEqual(placement.frame, CGRect(x: 300, y: 354, width: 200, height: 80))
    }

    func testPrefersInputRectWhenCaretIsInsideInputFrame() {
        let positioner = OverlayPositioning(defaultPanelSize: CGSize(width: 200, height: 80), spacing: 10, screenPadding: 10)
        let placement = positioner.placement(
            for: OverlayAnchorGeometry(
                caretRect: CGRect(x: 410, y: 312, width: 2, height: 18),
                inputRect: CGRect(x: 300, y: 300, width: 220, height: 44)
            ),
            visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )

        XCTAssertEqual(placement.anchorSource, .input)
        XCTAssertEqual(placement.frame, CGRect(x: 300, y: 354, width: 200, height: 80))
    }

    func testFallsBackToCaretWhenInputRectLooksLikeWholeDocument() {
        let positioner = OverlayPositioning(defaultPanelSize: CGSize(width: 200, height: 80), spacing: 10, screenPadding: 10)
        let placement = positioner.placement(
            for: OverlayAnchorGeometry(
                caretRect: CGRect(x: 410, y: 88, width: 2, height: 18),
                inputRect: CGRect(x: 0, y: 0, width: 800, height: 590)
            ),
            visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )

        XCTAssertEqual(placement.anchorSource, .caret)
        XCTAssertEqual(placement.frame, CGRect(x: 311, y: 116, width: 200, height: 80))
    }

    func testSkipsWholeDocumentInputRectWhenCaretIsUnavailable() {
        let positioner = OverlayPositioning(defaultPanelSize: CGSize(width: 200, height: 80), spacing: 10, screenPadding: 10)
        let placement = positioner.placement(
            for: OverlayAnchorGeometry(
                inputRect: CGRect(x: 0, y: 0, width: 800, height: 590),
                fallbackRect: CGRect(x: 300, y: 300, width: 100, height: 40)
            ),
            visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )

        XCTAssertEqual(placement.anchorSource, .fallback)
        XCTAssertEqual(placement.frame, CGRect(x: 250, y: 350, width: 200, height: 80))
    }

    func testUsesDefaultAnchorAndSizeWhenNoBoundsAreAvailable() {
        let positioner = OverlayPositioning(defaultPanelSize: CGSize(width: 360, height: 164), spacing: 8, screenPadding: 12)
        let placement = positioner.placement(
            for: OverlayAnchorGeometry(),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_024, height: 768)
        )

        XCTAssertEqual(placement.anchorSource, .defaultScreen)
        XCTAssertEqual(placement.frame.size, CGSize(width: 360, height: 164))
        XCTAssertGreaterThanOrEqual(placement.frame.minX, 12)
        XCTAssertLessThanOrEqual(placement.frame.maxX, 1_012)
        XCTAssertGreaterThanOrEqual(placement.frame.minY, 12)
        XCTAssertLessThanOrEqual(placement.frame.maxY, 756)
    }

    func testShrinksPanelToVisibleFrameWithPaddingWhenRequestedSizeIsTooWide() {
        let positioner = OverlayPositioning(defaultPanelSize: CGSize(width: 500, height: 400), spacing: 8, screenPadding: 12)
        let placement = positioner.placement(
            for: OverlayAnchorGeometry(caretRect: CGRect(x: 150, y: 100, width: 1, height: 1)),
            panelSize: CGSize(width: 500, height: 400),
            visibleFrame: CGRect(x: 0, y: 0, width: 300, height: 200)
        )

        XCTAssertEqual(placement.frame, CGRect(x: 12, y: 12, width: 276, height: 176))
    }
}

final class OverlayControllerTests: XCTestCase {
    func testStatusAndSuggestionLayoutsShareSizeToAvoidTransitionJump() {
        XCTAssertEqual(
            AgentStatusOverlayLayout.preferredContentSize,
            AgentSuggestionOverlayLayout.preferredContentSize
        )
    }

    func testShowSuggestionPositionsAndPresentsPanel() {
        let panelController = FakeSuggestionPanelController(preferredContentSize: CGSize(width: 200, height: 100))
        let positioner = OverlayPositioning(defaultPanelSize: CGSize(width: 360, height: 164), spacing: 10, screenPadding: 20)
        let anchorRect = CGRect(x: 380, y: 300, width: 2, height: 20)
        let visibleFrame = CGRect(x: 0, y: 0, width: 800, height: 600)
        var requestedScreenRect: CGRect?
        let controller = OverlayController(
            panelController: panelController,
            positioner: positioner,
            visibleFrameProvider: { rect in
                requestedScreenRect = rect
                return visibleFrame
            }
        )

        let placement = controller.showSuggestion(
            anchor: OverlayAnchorGeometry(caretRect: anchorRect),
            title: "Preview",
            detail: "Sample"
        )

        XCTAssertEqual(requestedScreenRect, anchorRect)
        XCTAssertEqual(placement.anchorSource, .caret)
        XCTAssertEqual(placement.frame, CGRect(x: 281, y: 330, width: 200, height: 100))
        XCTAssertEqual(panelController.placeholderTitle, "Preview")
        XCTAssertEqual(panelController.placeholderDetail, "Sample")
        XCTAssertEqual(panelController.shownFrame, placement.frame)
    }

    func testHideSuggestionHidesPanel() {
        let panelController = FakeSuggestionPanelController(preferredContentSize: CGSize(width: 200, height: 100))
        let controller = OverlayController(panelController: panelController)

        controller.hideSuggestion()

        XCTAssertTrue(panelController.didHide)
    }

    func testShowSuggestionsPositionsAndPresentsPagerPanel() {
        let panelController = FakeSuggestionPanelController(preferredContentSize: CGSize(width: 200, height: 100))
        let positioner = OverlayPositioning(defaultPanelSize: CGSize(width: 360, height: 164), spacing: 10, screenPadding: 20)
        let anchorRect = CGRect(x: 500, y: 600, width: 2, height: 20)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        var requestedScreenRect: CGRect?
        var appliedSuggestion: AgentSuggestion?
        var dismissedSuggestion: AgentSuggestion?
        let suggestion = suggestion(agentName: "Natural English")
        let controller = OverlayController(
            panelController: panelController,
            positioner: positioner,
            visibleFrameProvider: { rect in
                requestedScreenRect = rect
                return visibleFrame
            }
        )

        let placement = controller.showSuggestions(
            anchor: OverlayAnchorGeometry(caretRect: anchorRect),
            suggestions: [suggestion],
            onApply: {
                appliedSuggestion = $0
                return true
            },
            onDismiss: { dismissedSuggestion = $0 }
        )

        XCTAssertEqual(requestedScreenRect, anchorRect)
        XCTAssertEqual(placement.anchorSource, .caret)
        XCTAssertEqual(placement.frame, CGRect(x: 401, y: 630, width: 200, height: 100))
        XCTAssertEqual(panelController.presentedSuggestions, [suggestion])
        XCTAssertEqual(panelController.shownFrame, placement.frame)

        _ = panelController.applyHandler?(suggestion)
        panelController.dismissHandler?(suggestion)

        XCTAssertEqual(appliedSuggestion, suggestion)
        XCTAssertEqual(dismissedSuggestion, suggestion)
    }

    private func suggestion(agentName: String) -> AgentSuggestion {
        AgentSuggestion(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000901")!,
            agentName: agentName,
            result: CorrectionResult(
                summary: "Improved phrasing.",
                edits: [
                    CorrectionEdit(
                        rangeStart: 0,
                        rangeEnd: 5,
                        original: "hello",
                        replacement: "Hello",
                        reason: "Capitalization"
                    )
                ],
                fullRewrite: "Hello there."
            )
        )
    }
}

final class AgentSuggestionOverlayKeyboardActionTests: XCTestCase {
    func testMapsPlainOverlayNavigationKeys() {
        XCTAssertEqual(action(for: kVK_LeftArrow), .previous)
        XCTAssertEqual(action(for: kVK_RightArrow), .next)
        XCTAssertEqual(action(for: kVK_Return), .apply)
        XCTAssertEqual(action(for: kVK_ANSI_KeypadEnter), .apply)
        XCTAssertEqual(action(for: kVK_Escape), .dismiss)
    }

    func testIgnoresModifiedNavigationKeys() {
        XCTAssertNil(action(for: kVK_LeftArrow, modifiers: [.shift]))
        XCTAssertNil(action(for: kVK_RightArrow, modifiers: [.command]))
        XCTAssertNil(action(for: kVK_Return, modifiers: [.option]))
        XCTAssertNil(action(for: kVK_Escape, modifiers: [.control]))
    }

    func testIgnoresUnrelatedKeys() {
        XCTAssertNil(action(for: kVK_ANSI_A))
    }

    private func action(
        for keyCode: Int,
        modifiers: NSEvent.ModifierFlags = []
    ) -> AgentSuggestionOverlayKeyboardAction? {
        AgentSuggestionOverlayKeyboardAction.action(
            forKeyCode: UInt16(keyCode),
            modifierFlags: modifiers
        )
    }
}

private final class FakeSuggestionPanelController: SuggestionPanelPresenting {
    let preferredContentSize: CGSize
    private(set) var placeholderTitle: String?
    private(set) var placeholderDetail: String?
    private(set) var presentedSuggestions: [AgentSuggestion] = []
    private(set) var applyHandler: ((AgentSuggestion) -> Bool)?
    private(set) var dismissHandler: ((AgentSuggestion?) -> Void)?
    private(set) var shownFrame: CGRect?
    private(set) var didHide = false

    init(preferredContentSize: CGSize) {
        self.preferredContentSize = preferredContentSize
    }

    func setPlaceholder(title: String, detail: String) {
        placeholderTitle = title
        placeholderDetail = detail
    }

    func setSuggestions(
        _ suggestions: [AgentSuggestion],
        onApply: @escaping (AgentSuggestion) -> Bool,
        onDismiss: @escaping (AgentSuggestion?) -> Void
    ) {
        presentedSuggestions = suggestions
        applyHandler = onApply
        dismissHandler = onDismiss
    }

    func show(frame: CGRect) {
        shownFrame = frame
    }

    func hide() {
        didHide = true
    }
}
