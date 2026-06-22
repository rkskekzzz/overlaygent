import ApplicationServices
import AppKit
import Foundation

enum AXAttribute: Equatable {
    case focusedUIElement
    case role
    case subrole
    case value
    case selectedTextRange
    case position
    case size

    var name: String {
        switch self {
        case .focusedUIElement:
            return kAXFocusedUIElementAttribute as String
        case .role:
            return kAXRoleAttribute as String
        case .subrole:
            return kAXSubroleAttribute as String
        case .value:
            return kAXValueAttribute as String
        case .selectedTextRange:
            return kAXSelectedTextRangeAttribute as String
        case .position:
            return kAXPositionAttribute as String
        case .size:
            return kAXSizeAttribute as String
        }
    }
}

enum AXAttributePayload: Equatable {
    case element(AXElement)
    case string(String)
    case textRange(AXTextRange)
    case point(CGPoint)
    case size(CGSize)
    case unsupported(typeDescription: String)
}

enum AXClientError: Error, Equatable, CustomStringConvertible {
    case invalidElement
    case attributeUnavailable(attribute: String, code: Int32)
    case invalidAttributeType(attribute: String, expected: String)

    var description: String {
        switch self {
        case .invalidElement:
            return "Invalid AX element"
        case let .attributeUnavailable(attribute, code):
            return "AX attribute unavailable: \(attribute) (code: \(code))"
        case let .invalidAttributeType(attribute, expected):
            return "AX attribute has unexpected type: \(attribute) (expected: \(expected))"
        }
    }
}

protocol AXAttributeReading {
    func systemWideElement() -> AXElement
    func copyAttribute(_ attribute: AXAttribute, from element: AXElement) -> Result<AXAttributePayload, AXClientError>
}

protocol AXCoordinateConverting {
    func appKitRect(fromAXTopLeftRect rect: CGRect) -> CGRect
}

struct SystemAXCoordinateConverter: AXCoordinateConverting {
    func appKitRect(fromAXTopLeftRect rect: CGRect) -> CGRect {
        let standardized = rect.standardized
        let screens = NSScreen.screens
        guard screens.isEmpty == false else {
            return standardized
        }

        let desktopTopY = screens
            .map(\.frame.maxY)
            .max() ?? standardized.maxY

        return CGRect(
            x: standardized.minX,
            y: desktopTopY - standardized.maxY,
            width: standardized.width,
            height: standardized.height
        )
    }
}

final class AXClient {
    private let reader: AXAttributeReading
    private let coordinateConverter: any AXCoordinateConverting

    init(
        reader: AXAttributeReading = SystemAXAttributeReader(),
        coordinateConverter: any AXCoordinateConverting = SystemAXCoordinateConverter()
    ) {
        self.reader = reader
        self.coordinateConverter = coordinateConverter
    }

    func focusedElement() throws -> AXFocusedElement {
        let systemWideElement = reader.systemWideElement()
        let element = try requiredElementAttribute(.focusedUIElement, from: systemWideElement)

        return AXFocusedElement(
            element: element,
            role: optionalStringAttribute(.role, from: element),
            subrole: optionalStringAttribute(.subrole, from: element),
            value: optionalStringAttribute(.value, from: element),
            selectedRange: optionalTextRangeAttribute(.selectedTextRange, from: element),
            frame: optionalFrame(from: element)
        )
    }

    private func requiredElementAttribute(_ attribute: AXAttribute, from element: AXElement) throws -> AXElement {
        switch reader.copyAttribute(attribute, from: element) {
        case let .success(.element(value)):
            return value
        case .success:
            throw AXClientError.invalidAttributeType(attribute: attribute.name, expected: "AXUIElement")
        case let .failure(error):
            throw error
        }
    }

    private func optionalStringAttribute(_ attribute: AXAttribute, from element: AXElement) -> String? {
        switch reader.copyAttribute(attribute, from: element) {
        case let .success(.string(value)):
            return value
        default:
            return nil
        }
    }

    private func optionalTextRangeAttribute(_ attribute: AXAttribute, from element: AXElement) -> AXTextRange? {
        switch reader.copyAttribute(attribute, from: element) {
        case let .success(.textRange(value)):
            return value
        default:
            return nil
        }
    }

    private func optionalFrame(from element: AXElement) -> CGRect? {
        guard let position = optionalPointAttribute(.position, from: element),
              let size = optionalSizeAttribute(.size, from: element),
              position.x.isFinite,
              position.y.isFinite,
              size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0 else {
            return nil
        }

        return coordinateConverter.appKitRect(
            fromAXTopLeftRect: CGRect(origin: position, size: size)
        )
    }

    private func optionalPointAttribute(_ attribute: AXAttribute, from element: AXElement) -> CGPoint? {
        switch reader.copyAttribute(attribute, from: element) {
        case let .success(.point(value)):
            return value
        default:
            return nil
        }
    }

    private func optionalSizeAttribute(_ attribute: AXAttribute, from element: AXElement) -> CGSize? {
        switch reader.copyAttribute(attribute, from: element) {
        case let .success(.size(value)):
            return value
        default:
            return nil
        }
    }
}

final class SystemAXAttributeReader: AXAttributeReading {
    func systemWideElement() -> AXElement {
        AXElement(AXUIElementCreateSystemWide())
    }

    func copyAttribute(_ attribute: AXAttribute, from element: AXElement) -> Result<AXAttributePayload, AXClientError> {
        guard CFGetTypeID(element.rawValue) == AXUIElementGetTypeID() else {
            return .failure(.invalidElement)
        }

        let axElement = unsafeBitCast(element.rawValue, to: AXUIElement.self)
        var rawValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(axElement, attribute.name as CFString, &rawValue)

        guard error == .success, let rawValue else {
            return .failure(.attributeUnavailable(attribute: attribute.name, code: error.rawValue))
        }

        return .success(Self.payload(from: rawValue))
    }

    private static func payload(from rawValue: CFTypeRef) -> AXAttributePayload {
        let typeID = CFGetTypeID(rawValue)

        if typeID == AXUIElementGetTypeID() {
            return .element(AXElement(rawValue))
        }

        if typeID == AXValueGetTypeID() {
            let axValue = unsafeBitCast(rawValue, to: AXValue.self)
            switch AXValueGetType(axValue) {
            case .cfRange:
                var range = CFRange()
                if AXValueGetValue(axValue, .cfRange, &range) {
                    return .textRange(AXTextRange(range))
                }
            case .cgPoint:
                var point = CGPoint.zero
                if AXValueGetValue(axValue, .cgPoint, &point) {
                    return .point(point)
                }
            case .cgSize:
                var size = CGSize.zero
                if AXValueGetValue(axValue, .cgSize, &size) {
                    return .size(size)
                }
            default:
                break
            }
        }

        if let string = rawValue as? String {
            return .string(string)
        }

        if let attributedString = rawValue as? NSAttributedString {
            return .string(attributedString.string)
        }

        return .unsupported(typeDescription: String(describing: type(of: rawValue)))
    }
}
