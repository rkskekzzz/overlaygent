import ApplicationServices
import AppKit
import Foundation

enum AXAttribute: Equatable {
    case focusedApplication
    case focusedWindow
    case focusedUIElement
    case focused
    case role
    case subrole
    case value
    case selectedTextRange
    case children
    case position
    case size

    var name: String {
        switch self {
        case .focusedApplication:
            return kAXFocusedApplicationAttribute as String
        case .focusedWindow:
            return kAXFocusedWindowAttribute as String
        case .focusedUIElement:
            return kAXFocusedUIElementAttribute as String
        case .focused:
            return kAXFocusedAttribute as String
        case .role:
            return kAXRoleAttribute as String
        case .subrole:
            return kAXSubroleAttribute as String
        case .value:
            return kAXValueAttribute as String
        case .selectedTextRange:
            return kAXSelectedTextRangeAttribute as String
        case .children:
            return kAXChildrenAttribute as String
        case .position:
            return kAXPositionAttribute as String
        case .size:
            return kAXSizeAttribute as String
        }
    }
}

enum AXAttributePayload: Equatable {
    case element(AXElement)
    case elements([AXElement])
    case string(String)
    case bool(Bool)
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
    func frontmostApplicationElement() -> AXElement?
    func copyAttribute(_ attribute: AXAttribute, from element: AXElement) -> Result<AXAttributePayload, AXClientError>
}

extension AXAttributeReading {
    func frontmostApplicationElement() -> AXElement? {
        nil
    }
}

protocol AXCoordinateConverting {
    func appKitRect(fromAXTopLeftRect rect: CGRect) -> CGRect
}

struct SystemAXCoordinateConverter: AXCoordinateConverting {
    func appKitRect(fromAXTopLeftRect rect: CGRect) -> CGRect {
        Self.appKitRect(
            fromAXTopLeftRect: rect,
            screenFrames: NSScreen.screens.map(\.frame)
        )
    }

    static func appKitRect(fromAXTopLeftRect rect: CGRect, screenFrames: [CGRect]) -> CGRect {
        let standardized = rect.standardized
        guard screenFrames.isEmpty == false else {
            return standardized
        }

        let desktopTopY = primaryScreenTopY(in: screenFrames)

        return CGRect(
            x: standardized.minX,
            y: desktopTopY - standardized.maxY,
            width: standardized.width,
            height: standardized.height
        )
    }

    private static func primaryScreenTopY(in screenFrames: [CGRect]) -> CGFloat {
        if let primaryFrame = screenFrames.first(where: { $0.minX == 0 && $0.minY == 0 }) {
            return primaryFrame.maxY
        }

        return screenFrames[0].maxY
    }
}

final class AXClient {
    private struct TextElementCandidate {
        var element: AXElement
        var selectedRange: AXTextRange?
        var isFocused: Bool
    }

    private let textFallbackSearchMaxDepth = 12
    private let textFallbackSearchMaxNodes = 700
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
        let element = try focusedElement(from: systemWideElement)

        return AXFocusedElement(
            element: element,
            role: optionalStringAttribute(.role, from: element),
            subrole: optionalStringAttribute(.subrole, from: element),
            value: optionalStringAttribute(.value, from: element),
            selectedRange: optionalTextRangeAttribute(.selectedTextRange, from: element),
            frame: optionalFrame(from: element)
        )
    }

    private func focusedElement(from systemWideElement: AXElement) throws -> AXElement {
        do {
            return try requiredElementAttribute(.focusedUIElement, from: systemWideElement)
        } catch {
            guard shouldTryApplicationFallback(after: error) else {
                throw error
            }

            if let element = try focusedElementFromFocusedApplication(systemWideElement) {
                return element
            }

            if let applicationElement = reader.frontmostApplicationElement() {
                return try focusedElement(fromApplicationElement: applicationElement)
            }

            throw error
        }
    }

    private func focusedElementFromFocusedApplication(_ systemWideElement: AXElement) throws -> AXElement? {
        do {
            let applicationElement = try requiredElementAttribute(.focusedApplication, from: systemWideElement)
            return try focusedElement(fromApplicationElement: applicationElement)
        } catch let error as AXClientError {
            switch error {
            case let .attributeUnavailable(attribute, _)
                where attribute == AXAttribute.focusedApplication.name
                    || attribute == AXAttribute.focusedUIElement.name:
                return nil
            default:
                throw error
            }
        }
    }

    private func focusedElement(fromApplicationElement applicationElement: AXElement) throws -> AXElement {
        do {
            return try requiredElementAttribute(.focusedUIElement, from: applicationElement)
        } catch {
            guard shouldTryApplicationFallback(after: error) else {
                throw error
            }

            if let fallbackElement = focusedTextElementFromApplicationTree(applicationElement) {
                return fallbackElement
            }

            throw error
        }
    }

    private func focusedTextElementFromApplicationTree(_ applicationElement: AXElement) -> AXElement? {
        let roots = searchRoots(for: applicationElement)
        var focusedCandidates: [TextElementCandidate] = []
        var rangedCandidates: [TextElementCandidate] = []
        var textCandidates: [TextElementCandidate] = []
        var visited = Set<AXElement>()
        var remainingNodes = textFallbackSearchMaxNodes

        for root in roots {
            collectTextCandidates(
                from: root,
                depth: 0,
                visited: &visited,
                remainingNodes: &remainingNodes,
                focusedCandidates: &focusedCandidates,
                rangedCandidates: &rangedCandidates,
                textCandidates: &textCandidates
            )

            guard remainingNodes > 0 else {
                break
            }
        }

        if let focusedCandidate = focusedCandidates.last {
            return focusedCandidate.element
        }

        if let rangedCandidate = rangedCandidates.last {
            return rangedCandidate.element
        }

        return textCandidates.count == 1 ? textCandidates[0].element : nil
    }

    private func searchRoots(for applicationElement: AXElement) -> [AXElement] {
        var roots: [AXElement] = []

        if let focusedWindow = optionalElementAttribute(.focusedWindow, from: applicationElement) {
            roots.append(focusedWindow)
        }

        roots.append(applicationElement)
        return roots
    }

    private func collectTextCandidates(
        from element: AXElement,
        depth: Int,
        visited: inout Set<AXElement>,
        remainingNodes: inout Int,
        focusedCandidates: inout [TextElementCandidate],
        rangedCandidates: inout [TextElementCandidate],
        textCandidates: inout [TextElementCandidate]
    ) {
        guard depth <= textFallbackSearchMaxDepth,
              remainingNodes > 0,
              visited.insert(element).inserted else {
            return
        }

        remainingNodes -= 1

        if let candidate = textElementCandidate(from: element) {
            textCandidates.append(candidate)

            if candidate.isFocused {
                focusedCandidates.append(candidate)
            }

            if candidate.selectedRange != nil {
                rangedCandidates.append(candidate)
            }
        }

        for child in optionalElementsAttribute(.children, from: element) {
            collectTextCandidates(
                from: child,
                depth: depth + 1,
                visited: &visited,
                remainingNodes: &remainingNodes,
                focusedCandidates: &focusedCandidates,
                rangedCandidates: &rangedCandidates,
                textCandidates: &textCandidates
            )

            guard remainingNodes > 0 else {
                return
            }
        }
    }

    private func textElementCandidate(from element: AXElement) -> TextElementCandidate? {
        let role = optionalStringAttribute(.role, from: element)
        guard isTextInputRole(role) else {
            return nil
        }

        let value = optionalStringAttribute(.value, from: element)
        guard value != nil else {
            return nil
        }

        return TextElementCandidate(
            element: element,
            selectedRange: optionalTextRangeAttribute(.selectedTextRange, from: element),
            isFocused: optionalBoolAttribute(.focused, from: element) ?? false
        )
    }

    private func isTextInputRole(_ role: String?) -> Bool {
        guard let role else {
            return false
        }

        let supportedRoles = [
            NSAccessibility.Role.textArea.rawValue,
            NSAccessibility.Role.textField.rawValue,
            "AXSecureTextField"
        ]

        return supportedRoles.contains { supportedRole in
            supportedRole.caseInsensitiveCompare(role) == .orderedSame
        }
    }

    private func shouldTryApplicationFallback(after error: Error) -> Bool {
        guard let axError = error as? AXClientError else {
            return false
        }

        switch axError {
        case let .attributeUnavailable(attribute, _):
            return attribute == AXAttribute.focusedUIElement.name
        default:
            return false
        }
    }

    private func optionalElementAttribute(_ attribute: AXAttribute, from element: AXElement) -> AXElement? {
        switch reader.copyAttribute(attribute, from: element) {
        case let .success(.element(value)):
            return value
        default:
            return nil
        }
    }

    private func optionalElementsAttribute(_ attribute: AXAttribute, from element: AXElement) -> [AXElement] {
        switch reader.copyAttribute(attribute, from: element) {
        case let .success(.elements(value)):
            return value
        default:
            return []
        }
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

    private func optionalBoolAttribute(_ attribute: AXAttribute, from element: AXElement) -> Bool? {
        switch reader.copyAttribute(attribute, from: element) {
        case let .success(.bool(value)):
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
    private let applicationProvider: any FocusedApplicationProviding

    init(applicationProvider: any FocusedApplicationProviding = SystemFocusedApplicationProvider()) {
        self.applicationProvider = applicationProvider
    }

    func systemWideElement() -> AXElement {
        AXElement(AXUIElementCreateSystemWide())
    }

    func frontmostApplicationElement() -> AXElement? {
        guard let application = applicationProvider.focusedApplication(),
              NSRunningApplication(processIdentifier: application.processIdentifier) != nil else {
            return nil
        }

        return AXElement(AXUIElementCreateApplication(application.processIdentifier))
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

        if typeID == CFBooleanGetTypeID() {
            let boolValue = unsafeBitCast(rawValue, to: CFBoolean.self)
            return .bool(CFBooleanGetValue(boolValue))
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

        if let rawChildren = rawValue as? [AnyObject] {
            let elements = rawChildren.compactMap { rawChild -> AXElement? in
                guard CFGetTypeID(rawChild) == AXUIElementGetTypeID() else {
                    return nil
                }

                return AXElement(rawChild)
            }

            if elements.count == rawChildren.count {
                return .elements(elements)
            }
        }

        return .unsupported(typeDescription: String(describing: type(of: rawValue)))
    }
}
