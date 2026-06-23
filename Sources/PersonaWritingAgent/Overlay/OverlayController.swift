import AppKit
import CoreGraphics
import Foundation

enum OverlayAnchorSource: Equatable {
    case caret
    case input
    case fallback
    case defaultScreen
}

struct OverlayResolvedAnchor: Equatable {
    var rect: CGRect
    var source: OverlayAnchorSource
}

struct OverlayAnchorGeometry: Equatable {
    var caretRect: CGRect?
    var inputRect: CGRect?
    var fallbackRect: CGRect?

    init(caretRect: CGRect? = nil, inputRect: CGRect? = nil, fallbackRect: CGRect? = nil) {
        self.caretRect = caretRect
        self.inputRect = inputRect
        self.fallbackRect = fallbackRect
    }

    func resolvedAnchor(in visibleFrame: CGRect) -> OverlayResolvedAnchor {
        let normalizedInputRect = Self.normalized(inputRect)
        if let inputRect = normalizedInputRect,
           Self.isPlausibleInputRect(inputRect, in: visibleFrame) {
            return OverlayResolvedAnchor(rect: inputRect, source: .input)
        }

        if let caretRect = validatedCaretRect() {
            return OverlayResolvedAnchor(rect: caretRect, source: .caret)
        }

        if let fallbackRect = Self.normalized(fallbackRect) {
            return OverlayResolvedAnchor(rect: fallbackRect, source: .fallback)
        }

        return OverlayResolvedAnchor(
            rect: CGRect(x: visibleFrame.midX, y: visibleFrame.midY, width: 1, height: 1),
            source: .defaultScreen
        )
    }

    func preferredScreenRect() -> CGRect? {
        Self.normalized(inputRect)
            ?? validatedCaretRect()
            ?? Self.normalized(fallbackRect)
    }

    private func validatedCaretRect() -> CGRect? {
        guard let caretRect = Self.normalized(caretRect) else {
            return nil
        }

        guard let inputRect = Self.normalized(inputRect) else {
            return caretRect
        }

        let tolerance = max(24, min(max(inputRect.width, inputRect.height) * 0.2, 160))
        let plausibleInputRect = inputRect.insetBy(dx: -tolerance, dy: -tolerance)
        guard plausibleInputRect.intersects(caretRect) || plausibleInputRect.contains(caretRect.origin) else {
            return nil
        }

        return caretRect
    }

    private static func normalized(_ rect: CGRect?) -> CGRect? {
        guard let rect else {
            return nil
        }

        let standardized = rect.standardized
        guard standardized.origin.x.isFinite,
              standardized.origin.y.isFinite,
              standardized.size.width.isFinite,
              standardized.size.height.isFinite,
              standardized.size.width >= 0,
              standardized.size.height >= 0,
              standardized.size.width > 0 || standardized.size.height > 0
        else {
            return nil
        }

        return standardized
    }

    private static func isPlausibleInputRect(_ rect: CGRect, in visibleFrame: CGRect) -> Bool {
        let visibleFrame = visibleFrame.standardized
        guard visibleFrame.width > 0, visibleFrame.height > 0 else {
            return true
        }

        let maxInputHeight = max(120, min(260, visibleFrame.height * 0.36))
        let maxInputWidth = max(320, visibleFrame.width * 0.98)
        let maxInputArea = visibleFrame.width * visibleFrame.height * 0.38
        let rectArea = rect.width * rect.height

        return rect.height <= maxInputHeight
            && rect.width <= maxInputWidth
            && rectArea <= maxInputArea
    }
}

struct OverlayPanelPlacement: Equatable {
    var frame: CGRect
    var anchorSource: OverlayAnchorSource
}

struct OverlayPositioning {
    static let defaultVisibleFrame = CGRect(x: 0, y: 0, width: 1024, height: 768)

    var defaultPanelSize: CGSize
    var spacing: CGFloat
    var screenPadding: CGFloat

    init(
        defaultPanelSize: CGSize = CGSize(width: 360, height: 164),
        spacing: CGFloat = 8,
        screenPadding: CGFloat = 12
    ) {
        self.defaultPanelSize = defaultPanelSize
        self.spacing = spacing
        self.screenPadding = screenPadding
    }

    func placement(
        for anchor: OverlayAnchorGeometry,
        panelSize requestedPanelSize: CGSize? = nil,
        visibleFrame requestedVisibleFrame: CGRect
    ) -> OverlayPanelPlacement {
        let visibleFrame = normalizedVisibleFrame(requestedVisibleFrame)
        let panelSize = clampedPanelSize(requestedPanelSize ?? defaultPanelSize, in: visibleFrame)
        let resolvedAnchor = anchor.resolvedAnchor(in: visibleFrame)

        let xRange = placementRange(
            origin: visibleFrame.minX,
            availableLength: visibleFrame.width,
            itemLength: panelSize.width
        )
        let yRange = placementRange(
            origin: visibleFrame.minY,
            availableLength: visibleFrame.height,
            itemLength: panelSize.height
        )

        let proposedX: CGFloat
        switch resolvedAnchor.source {
        case .input:
            proposedX = resolvedAnchor.rect.minX
        case .caret, .fallback, .defaultScreen:
            proposedX = resolvedAnchor.rect.midX - (panelSize.width / 2)
        }
        let belowY = resolvedAnchor.rect.minY - spacing - panelSize.height
        let aboveY = resolvedAnchor.rect.maxY + spacing
        let proposedY = yRange.contains(aboveY) ? aboveY : belowY

        let frame = CGRect(
            x: clamp(proposedX, to: xRange),
            y: clamp(proposedY, to: yRange),
            width: panelSize.width,
            height: panelSize.height
        )

        return OverlayPanelPlacement(frame: frame, anchorSource: resolvedAnchor.source)
    }

    private func normalizedVisibleFrame(_ frame: CGRect) -> CGRect {
        let standardized = frame.standardized
        guard standardized.origin.x.isFinite,
              standardized.origin.y.isFinite,
              standardized.size.width.isFinite,
              standardized.size.height.isFinite,
              standardized.width > 0,
              standardized.height > 0
        else {
            return Self.defaultVisibleFrame
        }

        return standardized
    }

    private func clampedPanelSize(_ size: CGSize, in visibleFrame: CGRect) -> CGSize {
        let maxWidth = max(1, visibleFrame.width - (screenPadding * 2))
        let maxHeight = max(1, visibleFrame.height - (screenPadding * 2))
        let width = clampedLength(size.width, fallback: defaultPanelSize.width, maximum: maxWidth)
        let height = clampedLength(size.height, fallback: defaultPanelSize.height, maximum: maxHeight)
        return CGSize(width: width, height: height)
    }

    private func clampedLength(_ value: CGFloat, fallback: CGFloat, maximum: CGFloat) -> CGFloat {
        let requested = value.isFinite && value > 0 ? value : fallback
        return min(max(requested, 1), max(maximum, 1))
    }

    private func placementRange(origin: CGFloat, availableLength: CGFloat, itemLength: CGFloat) -> ClosedRange<CGFloat> {
        let remaining = max(0, availableLength - itemLength)
        let padding = min(screenPadding, remaining / 2)
        let lowerBound = origin + padding
        let upperBound = origin + availableLength - itemLength - padding

        if lowerBound <= upperBound {
            return lowerBound...upperBound
        }

        return lowerBound...lowerBound
    }

    private func clamp(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

protocol SuggestionPanelPresenting: AnyObject {
    var preferredContentSize: CGSize { get }

    func setPlaceholder(title: String, detail: String)
    func setSuggestions(
        _ suggestions: [AgentSuggestion],
        onApply: @escaping (AgentSuggestion) -> Bool,
        onDismiss: @escaping (AgentSuggestion?) -> Void
    )
    func show(frame: CGRect)
    func hide()
}

enum AgentSuggestionOverlayLayout {
    static let preferredContentSize = CGSize(width: 420, height: 260)
}

enum AgentStatusOverlayLayout {
    static let preferredContentSize = AgentSuggestionOverlayLayout.preferredContentSize
}

final class OverlayController {
    typealias VisibleFrameProvider = (CGRect?) -> CGRect

    private let panelController: SuggestionPanelPresenting
    private let positioner: OverlayPositioning
    private let visibleFrameProvider: VisibleFrameProvider

    init(
        panelController: SuggestionPanelPresenting = SuggestionPanelController(),
        positioner: OverlayPositioning = OverlayPositioning(),
        visibleFrameProvider: @escaping VisibleFrameProvider = OverlayController.visibleFrame(containing:)
    ) {
        self.panelController = panelController
        self.positioner = positioner
        self.visibleFrameProvider = visibleFrameProvider
    }

    @discardableResult
    func showSuggestion(
        anchor: OverlayAnchorGeometry,
        title: String = "Suggested rewrite",
        detail: String = "Sample correction preview"
    ) -> OverlayPanelPlacement {
        let visibleFrame = visibleFrameProvider(anchor.preferredScreenRect())
        let placement = positioner.placement(
            for: anchor,
            panelSize: panelController.preferredContentSize,
            visibleFrame: visibleFrame
        )

        panelController.setPlaceholder(title: title, detail: detail)
        panelController.show(frame: placement.frame)
        return placement
    }

    func hideSuggestion() {
        panelController.hide()
    }

    @discardableResult
    func showStatus(
        anchor: OverlayAnchorGeometry,
        title: String,
        detail: String
    ) -> OverlayPanelPlacement {
        showSuggestion(anchor: anchor, title: title, detail: detail)
    }

    @discardableResult
    func showSuggestions(
        anchor: OverlayAnchorGeometry,
        suggestions: [AgentSuggestion],
        onApply: @escaping (AgentSuggestion) -> Bool,
        onDismiss: @escaping (AgentSuggestion?) -> Void
    ) -> OverlayPanelPlacement {
        let visibleFrame = visibleFrameProvider(anchor.preferredScreenRect())
        let placement = positioner.placement(
            for: anchor,
            panelSize: panelController.preferredContentSize,
            visibleFrame: visibleFrame
        )

        panelController.setSuggestions(
            suggestions,
            onApply: onApply,
            onDismiss: onDismiss
        )
        panelController.show(frame: placement.frame)
        return placement
    }

    private static func visibleFrame(containing rect: CGRect?) -> CGRect {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return NSScreen.main?.visibleFrame ?? OverlayPositioning.defaultVisibleFrame
        }

        if let rect,
           let screen = screens.first(where: { $0.visibleFrame.intersects(rect) || $0.frame.intersects(rect) }) {
            return screen.visibleFrame
        }

        if let rect {
            let anchorPoint = CGPoint(x: rect.midX, y: rect.midY)
            let nearestScreen = screens.min { lhs, rhs in
                distanceSquared(from: anchorPoint, to: lhs.visibleFrame) < distanceSquared(from: anchorPoint, to: rhs.visibleFrame)
            }

            if let nearestScreen {
                return nearestScreen.visibleFrame
            }
        }

        return NSScreen.main?.visibleFrame ?? screens[0].visibleFrame
    }

    private static func distanceSquared(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx: CGFloat
        if point.x < rect.minX {
            dx = rect.minX - point.x
        } else if point.x > rect.maxX {
            dx = point.x - rect.maxX
        } else {
            dx = 0
        }

        let dy: CGFloat
        if point.y < rect.minY {
            dy = rect.minY - point.y
        } else if point.y > rect.maxY {
            dy = point.y - rect.maxY
        } else {
            dy = 0
        }

        return (dx * dx) + (dy * dy)
    }
}

extension OverlayController: ActiveAgentSuggestionPresenting {}
