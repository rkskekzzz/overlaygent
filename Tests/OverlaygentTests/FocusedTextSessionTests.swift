import Foundation
import CoreGraphics
import XCTest
@testable import Overlaygent

final class FocusedTextSessionTests: XCTestCase {
    func testSnapshotCreatedForAccessibleTextField() throws {
        let element = AXElement(FakeAXNode())
        let provider = FakeFocusedElementProvider(
            element: focusedElement(
                element: element,
                role: "AXTextArea",
                subrole: "AXStandardWindowTextArea",
                value: "Can we deploy it after review?",
                selectedRange: AXTextRange(location: 7, length: 9)
            )
        )
        let sourceResolver = FakeSourceBundleResolver(bundleIDs: [element: "com.tinyspeck.slackmacgap"])
        let session = FocusedTextSession(
            focusedElementProvider: provider,
            sourceBundleResolver: sourceResolver,
            geometryResolver: AXGeometryResolver(boundsReader: FakeRangeBoundsReader())
        )

        let snapshot = try session.snapshot()

        XCTAssertEqual(snapshot.text, "Can we deploy it after review?")
        XCTAssertEqual(snapshot.selectedRange, 7..<16)
        XCTAssertEqual(snapshot.sourceBundleID, "com.tinyspeck.slackmacgap")
        XCTAssertEqual(snapshot.sourceElementRole, "AXTextArea")
        XCTAssertEqual(
            snapshot.contentHash,
            TextSnapshotHasher().hash(text: "Can we deploy it after review?")
        )
        XCTAssertTrue(snapshot.contentHash.hasPrefix("sha256:") || snapshot.contentHash.hasPrefix("fnv1a64:"))
    }

    func testCaptureIncludesFocusedElementSnapshotAndGeometry() throws {
        let element = AXElement(FakeAXNode())
        let focusedElement = focusedElement(
            element: element,
            role: "AXTextArea",
            subrole: "AXStandardWindowTextArea",
            value: "Can we deploy it after review?",
            selectedRange: AXTextRange(location: 7, length: 9)
        )
        let provider = FakeFocusedElementProvider(element: focusedElement)
        let sourceResolver = FakeSourceBundleResolver(bundleIDs: [element: "com.tinyspeck.slackmacgap"])
        let boundsReader = FakeRangeBoundsReader(
            selectionBounds: CGRect(x: 80, y: 320, width: 120, height: 20),
            caretBounds: CGRect(x: 200, y: 320, width: 2, height: 20)
        )
        let session = FocusedTextSession(
            focusedElementProvider: provider,
            sourceBundleResolver: sourceResolver,
            geometryResolver: AXGeometryResolver(boundsReader: boundsReader)
        )

        let capture = try session.capture()

        XCTAssertEqual(capture.focusedElement, focusedElement)
        XCTAssertEqual(capture.snapshot.text, "Can we deploy it after review?")
        XCTAssertEqual(capture.geometry.selectionBounds, CGRect(x: 80, y: 320, width: 120, height: 20))
        XCTAssertEqual(capture.geometry.caretBounds, CGRect(x: 200, y: 320, width: 2, height: 20))
    }

    func testSecureFieldIsRejectedBeforeSnapshotCreation() {
        let element = AXElement(FakeAXNode())
        let provider = FakeFocusedElementProvider(
            element: focusedElement(
                element: element,
                role: "AXSecureTextField",
                subrole: nil,
                value: "hidden",
                selectedRange: nil
            )
        )
        let sourceResolver = FakeSourceBundleResolver(bundleIDs: [element: "com.example.SecretApp"])
        let session = FocusedTextSession(
            focusedElementProvider: provider,
            sourceBundleResolver: sourceResolver,
            geometryResolver: AXGeometryResolver(boundsReader: FakeRangeBoundsReader())
        )

        XCTAssertThrowsError(try session.snapshot()) { error in
            XCTAssertEqual(error as? FocusedTextSessionError, .rejected(reason: .secureField))
        }
        XCTAssertEqual(sourceResolver.requests, [])
    }

    func testUnsupportedRoleIsRejected() {
        let element = AXElement(FakeAXNode())
        let provider = FakeFocusedElementProvider(
            element: focusedElement(
                element: element,
                role: "AXStaticText",
                subrole: nil,
                value: "Visible label",
                selectedRange: nil
            )
        )
        let session = FocusedTextSession(
            focusedElementProvider: provider,
            sourceBundleResolver: FakeSourceBundleResolver(bundleIDs: [element: "com.example.App"]),
            geometryResolver: AXGeometryResolver(boundsReader: FakeRangeBoundsReader())
        )

        XCTAssertThrowsError(try session.snapshot()) { error in
            XCTAssertEqual(error as? FocusedTextSessionError, .rejected(reason: .unsupportedRole))
        }
    }

    func testInvalidSelectedRangeFallsBackToNilWithoutRejectingSnapshot() throws {
        let element = AXElement(FakeAXNode())
        let provider = FakeFocusedElementProvider(
            element: focusedElement(
                element: element,
                role: "AXTextField",
                subrole: nil,
                value: "Draft",
                selectedRange: AXTextRange(location: 10, length: 2)
            )
        )
        let session = FocusedTextSession(
            focusedElementProvider: provider,
            sourceBundleResolver: FakeSourceBundleResolver(bundleIDs: [element: "com.example.App"]),
            geometryResolver: AXGeometryResolver(boundsReader: FakeRangeBoundsReader())
        )

        let snapshot = try session.snapshot()

        XCTAssertNil(snapshot.selectedRange)
        XCTAssertEqual(snapshot.text, "Draft")
    }

    func testMissingSourceBundleIDRejectsSnapshot() {
        let element = AXElement(FakeAXNode())
        let provider = FakeFocusedElementProvider(
            element: focusedElement(
                element: element,
                role: "AXTextField",
                subrole: nil,
                value: "Draft",
                selectedRange: nil
            )
        )
        let session = FocusedTextSession(
            focusedElementProvider: provider,
            sourceBundleResolver: FakeSourceBundleResolver(bundleIDs: [:]),
            geometryResolver: AXGeometryResolver(boundsReader: FakeRangeBoundsReader())
        )

        XCTAssertThrowsError(try session.snapshot()) { error in
            XCTAssertEqual(error as? FocusedTextSessionError, .missingSourceBundleID)
        }
    }

    func testContentHashIsStableAndChangesWithText() {
        let hasher = TextSnapshotHasher()

        XCTAssertEqual(hasher.hash(text: "same text"), hasher.hash(text: "same text"))
        XCTAssertNotEqual(hasher.hash(text: "same text"), hasher.hash(text: "other text"))
    }

    private func focusedElement(
        element: AXElement,
        role: String?,
        subrole: String?,
        value: String?,
        selectedRange: AXTextRange?
    ) -> AXFocusedElement {
        AXFocusedElement(
            element: element,
            role: role,
            subrole: subrole,
            value: value,
            selectedRange: selectedRange
        )
    }
}

private final class FakeAXNode: NSObject {}

private struct FakeFocusedElementProvider: AXFocusedElementProviding {
    var element: AXFocusedElement

    func focusedElement() throws -> AXFocusedElement {
        element
    }
}

private final class FakeSourceBundleResolver: AXSourceBundleResolving {
    private let bundleIDs: [AXElement: String]
    private(set) var requests: [AXElement] = []

    init(bundleIDs: [AXElement: String]) {
        self.bundleIDs = bundleIDs
    }

    func sourceBundleID(for element: AXElement) -> String? {
        requests.append(element)
        return bundleIDs[element]
    }
}

private final class FakeRangeBoundsReader: AXRangeBoundsReading {
    private let selectionBounds: CGRect?
    private let caretBounds: CGRect?

    init(selectionBounds: CGRect? = nil, caretBounds: CGRect? = nil) {
        self.selectionBounds = selectionBounds
        self.caretBounds = caretBounds
    }

    func bounds(for range: AXTextRange, in element: AXElement) -> CGRect? {
        range.length == 0 ? caretBounds : selectionBounds
    }
}
