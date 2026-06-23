import CoreGraphics
import Foundation
import XCTest
@testable import Overlaygent

final class AccessibilityPreparingInputCaptureTests: XCTestCase {
    func testPrepareRunsBeforeBaseCapture() throws {
        var events: [String] = []
        let preparer = RecordingAccessibilityPreparer {
            events.append("prepare")
        }
        let baseCapture = RecordingInputCapture(
            result: .success(Self.focusedTextCapture()),
            onCapture: {
                events.append("capture")
            }
        )
        let capture = AccessibilityPreparingInputCapture(
            preparer: preparer,
            baseCapture: baseCapture
        )

        let result = try capture.capture()

        XCTAssertEqual(result.snapshot.text, "Can we deploy it?")
        XCTAssertEqual(events, ["prepare", "capture"])
        XCTAssertEqual(preparer.callCount, 1)
        XCTAssertEqual(baseCapture.callCount, 1)
    }

    func testBaseCaptureErrorPropagatesAfterPreparation() {
        var events: [String] = []
        let preparer = RecordingAccessibilityPreparer {
            events.append("prepare")
        }
        let baseCapture = RecordingInputCapture(
            result: .failure(FocusedTextSessionError.missingSourceBundleID),
            onCapture: {
                events.append("capture")
            }
        )
        let capture = AccessibilityPreparingInputCapture(
            preparer: preparer,
            baseCapture: baseCapture
        )

        XCTAssertThrowsError(try capture.capture()) { error in
            XCTAssertEqual(error as? FocusedTextSessionError, .missingSourceBundleID)
        }
        XCTAssertEqual(events, ["prepare", "capture"])
    }

    private static func focusedTextCapture() -> FocusedTextCapture {
        let focusedElement = AXFocusedElement(
            element: AXElement(FakeAXNode()),
            role: "AXTextArea",
            subrole: nil,
            value: "Can we deploy it?",
            selectedRange: AXTextRange(location: 0, length: 3)
        )
        let snapshot = TextSnapshot(
            text: "Can we deploy it?",
            selectedRange: 0..<3,
            sourceBundleID: "com.tinyspeck.slackmacgap",
            sourceElementRole: "AXTextArea",
            contentHash: "sha256:test"
        )

        return FocusedTextCapture(
            focusedElement: focusedElement,
            snapshot: snapshot,
            geometry: AXTextGeometry(
                selectionBounds: CGRect(x: 10, y: 20, width: 80, height: 18),
                caretBounds: CGRect(x: 90, y: 20, width: 2, height: 18)
            )
        )
    }
}

private final class FakeAXNode: NSObject {}

private final class RecordingAccessibilityPreparer: FocusedApplicationAccessibilityPreparing {
    private let onPrepare: () -> Void
    private(set) var callCount = 0

    init(onPrepare: @escaping () -> Void = {}) {
        self.onPrepare = onPrepare
    }

    func prepareFocusedApplication() {
        callCount += 1
        onPrepare()
    }
}

private final class RecordingInputCapture: AgentRunInputCapturing {
    private let result: Result<FocusedTextCapture, Error>
    private let onCapture: () -> Void
    private(set) var callCount = 0

    init(
        result: Result<FocusedTextCapture, Error>,
        onCapture: @escaping () -> Void = {}
    ) {
        self.result = result
        self.onCapture = onCapture
    }

    func capture() throws -> FocusedTextCapture {
        callCount += 1
        onCapture()
        return try result.get()
    }
}
