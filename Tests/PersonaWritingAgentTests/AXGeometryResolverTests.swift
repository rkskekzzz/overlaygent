import CoreGraphics
import Foundation
import XCTest
@testable import PersonaWritingAgent

final class AXGeometryResolverTests: XCTestCase {
    func testResolvesSelectionAndCaretBoundsThroughBoundsReader() {
        let axElement = AXElement(FakeAXNode())
        let focusedElement = AXFocusedElement(
            element: axElement,
            role: "AXTextArea",
            subrole: nil,
            value: "Can we deploy it after review?",
            selectedRange: AXTextRange(location: 7, length: 9),
            frame: CGRect(x: 8, y: 12, width: 380, height: 52)
        )
        let selectionRect = CGRect(x: 10, y: 20, width: 90, height: 18)
        let caretRect = CGRect(x: 100, y: 20, width: 2, height: 18)
        let boundsReader = FakeRangeBoundsReader(bounds: [
            BoundsKey(element: axElement, range: AXTextRange(location: 7, length: 9)): selectionRect,
            BoundsKey(element: axElement, range: AXTextRange(location: 16, length: 0)): caretRect
        ])
        let resolver = AXGeometryResolver(boundsReader: boundsReader)

        let geometry = resolver.resolveGeometry(for: focusedElement)

        XCTAssertEqual(geometry.inputFrame, CGRect(x: 8, y: 12, width: 380, height: 52))
        XCTAssertEqual(geometry.selectionBounds, selectionRect)
        XCTAssertEqual(geometry.caretBounds, caretRect)
        XCTAssertEqual(
            boundsReader.requests,
            [
                BoundsKey(element: axElement, range: AXTextRange(location: 7, length: 9)),
                BoundsKey(element: axElement, range: AXTextRange(location: 16, length: 0))
            ]
        )
    }

    func testSelectionBoundsAreNilForCaretOnlyRange() {
        let axElement = AXElement(FakeAXNode())
        let focusedElement = AXFocusedElement(
            element: axElement,
            role: "AXTextField",
            subrole: nil,
            value: "Draft",
            selectedRange: AXTextRange(location: 5, length: 0)
        )
        let caretRect = CGRect(x: 40, y: 12, width: 2, height: 17)
        let boundsReader = FakeRangeBoundsReader(bounds: [
            BoundsKey(element: axElement, range: AXTextRange(location: 5, length: 0)): caretRect
        ])
        let resolver = AXGeometryResolver(boundsReader: boundsReader)

        let geometry = resolver.resolveGeometry(for: focusedElement)

        XCTAssertNil(geometry.selectionBounds)
        XCTAssertEqual(geometry.caretBounds, caretRect)
        XCTAssertEqual(boundsReader.requests, [BoundsKey(element: axElement, range: AXTextRange(location: 5, length: 0))])
    }

    func testBoundsReaderNilFallsBackToNilGeometry() {
        let axElement = AXElement(FakeAXNode())
        let focusedElement = AXFocusedElement(
            element: axElement,
            role: "AXTextArea",
            subrole: nil,
            value: "Draft",
            selectedRange: AXTextRange(location: 1, length: 2)
        )
        let resolver = AXGeometryResolver(boundsReader: FakeRangeBoundsReader(bounds: [:]))

        let geometry = resolver.resolveGeometry(for: focusedElement)

        XCTAssertNil(geometry.selectionBounds)
        XCTAssertNil(geometry.caretBounds)
    }

    func testMissingSelectedRangeDoesNotAskForBounds() {
        let axElement = AXElement(FakeAXNode())
        let focusedElement = AXFocusedElement(
            element: axElement,
            role: "AXTextArea",
            subrole: nil,
            value: "Draft",
            selectedRange: nil
        )
        let boundsReader = FakeRangeBoundsReader(bounds: [:])
        let resolver = AXGeometryResolver(boundsReader: boundsReader)

        let geometry = resolver.resolveGeometry(for: focusedElement)

        XCTAssertNil(geometry.selectionBounds)
        XCTAssertNil(geometry.caretBounds)
        XCTAssertEqual(boundsReader.requests, [])
    }
}

private final class FakeAXNode: NSObject {}

private struct BoundsKey: Hashable, Equatable {
    var element: AXElement
    var range: AXTextRange

    func hash(into hasher: inout Hasher) {
        hasher.combine(element)
        hasher.combine(range.location)
        hasher.combine(range.length)
    }
}

private final class FakeRangeBoundsReader: AXRangeBoundsReading {
    private let bounds: [BoundsKey: CGRect]
    private(set) var requests: [BoundsKey] = []

    init(bounds: [BoundsKey: CGRect]) {
        self.bounds = bounds
    }

    func bounds(for range: AXTextRange, in element: AXElement) -> CGRect? {
        let key = BoundsKey(element: element, range: range)
        requests.append(key)
        return bounds[key]
    }
}
