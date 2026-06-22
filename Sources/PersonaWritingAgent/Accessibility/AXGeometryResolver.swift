import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

protocol AXRangeBoundsReading {
    func bounds(for range: AXTextRange, in element: AXElement) -> CGRect?
}

struct AXTextGeometry: Equatable {
    var inputFrame: CGRect?
    var selectionBounds: CGRect?
    var caretBounds: CGRect?

    init(
        inputFrame: CGRect? = nil,
        selectionBounds: CGRect? = nil,
        caretBounds: CGRect? = nil
    ) {
        self.inputFrame = inputFrame
        self.selectionBounds = selectionBounds
        self.caretBounds = caretBounds
    }
}

struct AXGeometryResolver {
    private let boundsReader: AXRangeBoundsReading

    init(boundsReader: AXRangeBoundsReading = SystemAXRangeBoundsReader()) {
        self.boundsReader = boundsReader
    }

    func resolveGeometry(for element: AXFocusedElement) -> AXTextGeometry {
        AXTextGeometry(
            inputFrame: element.frame,
            selectionBounds: selectionBounds(for: element),
            caretBounds: caretBounds(for: element)
        )
    }

    func selectionBounds(for element: AXFocusedElement) -> CGRect? {
        guard let selectedRange = element.selectedRange, selectedRange.length > 0 else {
            return nil
        }

        return boundsReader.bounds(for: selectedRange, in: element.element)
    }

    func caretBounds(for element: AXFocusedElement) -> CGRect? {
        guard let selectedRange = element.selectedRange else {
            return nil
        }

        return boundsReader.bounds(
            for: AXTextRange(location: selectedRange.upperBound, length: 0),
            in: element.element
        )
    }
}

struct SystemAXRangeBoundsReader: AXRangeBoundsReading {
    private let coordinateConverter: any AXCoordinateConverting

    init(coordinateConverter: any AXCoordinateConverting = SystemAXCoordinateConverter()) {
        self.coordinateConverter = coordinateConverter
    }

    func bounds(for range: AXTextRange, in element: AXElement) -> CGRect? {
        guard CFGetTypeID(element.rawValue) == AXUIElementGetTypeID() else {
            return nil
        }

        let axElement = unsafeBitCast(element.rawValue, to: AXUIElement.self)
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
            return nil
        }

        var rawBounds: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(
            axElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &rawBounds
        )

        guard error == .success, let rawBounds, CFGetTypeID(rawBounds) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeBitCast(rawBounds, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgRect else {
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect) else {
            return nil
        }

        return coordinateConverter.appKitRect(fromAXTopLeftRect: rect)
    }
}
