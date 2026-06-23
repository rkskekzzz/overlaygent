import Foundation

protocol EditApplier {
    @discardableResult
    func apply(_ edit: CorrectionEdit, to snapshot: TextSnapshot) throws -> EditApplicationPlan
}

extension EditApplier {
    @discardableResult
    func apply(_ edits: [CorrectionEdit], to snapshot: TextSnapshot) throws -> [EditApplicationPlan] {
        var currentSnapshot = snapshot
        var plans: [EditApplicationPlan] = []

        for edit in edits {
            let plan = try apply(edit, to: currentSnapshot)
            plans.append(plan)
            currentSnapshot.text = plan.resultingText
        }

        return plans
    }
}

enum EditApplicationPlanningError: Error, Equatable, CustomStringConvertible {
    case invalidRange(start: Int, end: Int, textLength: Int)
    case staleOriginal(range: Range<Int>, expected: String, actual: String)
    case clipboardFallbackNotAllowed

    var description: String {
        switch self {
        case let .invalidRange(start, end, textLength):
            return "Edit range \(start)..<\(end) is outside snapshot text length \(textLength)"
        case let .staleOriginal(range, expected, actual):
            return "Edit original is stale for range \(range): expected \(expected), found \(actual)"
        case .clipboardFallbackNotAllowed:
            return "Clipboard paste fallback is not enabled"
        }
    }
}

enum EditApplicationRisk: String, Equatable {
    case replacesEntireValue
    case mayResetUndoStack
    case mayMoveCursor
    case mayDropRichTextState
}

struct EditApplicationPlan: Equatable {
    var range: Range<Int>
    var original: String
    var replacement: String
    var resultingText: String
    var sourceContentHash: String
    var risks: [EditApplicationRisk]

    var textRange: AXTextRange {
        AXTextRange(location: range.lowerBound, length: range.upperBound - range.lowerBound)
    }
}

struct EditApplicationPlanner {
    func plan(
        for edit: CorrectionEdit,
        in snapshot: TextSnapshot,
        risks: [EditApplicationRisk] = []
    ) throws -> EditApplicationPlan {
        let textLength = snapshot.text.count
        guard edit.rangeStart >= 0,
              edit.rangeEnd >= edit.rangeStart,
              edit.rangeEnd <= textLength
        else {
            throw EditApplicationPlanningError.invalidRange(
                start: edit.rangeStart,
                end: edit.rangeEnd,
                textLength: textLength
            )
        }

        let lowerBound = snapshot.text.index(snapshot.text.startIndex, offsetBy: edit.rangeStart)
        let upperBound = snapshot.text.index(snapshot.text.startIndex, offsetBy: edit.rangeEnd)
        let currentOriginal = String(snapshot.text[lowerBound..<upperBound])

        guard currentOriginal == edit.original else {
            throw EditApplicationPlanningError.staleOriginal(
                range: edit.range,
                expected: edit.original,
                actual: currentOriginal
            )
        }

        let resultingText = String(snapshot.text[..<lowerBound])
            + edit.replacement
            + String(snapshot.text[upperBound...])

        return EditApplicationPlan(
            range: edit.range,
            original: edit.original,
            replacement: edit.replacement,
            resultingText: resultingText,
            sourceContentHash: snapshot.contentHash,
            risks: risks
        )
    }
}
