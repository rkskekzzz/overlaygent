import Foundation
import XCTest
@testable import PersonaWritingAgent

final class AXFocusedElementReaderTests: XCTestCase {
    func testFocusedElementReadsRoleSubroleValueAndSelectedRange() throws {
        let systemWideNode = FakeAXNode()
        let focusedNode = FakeAXNode()
        let systemWideElement = AXElement(systemWideNode)
        let focusedElement = AXElement(focusedNode)
        let reader = FakeAXAttributeReader(systemWideElement: systemWideElement)
        reader.set(.element(focusedElement), for: .focusedUIElement, on: systemWideElement)
        reader.set(.string("AXTextArea"), for: .role, on: focusedElement)
        reader.set(.string("AXStandardWindowTextArea"), for: .subrole, on: focusedElement)
        reader.set(.string("Can we deploy it after review?"), for: .value, on: focusedElement)
        reader.set(.textRange(AXTextRange(location: 7, length: 9)), for: .selectedTextRange, on: focusedElement)
        let client = AXClient(reader: reader)

        let result = try client.focusedElement()

        XCTAssertEqual(result.element, focusedElement)
        XCTAssertEqual(result.role, "AXTextArea")
        XCTAssertEqual(result.subrole, "AXStandardWindowTextArea")
        XCTAssertEqual(result.value, "Can we deploy it after review?")
        XCTAssertEqual(result.selectedRange, AXTextRange(location: 7, length: 9))
        XCTAssertNil(result.frame)
        XCTAssertEqual(
            reader.requests.map(\.attribute),
            [.focusedUIElement, .role, .subrole, .value, .selectedTextRange, .position]
        )
    }

    func testFocusedElementReadsFrameFromPositionAndSize() throws {
        let systemWideNode = FakeAXNode()
        let focusedNode = FakeAXNode()
        let systemWideElement = AXElement(systemWideNode)
        let focusedElement = AXElement(focusedNode)
        let reader = FakeAXAttributeReader(systemWideElement: systemWideElement)
        let converter = FakeAXCoordinateConverter(
            convertedRect: CGRect(x: 20, y: 616, width: 420, height: 44)
        )
        reader.set(.element(focusedElement), for: .focusedUIElement, on: systemWideElement)
        reader.set(.string("AXTextArea"), for: .role, on: focusedElement)
        reader.set(.string("Text"), for: .value, on: focusedElement)
        reader.set(.point(CGPoint(x: 20, y: 100)), for: .position, on: focusedElement)
        reader.set(.size(CGSize(width: 420, height: 44)), for: .size, on: focusedElement)
        let client = AXClient(reader: reader, coordinateConverter: converter)

        let result = try client.focusedElement()

        XCTAssertEqual(result.frame, CGRect(x: 20, y: 616, width: 420, height: 44))
        XCTAssertEqual(converter.rawRects, [CGRect(x: 20, y: 100, width: 420, height: 44)])
        XCTAssertEqual(
            reader.requests.map(\.attribute),
            [.focusedUIElement, .role, .subrole, .value, .selectedTextRange, .position, .size]
        )
    }

    func testFocusedElementKeepsOptionalAttributesNilWhenReadsFail() throws {
        let systemWideElement = AXElement(FakeAXNode())
        let focusedElement = AXElement(FakeAXNode())
        let reader = FakeAXAttributeReader(systemWideElement: systemWideElement)
        reader.set(.element(focusedElement), for: .focusedUIElement, on: systemWideElement)
        let client = AXClient(reader: reader)

        let result = try client.focusedElement()

        XCTAssertEqual(result.element, focusedElement)
        XCTAssertNil(result.role)
        XCTAssertNil(result.subrole)
        XCTAssertNil(result.value)
        XCTAssertNil(result.selectedRange)
    }

    func testFocusedElementThrowsWhenFocusedUIElementCannotBeRead() {
        let systemWideElement = AXElement(FakeAXNode())
        let reader = FakeAXAttributeReader(systemWideElement: systemWideElement)
        reader.fail(.attributeUnavailable(attribute: AXAttribute.focusedUIElement.name, code: -25205), for: .focusedUIElement, on: systemWideElement)
        let client = AXClient(reader: reader)

        XCTAssertThrowsError(try client.focusedElement()) { error in
            XCTAssertEqual(
                error as? AXClientError,
                .attributeUnavailable(attribute: AXAttribute.focusedUIElement.name, code: -25205)
            )
        }
    }

    func testFocusedElementThrowsWhenFocusedUIElementHasUnexpectedType() {
        let systemWideElement = AXElement(FakeAXNode())
        let reader = FakeAXAttributeReader(systemWideElement: systemWideElement)
        reader.set(.string("not an element"), for: .focusedUIElement, on: systemWideElement)
        let client = AXClient(reader: reader)

        XCTAssertThrowsError(try client.focusedElement()) { error in
            XCTAssertEqual(
                error as? AXClientError,
                .invalidAttributeType(attribute: AXAttribute.focusedUIElement.name, expected: "AXUIElement")
            )
        }
    }
}

final class SystemAXCoordinateConverterTests: XCTestCase {
    func testConvertsTopLeftAXRectOnPrimaryScreenToAppKitRect() {
        let rect = SystemAXCoordinateConverter.appKitRect(
            fromAXTopLeftRect: CGRect(x: 20, y: 900, width: 420, height: 44),
            screenFrames: [
                CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
            ]
        )

        XCTAssertEqual(rect, CGRect(x: 20, y: 136, width: 420, height: 44))
    }

    func testUsesPrimaryScreenTopWhenAnotherDisplayExtendsAboveIt() {
        let rect = SystemAXCoordinateConverter.appKitRect(
            fromAXTopLeftRect: CGRect(x: 20, y: 900, width: 420, height: 44),
            screenFrames: [
                CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
                CGRect(x: -1_080, y: -410, width: 1_080, height: 1_920)
            ]
        )

        XCTAssertEqual(rect, CGRect(x: 20, y: 136, width: 420, height: 44))
    }
}

private final class FakeAXNode: NSObject {}

private final class FakeAXCoordinateConverter: AXCoordinateConverting {
    private let convertedRect: CGRect
    private(set) var rawRects: [CGRect] = []

    init(convertedRect: CGRect) {
        self.convertedRect = convertedRect
    }

    func appKitRect(fromAXTopLeftRect rect: CGRect) -> CGRect {
        rawRects.append(rect)
        return convertedRect
    }
}

private final class FakeAXAttributeReader: AXAttributeReading {
    struct Request: Equatable {
        var element: AXElement
        var attribute: AXAttribute
    }

    private struct AttributeKey: Hashable {
        var element: AXElement
        var attribute: AXAttribute
    }

    private let systemWideElementValue: AXElement
    private var values: [AttributeKey: Result<AXAttributePayload, AXClientError>] = [:]
    private(set) var requests: [Request] = []

    init(systemWideElement: AXElement) {
        self.systemWideElementValue = systemWideElement
    }

    func systemWideElement() -> AXElement {
        systemWideElementValue
    }

    func copyAttribute(_ attribute: AXAttribute, from element: AXElement) -> Result<AXAttributePayload, AXClientError> {
        requests.append(Request(element: element, attribute: attribute))

        return values[AttributeKey(element: element, attribute: attribute)]
            ?? .failure(.attributeUnavailable(attribute: attribute.name, code: -25205))
    }

    func set(_ value: AXAttributePayload, for attribute: AXAttribute, on element: AXElement) {
        values[AttributeKey(element: element, attribute: attribute)] = .success(value)
    }

    func fail(_ error: AXClientError, for attribute: AXAttribute, on element: AXElement) {
        values[AttributeKey(element: element, attribute: attribute)] = .failure(error)
    }
}
