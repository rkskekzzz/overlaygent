import ApplicationServices
import Foundation

protocol AXValueWriting {
    func setValue(_ value: String, on element: AXElement) throws
}

struct AXValueApplier: EditApplier {
    private let element: AXElement
    private let writer: AXValueWriting
    private let valueReader: (any AXTextValueReading)?
    private let focusRestorer: (any AXTextFocusRestoring)?
    private let planner: EditApplicationPlanner
    private let focusSettleDelay: TimeInterval
    private let sleeper: (TimeInterval) -> Void

    init(
        element: AXElement,
        writer: AXValueWriting = SystemAXValueWriter(),
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
        let plan = try planner.plan(
            for: edit,
            in: snapshot,
            risks: [
                .replacesEntireValue,
                .mayResetUndoStack,
                .mayMoveCursor,
                .mayDropRichTextState
            ]
        )

        restoreFocusIfPossible()
        try writer.setValue(plan.resultingText, on: element)
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

struct SystemAXValueWriter: AXValueWriting {
    func setValue(_ value: String, on element: AXElement) throws {
        guard CFGetTypeID(element.rawValue) == AXUIElementGetTypeID() else {
            throw AXTextWriteError.invalidElement
        }

        let axElement = unsafeBitCast(element.rawValue, to: AXUIElement.self)
        let error = AXUIElementSetAttributeValue(
            axElement,
            kAXValueAttribute as CFString,
            value as CFString
        )

        guard error == .success else {
            throw AXTextWriteError.setAttributeFailed(
                attribute: kAXValueAttribute as String,
                code: error.rawValue
            )
        }
    }
}
