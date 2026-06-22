import ApplicationServices
import AppKit
import Foundation

struct ClipboardSnapshot: Equatable {
    struct Item: Equatable {
        var contents: [Content]
    }

    struct Content: Equatable {
        var type: NSPasteboard.PasteboardType
        var data: Data
    }

    var items: [Item]

    init(items: [Item] = []) {
        self.items = items
    }

    init(string: String?) {
        guard let data = string?.data(using: .utf8) else {
            self.items = []
            return
        }

        self.items = [
            Item(contents: [
                Content(type: .string, data: data)
            ])
        ]
    }

    var string: String? {
        for item in items {
            if let content = item.contents.first(where: { $0.type == .string }),
               let string = String(data: content.data, encoding: .utf8) {
                return string
            }
        }

        return nil
    }
}

protocol ClipboardWriting {
    func snapshot() throws -> ClipboardSnapshot
    func setString(_ string: String) throws
    func restore(_ snapshot: ClipboardSnapshot) throws
}

protocol PasteEventSending {
    func sendPasteEvent(toProcessID processID: pid_t?) throws
}

extension PasteEventSending {
    func sendPasteEvent() throws {
        try sendPasteEvent(toProcessID: nil)
    }
}

enum ClipboardPasteError: Error, Equatable {
    case writeFailed
    case restoreFailed
    case eventCreationFailed
}

struct ClipboardPasteApplier: EditApplier {
    private let isEnabled: Bool
    private let clipboardWriter: ClipboardWriting
    private let pasteEventSender: PasteEventSending
    private let planner: EditApplicationPlanner

    init(
        isEnabled: Bool,
        clipboardWriter: ClipboardWriting = SystemClipboardWriter(),
        pasteEventSender: PasteEventSending = SystemPasteEventSender(),
        planner: EditApplicationPlanner = EditApplicationPlanner()
    ) {
        self.isEnabled = isEnabled
        self.clipboardWriter = clipboardWriter
        self.pasteEventSender = pasteEventSender
        self.planner = planner
    }

    @discardableResult
    func apply(_ edit: CorrectionEdit, to snapshot: TextSnapshot) throws -> EditApplicationPlan {
        guard isEnabled else {
            throw EditApplicationPlanningError.clipboardFallbackNotAllowed
        }

        let plan = try planner.plan(for: edit, in: snapshot)
        let previousClipboard = try clipboardWriter.snapshot()

        do {
            try clipboardWriter.setString(plan.replacement)
            try pasteEventSender.sendPasteEvent()
            try clipboardWriter.restore(previousClipboard)
        } catch {
            try? clipboardWriter.restore(previousClipboard)
            throw error
        }

        return plan
    }
}

struct SystemClipboardWriter: ClipboardWriting {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func snapshot() throws -> ClipboardSnapshot {
        let items = pasteboard.pasteboardItems?.map { item in
            ClipboardSnapshot.Item(
                contents: item.types.compactMap { type in
                    guard let data = item.data(forType: type) else {
                        return nil
                    }

                    return ClipboardSnapshot.Content(type: type, data: data)
                }
            )
        }.filter { $0.contents.isEmpty == false } ?? []

        return ClipboardSnapshot(items: items)
    }

    func setString(_ string: String) throws {
        pasteboard.clearContents()
        guard pasteboard.setString(string, forType: .string) else {
            throw ClipboardPasteError.writeFailed
        }
    }

    func restore(_ snapshot: ClipboardSnapshot) throws {
        pasteboard.clearContents()

        guard snapshot.items.isEmpty == false else {
            return
        }

        let pasteboardItems = snapshot.items.map { itemSnapshot in
            let item = NSPasteboardItem()
            for content in itemSnapshot.contents {
                item.setData(content.data, forType: content.type)
            }
            return item
        }

        guard pasteboard.writeObjects(pasteboardItems) else {
            throw ClipboardPasteError.restoreFailed
        }
    }
}

struct SystemPasteEventSender: PasteEventSending {
    private let eventSource: CGEventSource?

    init(eventSource: CGEventSource? = CGEventSource(stateID: .hidSystemState)) {
        self.eventSource = eventSource
    }

    func sendPasteEvent(toProcessID processID: pid_t?) throws {
        guard let keyDown = CGEvent(
            keyboardEventSource: eventSource,
            virtualKey: 0x09,
            keyDown: true
        ), let keyUp = CGEvent(
            keyboardEventSource: eventSource,
            virtualKey: 0x09,
            keyDown: false
        ) else {
            throw ClipboardPasteError.eventCreationFailed
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        if let processID {
            keyDown.postToPid(processID)
            keyUp.postToPid(processID)
        } else {
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
