import Foundation
import AppKit
import XCTest
@testable import PersonaWritingAgent

final class EditApplierTests: XCTestCase {
    func testPlannerBuildsReplacementPlanWhenOriginalMatchesSnapshotRange() throws {
        let snapshot = textSnapshot("I will make deploy when PR approved.")
        let edit = correctionEdit(
            range: 7..<18,
            original: "make deploy",
            replacement: "deploy it"
        )

        let plan = try EditApplicationPlanner().plan(for: edit, in: snapshot)

        XCTAssertEqual(plan.range, 7..<18)
        XCTAssertEqual(plan.original, "make deploy")
        XCTAssertEqual(plan.replacement, "deploy it")
        XCTAssertEqual(plan.resultingText, "I will deploy it when PR approved.")
        XCTAssertEqual(plan.sourceContentHash, snapshot.contentHash)
        XCTAssertEqual(plan.textRange, AXTextRange(location: 7, length: 11))
        XCTAssertTrue(plan.risks.isEmpty)
    }

    func testPlannerUsesCharacterOffsetsForUnicodeText() throws {
        let snapshot = textSnapshot("Hi 👋 there")
        let edit = correctionEdit(
            range: 3..<4,
            original: "👋",
            replacement: "hello"
        )

        let plan = try EditApplicationPlanner().plan(for: edit, in: snapshot)

        XCTAssertEqual(plan.resultingText, "Hi hello there")
        XCTAssertEqual(plan.textRange, AXTextRange(location: 3, length: 1))
    }

    func testPlannerRejectsOutOfBoundsRange() {
        let snapshot = textSnapshot("Short")
        let edit = correctionEdit(
            range: 0..<6,
            original: "Short!",
            replacement: "Longer"
        )

        XCTAssertThrowsError(try EditApplicationPlanner().plan(for: edit, in: snapshot)) { error in
            XCTAssertEqual(
                error as? EditApplicationPlanningError,
                .invalidRange(start: 0, end: 6, textLength: 5)
            )
        }
    }

    func testPlannerRejectsStaleOriginal() {
        let snapshot = textSnapshot("I will deploy it after review.")
        let edit = correctionEdit(
            range: 7..<16,
            original: "make deploy",
            replacement: "deploy"
        )

        XCTAssertThrowsError(try EditApplicationPlanner().plan(for: edit, in: snapshot)) { error in
            XCTAssertEqual(
                error as? EditApplicationPlanningError,
                .staleOriginal(range: 7..<16, expected: "make deploy", actual: "deploy it")
            )
        }
    }

    func testAXSelectedTextApplierSetsRangeBeforeReplacingSelectedText() throws {
        let element = AXElement(FakeAXNode())
        let writer = FakeAXSelectedTextWriter()
        let snapshot = textSnapshot("I will make deploy when PR approved.")
        let edit = correctionEdit(
            range: 7..<18,
            original: "make deploy",
            replacement: "deploy it"
        )
        let applier = AXSelectedTextApplier(
            element: element,
            writer: writer,
            valueReader: FakeAXTextValueReader(value: "I will deploy it when PR approved.")
        )

        let plan = try applier.apply(edit, to: snapshot)

        XCTAssertEqual(plan.resultingText, "I will deploy it when PR approved.")
        XCTAssertEqual(
            writer.calls,
            [
                .setSelectedRange(AXTextRange(location: 7, length: 11), element),
                .replaceSelectedText("deploy it", element)
            ]
        )
    }

    func testAXSelectedTextApplierFailsWhenWriteDoesNotChangeValue() {
        let element = AXElement(FakeAXNode())
        let writer = FakeAXSelectedTextWriter()
        let applier = AXSelectedTextApplier(
            element: element,
            writer: writer,
            valueReader: FakeAXTextValueReader(value: "I will make deploy when PR approved.")
        )

        XCTAssertThrowsError(
            try applier.apply(
                correctionEdit(range: 7..<18, original: "make deploy", replacement: "deploy it"),
                to: textSnapshot("I will make deploy when PR approved.")
            )
        ) { error in
            XCTAssertEqual(
                error as? AXTextWriteError,
                .writeVerificationFailed(
                    expected: "I will deploy it when PR approved.",
                    actual: "I will make deploy when PR approved."
                )
            )
        }
        XCTAssertEqual(
            writer.calls,
            [
                .setSelectedRange(AXTextRange(location: 7, length: 11), element),
                .replaceSelectedText("deploy it", element)
            ]
        )
    }

    func testAXSelectedTextApplierDoesNotWriteWhenEditIsStale() {
        let element = AXElement(FakeAXNode())
        let writer = FakeAXSelectedTextWriter()
        let applier = AXSelectedTextApplier(element: element, writer: writer)
        let snapshot = textSnapshot("Already fixed")
        let edit = correctionEdit(
            range: 0..<7,
            original: "Outdated",
            replacement: "Updated"
        )

        XCTAssertThrowsError(try applier.apply(edit, to: snapshot))
        XCTAssertTrue(writer.calls.isEmpty)
    }

    func testAXValueApplierWritesFullReplacementAndCarriesRiskMetadata() throws {
        let element = AXElement(FakeAXNode())
        let writer = FakeAXValueWriter()
        let snapshot = textSnapshot("Ship when PR approved.")
        let edit = correctionEdit(
            range: 10..<21,
            original: "PR approved",
            replacement: "review passes"
        )
        let applier = AXValueApplier(
            element: element,
            writer: writer,
            valueReader: FakeAXTextValueReader(value: "Ship when review passes.")
        )

        let plan = try applier.apply(edit, to: snapshot)

        XCTAssertEqual(plan.resultingText, "Ship when review passes.")
        XCTAssertEqual(writer.calls, [.setValue("Ship when review passes.", element)])
        XCTAssertEqual(
            plan.risks,
            [.replacesEntireValue, .mayResetUndoStack, .mayMoveCursor, .mayDropRichTextState]
        )
    }

    func testAXClipboardPasteApplierSelectsRangeThenPastesReplacementAndRestoresClipboard() throws {
        let element = AXElement(FakeAXNode())
        let selectionWriter = FakeAXSelectedTextWriter()
        let recorder = ClipboardCallRecorder()
        let clipboardWriter = FakeClipboardWriter(
            recorder: recorder,
            snapshotValue: ClipboardSnapshot(string: "previous clipboard")
        )
        let focusRestorer = FakeAXTextFocusRestorer(recorder: recorder, processID: 42)
        let pasteEventSender = FakePasteEventSender(recorder: recorder)
        let applier = AXClipboardPasteApplier(
            element: element,
            isEnabled: true,
            selectionWriter: selectionWriter,
            focusRestorer: focusRestorer,
            clipboardWriter: clipboardWriter,
            pasteEventSender: pasteEventSender,
            focusSettleDelay: 0,
            restoreDelay: 0
        )

        let plan = try applier.apply(
            correctionEdit(range: 7..<18, original: "make deploy", replacement: "deploy it"),
            to: textSnapshot("I will make deploy when PR approved.")
        )

        XCTAssertEqual(plan.resultingText, "I will deploy it when PR approved.")
        XCTAssertEqual(selectionWriter.calls, [.setSelectedRange(AXTextRange(location: 7, length: 11), element)])
        XCTAssertEqual(
            recorder.calls,
            [
                .snapshot,
                .setString("deploy it"),
                .restoreFocus(element),
                .sendPasteEvent(processID: 42),
                .restore(ClipboardSnapshot(string: "previous clipboard"))
            ]
        )
    }

    func testClipboardPasteApplierRequiresExplicitOptIn() {
        let recorder = ClipboardCallRecorder()
        let clipboardWriter = FakeClipboardWriter(recorder: recorder)
        let pasteEventSender = FakePasteEventSender(recorder: recorder)
        let applier = ClipboardPasteApplier(
            isEnabled: false,
            clipboardWriter: clipboardWriter,
            pasteEventSender: pasteEventSender
        )

        XCTAssertThrowsError(
            try applier.apply(
                correctionEdit(range: 0..<4, original: "Make", replacement: "Ship"),
                to: textSnapshot("Make it")
            )
        ) { error in
            XCTAssertEqual(error as? EditApplicationPlanningError, .clipboardFallbackNotAllowed)
        }
        XCTAssertTrue(recorder.calls.isEmpty)
    }

    func testClipboardPasteApplierWritesReplacementSendsPasteAndRestoresClipboard() throws {
        let recorder = ClipboardCallRecorder()
        let clipboardWriter = FakeClipboardWriter(
            recorder: recorder,
            snapshotValue: ClipboardSnapshot(string: "previous clipboard")
        )
        let pasteEventSender = FakePasteEventSender(recorder: recorder)
        let applier = ClipboardPasteApplier(
            isEnabled: true,
            clipboardWriter: clipboardWriter,
            pasteEventSender: pasteEventSender
        )

        let plan = try applier.apply(
            correctionEdit(range: 7..<18, original: "make deploy", replacement: "deploy it"),
            to: textSnapshot("I will make deploy when PR approved.")
        )

        XCTAssertEqual(plan.resultingText, "I will deploy it when PR approved.")
        XCTAssertEqual(
            recorder.calls,
            [
                .snapshot,
                .setString("deploy it"),
                .sendPasteEvent(processID: nil),
                .restore(ClipboardSnapshot(string: "previous clipboard"))
            ]
        )
    }

    func testClipboardPasteApplierRestoresClipboardWhenPasteEventFails() {
        let recorder = ClipboardCallRecorder()
        let clipboardWriter = FakeClipboardWriter(
            recorder: recorder,
            snapshotValue: ClipboardSnapshot(string: "previous clipboard")
        )
        let pasteEventSender = FakePasteEventSender(
            recorder: recorder,
            error: ClipboardPasteError.eventCreationFailed
        )
        let applier = ClipboardPasteApplier(
            isEnabled: true,
            clipboardWriter: clipboardWriter,
            pasteEventSender: pasteEventSender
        )

        XCTAssertThrowsError(
            try applier.apply(
                correctionEdit(range: 0..<4, original: "Make", replacement: "Ship"),
                to: textSnapshot("Make it")
            )
        ) { error in
            XCTAssertEqual(error as? ClipboardPasteError, .eventCreationFailed)
        }
        XCTAssertEqual(
            recorder.calls,
            [
                .snapshot,
                .setString("Ship"),
                .sendPasteEvent(processID: nil),
                .restore(ClipboardSnapshot(string: "previous clipboard"))
            ]
        )
    }

    func testSystemClipboardWriterRestoresAllPasteboardItemTypes() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PersonaWritingAgentTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        let writer = SystemClipboardWriter(pasteboard: pasteboard)
        let item = NSPasteboardItem()
        let plainTextData = try XCTUnwrap("previous clipboard".data(using: .utf8))
        let customData = Data([0x01, 0x02, 0x03])
        item.setData(plainTextData, forType: .string)
        item.setData(customData, forType: NSPasteboard.PasteboardType("com.example.custom"))
        XCTAssertTrue(pasteboard.writeObjects([item]))

        let snapshot = try writer.snapshot()
        try writer.setString("temporary replacement")
        try writer.restore(snapshot)

        let restoredItem = try XCTUnwrap(pasteboard.pasteboardItems?.first)
        XCTAssertEqual(restoredItem.data(forType: .string), plainTextData)
        XCTAssertEqual(restoredItem.data(forType: NSPasteboard.PasteboardType("com.example.custom")), customData)
    }

    private func textSnapshot(_ text: String) -> TextSnapshot {
        TextSnapshot(
            text: text,
            selectedRange: nil,
            sourceBundleID: "com.example.editor",
            sourceElementRole: "AXTextArea",
            contentHash: "sha256:test"
        )
    }

    private func correctionEdit(
        range: Range<Int>,
        original: String,
        replacement: String
    ) -> CorrectionEdit {
        CorrectionEdit(
            rangeStart: range.lowerBound,
            rangeEnd: range.upperBound,
            original: original,
            replacement: replacement,
            reason: "test"
        )
    }
}

private final class FakeAXNode: NSObject {}

private final class FakeAXSelectedTextWriter: AXSelectedTextWriting {
    enum Call: Equatable {
        case setSelectedRange(AXTextRange, AXElement)
        case replaceSelectedText(String, AXElement)
    }

    private(set) var calls: [Call] = []

    func setSelectedTextRange(_ range: AXTextRange, on element: AXElement) throws {
        calls.append(.setSelectedRange(range, element))
    }

    func replaceSelectedText(with replacement: String, on element: AXElement) throws {
        calls.append(.replaceSelectedText(replacement, element))
    }
}

private final class FakeAXValueWriter: AXValueWriting {
    enum Call: Equatable {
        case setValue(String, AXElement)
    }

    private(set) var calls: [Call] = []

    func setValue(_ value: String, on element: AXElement) throws {
        calls.append(.setValue(value, element))
    }
}

private struct FakeAXTextValueReader: AXTextValueReading {
    var value: String?

    func value(on element: AXElement) throws -> String? {
        value
    }
}

private final class ClipboardCallRecorder {
    enum Call: Equatable {
        case snapshot
        case setString(String)
        case restoreFocus(AXElement)
        case sendPasteEvent(processID: pid_t?)
        case restore(ClipboardSnapshot)
    }

    var calls: [Call] = []
}

private final class FakeClipboardWriter: ClipboardWriting {
    private let recorder: ClipboardCallRecorder
    private let snapshotValue: ClipboardSnapshot

    init(
        recorder: ClipboardCallRecorder,
        snapshotValue: ClipboardSnapshot = ClipboardSnapshot(string: nil)
    ) {
        self.recorder = recorder
        self.snapshotValue = snapshotValue
    }

    func snapshot() throws -> ClipboardSnapshot {
        recorder.calls.append(.snapshot)
        return snapshotValue
    }

    func setString(_ string: String) throws {
        recorder.calls.append(.setString(string))
    }

    func restore(_ snapshot: ClipboardSnapshot) throws {
        recorder.calls.append(.restore(snapshot))
    }
}

private final class FakePasteEventSender: PasteEventSending {
    private let recorder: ClipboardCallRecorder
    private let error: Error?

    init(recorder: ClipboardCallRecorder, error: Error? = nil) {
        self.recorder = recorder
        self.error = error
    }

    func sendPasteEvent(toProcessID processID: pid_t?) throws {
        recorder.calls.append(.sendPasteEvent(processID: processID))

        if let error {
            throw error
        }
    }
}

private final class FakeAXTextFocusRestorer: AXTextFocusRestoring {
    private let recorder: ClipboardCallRecorder
    private let processID: pid_t?

    init(recorder: ClipboardCallRecorder, processID: pid_t?) {
        self.recorder = recorder
        self.processID = processID
    }

    func restoreFocus(to element: AXElement) -> pid_t? {
        recorder.calls.append(.restoreFocus(element))
        return processID
    }
}
