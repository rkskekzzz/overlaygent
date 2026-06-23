import ApplicationServices
import Foundation

protocol AXSelectedTextWriting {
    func setSelectedTextRange(_ range: AXTextRange, on element: AXElement) throws
    func replaceSelectedText(with replacement: String, on element: AXElement) throws
}

protocol AXTextValueReading {
    func value(on element: AXElement) throws -> String?
}

struct AXSelectedTextApplier: EditApplier {
    private let element: AXElement
    private let writer: AXSelectedTextWriting
    private let valueReader: (any AXTextValueReading)?
    private let focusRestorer: (any AXTextFocusRestoring)?
    private let planner: EditApplicationPlanner
    private let focusSettleDelay: TimeInterval
    private let sleeper: (TimeInterval) -> Void

    init(
        element: AXElement,
        writer: AXSelectedTextWriting = SystemAXSelectedTextWriter(),
        valueReader: (any AXTextValueReading)? = SystemAXTextValueReader(),
        focusRestorer: (any AXTextFocusRestoring)? = SystemAXTextFocusRestorer(),
        planner: EditApplicationPlanner = EditApplicationPlanner(),
        focusSettleDelay: TimeInterval = 0.08,
        sleeper: @escaping (TimeInterval) -> Void = Thread.sleep(forTimeInterval:)
    ) {
        self.element = element
        self.writer = writer
        self.valueReader = valueReader
        self.focusRestorer = focusRestorer
        self.planner = planner
        self.focusSettleDelay = focusSettleDelay
        self.sleeper = sleeper
    }

    @discardableResult
    func apply(_ edit: CorrectionEdit, to snapshot: TextSnapshot) throws -> EditApplicationPlan {
        let plan = try planner.plan(for: edit, in: snapshot)

        restoreFocusIfPossible()
        try writer.setSelectedTextRange(plan.textRange, on: element)
        try writer.replaceSelectedText(with: plan.replacement, on: element)
        try verifyAppliedPlan(plan)

        return plan
    }

    private func restoreFocusIfPossible() {
        guard let processID = focusRestorer?.restoreFocus(to: element),
              processID > 0,
              focusSettleDelay > 0 else {
            return
        }

        sleeper(focusSettleDelay)
    }

    private func verifyAppliedPlan(_ plan: EditApplicationPlan) throws {
        guard let valueReader else {
            return
        }

        guard let actualValue = try valueReader.value(on: element) else {
            throw AXTextWriteError.writeVerificationFailed(expected: plan.resultingText, actual: nil)
        }

        guard actualValue == plan.resultingText else {
            throw AXTextWriteError.writeVerificationFailed(expected: plan.resultingText, actual: actualValue)
        }
    }
}

enum AXTextWriteError: Error, Equatable {
    case invalidElement
    case invalidRange
    case setAttributeFailed(attribute: String, code: Int32)
    case writeVerificationFailed(expected: String, actual: String?)
}

struct SystemAXSelectedTextWriter: AXSelectedTextWriting {
    func setSelectedTextRange(_ range: AXTextRange, on element: AXElement) throws {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
            throw AXTextWriteError.invalidRange
        }

        try setAttribute(
            kAXSelectedTextRangeAttribute as String,
            value: rangeValue,
            on: element
        )
    }

    func replaceSelectedText(with replacement: String, on element: AXElement) throws {
        try setAttribute(
            kAXSelectedTextAttribute as String,
            value: replacement as CFString,
            on: element
        )
    }

    private func setAttribute(_ attribute: String, value: CFTypeRef, on element: AXElement) throws {
        guard CFGetTypeID(element.rawValue) == AXUIElementGetTypeID() else {
            throw AXTextWriteError.invalidElement
        }

        let axElement = unsafeBitCast(element.rawValue, to: AXUIElement.self)
        let error = AXUIElementSetAttributeValue(axElement, attribute as CFString, value)

        guard error == .success else {
            throw AXTextWriteError.setAttributeFailed(attribute: attribute, code: error.rawValue)
        }
    }
}

struct SystemAXTextValueReader: AXTextValueReading {
    func value(on element: AXElement) throws -> String? {
        guard CFGetTypeID(element.rawValue) == AXUIElementGetTypeID() else {
            throw AXTextWriteError.invalidElement
        }

        let axElement = unsafeBitCast(element.rawValue, to: AXUIElement.self)
        var result: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            axElement,
            kAXValueAttribute as CFString,
            &result
        )

        switch error {
        case .success:
            return result as? String
        case .attributeUnsupported, .noValue:
            return nil
        default:
            throw AXTextWriteError.setAttributeFailed(
                attribute: kAXValueAttribute as String,
                code: error.rawValue
            )
        }
    }
}
