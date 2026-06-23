import Foundation

struct AXClipboardPasteApplier: EditApplier {
    private let element: AXElement
    private let isEnabled: Bool
    private let selectionWriter: AXSelectedTextWriting
    private let focusRestorer: AXTextFocusRestoring
    private let clipboardWriter: ClipboardWriting
    private let pasteEventSender: PasteEventSending
    private let planner: EditApplicationPlanner
    private let focusSettleDelay: TimeInterval
    private let restoreDelay: TimeInterval
    private let sleeper: (TimeInterval) -> Void

    init(
        element: AXElement,
        isEnabled: Bool,
        selectionWriter: AXSelectedTextWriting = SystemAXSelectedTextWriter(),
        focusRestorer: AXTextFocusRestoring = SystemAXTextFocusRestorer(),
        clipboardWriter: ClipboardWriting = SystemClipboardWriter(),
        pasteEventSender: PasteEventSending = SystemPasteEventSender(),
        planner: EditApplicationPlanner = EditApplicationPlanner(),
        focusSettleDelay: TimeInterval = 0.08,
        restoreDelay: TimeInterval = 0.35,
        sleeper: @escaping (TimeInterval) -> Void = Thread.sleep(forTimeInterval:)
    ) {
        self.element = element
        self.isEnabled = isEnabled
        self.selectionWriter = selectionWriter
        self.focusRestorer = focusRestorer
        self.clipboardWriter = clipboardWriter
        self.pasteEventSender = pasteEventSender
        self.planner = planner
        self.focusSettleDelay = focusSettleDelay
        self.restoreDelay = restoreDelay
        self.sleeper = sleeper
    }

    @discardableResult
    func apply(_ edit: CorrectionEdit, to snapshot: TextSnapshot) throws -> EditApplicationPlan {
        guard isEnabled else {
            throw EditApplicationPlanningError.clipboardFallbackNotAllowed
        }

        let plan = try planner.plan(for: edit, in: snapshot)
        let processID = focusRestorer.restoreFocus(to: element)
        if focusSettleDelay > 0 {
            sleeper(focusSettleDelay)
        }

        try selectionWriter.setSelectedTextRange(plan.textRange, on: element)
        let previousClipboard = try clipboardWriter.snapshot()
        do {
            try clipboardWriter.setString(plan.replacement)
            try pasteEventSender.sendPasteEvent(toProcessID: processID)
            if restoreDelay > 0 {
                sleeper(restoreDelay)
            }
            try clipboardWriter.restore(previousClipboard)
        } catch {
            try? clipboardWriter.restore(previousClipboard)
            throw error
        }

        return plan
    }
}
