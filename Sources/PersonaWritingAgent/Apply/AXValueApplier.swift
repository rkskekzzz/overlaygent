import ApplicationServices
import Foundation

protocol AXValueWriting {
    func setValue(_ value: String, on element: AXElement) throws
}

struct AXValueApplier: EditApplier {
    private let element: AXElement
    private let writer: AXValueWriting
    private let valueReader: (any AXTextValueReading)?
    private let planner: EditApplicationPlanner

    init(
        element: AXElement,
        writer: AXValueWriting = SystemAXValueWriter(),
        valueReader: (any AXTextValueReading)? = SystemAXTextValueReader(),
        planner: EditApplicationPlanner = EditApplicationPlanner()
    ) {
        self.element = element
        self.writer = writer
        self.valueReader = valueReader
        self.planner = planner
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

        try writer.setValue(plan.resultingText, on: element)
        try verifyAppliedPlan(plan)

        return plan
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
