import AppKit
import Carbon
import Foundation
import QuartzCore
import SwiftUI

final class SuggestionPanelController: NSObject, SuggestionPanelPresenting {
    let preferredContentSize = AgentStatusOverlayLayout.preferredContentSize

    private var hostingController: NSHostingController<AnyView>?
    private lazy var contentContainer = GlassPanelContainerView(cornerRadius: 22)
    private lazy var panel: NSPanel = makePanel()
    private var keyboardMonitor: Any?
    private var suggestionKeyboardHandler: (@MainActor (AgentSuggestionOverlayKeyboardAction) -> Bool)?

    func setPlaceholder(title: String, detail: String) {
        removeSuggestionKeyboardMonitor()

        let content: AnyView
        if title == "Running agents" {
            content = AnyView(AgentThinkingOverlayContent(detail: detail))
        } else {
            content = AnyView(AgentStatusOverlayContent(title: title, detail: detail))
        }

        installOverlayContent(content, onClose: { [weak self] in
            self?.hide()
        })
    }

    func setSuggestions(
        _ suggestions: [AgentSuggestion],
        onApply: @escaping (AgentSuggestion) -> Bool,
        onDismiss: @escaping (AgentSuggestion?) -> Void
    ) {
        MainActor.assumeIsolated {
            setSuggestionsOnMain(
                suggestions,
                onApply: onApply,
                onDismiss: onDismiss
            )
        }
    }

    @MainActor
    private func setSuggestionsOnMain(
        _ suggestions: [AgentSuggestion],
        onApply: @escaping (AgentSuggestion) -> Bool,
        onDismiss: @escaping (AgentSuggestion?) -> Void
    ) {
        guard suggestions.isEmpty == false else {
            setPlaceholder(title: "Agent Suggestions", detail: "No successful suggestions.")
            return
        }

        let pagerViewModel = AgentResultPagerViewModel(suggestions: suggestions)
        let applySuggestion: (AgentSuggestion) -> Void = { [weak self] suggestion in
            if onApply(suggestion) {
                self?.hide()
            }
        }
        let dismissSuggestion: (AgentSuggestion?) -> Void = { [weak self] suggestion in
            onDismiss(suggestion)
            self?.hide()
        }
        let pagerView = AgentResultPagerView(
            viewModel: pagerViewModel,
            onApply: applySuggestion,
            onDismiss: dismissSuggestion
        )
        installSuggestionKeyboardMonitor(
            viewModel: pagerViewModel,
            onApply: applySuggestion,
            onDismiss: dismissSuggestion
        )
        installOverlayContent(
            AnyView(pagerView),
            onClose: {
                dismissSuggestion(nil)
            },
            toolbarContent: {
                AgentResultPagerNavigationControls(viewModel: pagerViewModel)
            }
        )
    }

    func show(frame: CGRect) {
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        if suggestionKeyboardHandler != nil {
            panel.makeKey()
        }
    }

    func hide() {
        removeSuggestionKeyboardMonitor()
        panel.orderOut(nil)
    }

    @MainActor
    private func installSuggestionKeyboardMonitor(
        viewModel: AgentResultPagerViewModel,
        onApply: @escaping (AgentSuggestion) -> Void,
        onDismiss: @escaping (AgentSuggestion?) -> Void
    ) {
        removeSuggestionKeyboardMonitor()
        suggestionKeyboardHandler = { [weak viewModel] action in
            guard let viewModel else {
                return false
            }

            switch action {
            case .previous:
                viewModel.goToPrevious()
            case .next:
                viewModel.goToNext()
            case .apply:
                guard let suggestion = viewModel.currentSuggestion else {
                    return true
                }
                onApply(suggestion)
            case .dismiss:
                onDismiss(nil)
            }

            return true
        }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleOverlayKeyDown(event) ?? event
        }
    }

    private func removeSuggestionKeyboardMonitor() {
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
        }

        keyboardMonitor = nil
        suggestionKeyboardHandler = nil
    }

    private func handleOverlayKeyDown(_ event: NSEvent) -> NSEvent? {
        let keyCode = event.keyCode
        let modifierFlags = event.modifierFlags
        let shouldConsume = MainActor.assumeIsolated {
            guard panel.isVisible,
                  panel.isKeyWindow,
                  let action = AgentSuggestionOverlayKeyboardAction.action(
                    forKeyCode: keyCode,
                    modifierFlags: modifierFlags
                  ),
                  let suggestionKeyboardHandler,
                  suggestionKeyboardHandler(action)
            else {
                return false
            }

            return true
        }

        return shouldConsume ? nil : event
    }

    private func makePanel() -> NSPanel {
        let panel = NonActivatingSuggestionPanel(
            contentRect: CGRect(origin: .zero, size: preferredContentSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.001)
        panel.alphaValue = 0.97
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = true

        contentContainer.frame = CGRect(origin: .zero, size: preferredContentSize)
        panel.contentView = contentContainer
        return panel
    }

    private func installOverlayContent(
        _ content: AnyView,
        onClose: @escaping () -> Void
    ) {
        installOverlayContent(
            content,
            onClose: onClose,
            toolbarContent: {
                EmptyView()
            }
        )
    }

    private func installOverlayContent<ToolbarContent: View>(
        _ content: AnyView,
        onClose: @escaping () -> Void,
        @ViewBuilder toolbarContent: () -> ToolbarContent
    ) {
        let rootView = AnyView(
            AgentOverlayShell(
                onClose: onClose,
                toolbarContent: toolbarContent
            ) {
                content
            }
        )

        if let hostingController {
            hostingController.rootView = rootView
            installHostedView(hostingController.view, size: preferredContentSize)
            return
        }

        let hostingController = makeHostingController(rootView: rootView, size: preferredContentSize)
        self.hostingController = hostingController
        installHostedView(hostingController.view, size: preferredContentSize)
    }

    private func makeHostingController(
        rootView: AnyView,
        size: CGSize
    ) -> NSHostingController<AnyView> {
        let hostingController = NSHostingController(rootView: rootView)
        prepareHostedView(hostingController.view, size: size)
        return hostingController
    }

    private func prepareHostedView(_ view: NSView, size: CGSize) {
        view.frame = CGRect(origin: .zero, size: size)
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    private func installHostedView(_ view: NSView, size: CGSize) {
        prepareHostedView(view, size: size)
        contentContainer.frame = CGRect(origin: .zero, size: size)
        contentContainer.installContentView(view)
    }
}

enum AgentSuggestionOverlayKeyboardAction: Equatable {
    case previous
    case next
    case apply
    case dismiss

    static func action(for event: NSEvent) -> AgentSuggestionOverlayKeyboardAction? {
        action(forKeyCode: event.keyCode, modifierFlags: event.modifierFlags)
    }

    static func action(
        forKeyCode keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> AgentSuggestionOverlayKeyboardAction? {
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        guard modifierFlags.intersection(disallowedModifiers).isEmpty else {
            return nil
        }

        switch keyCode {
        case UInt16(kVK_LeftArrow):
            return .previous
        case UInt16(kVK_RightArrow):
            return .next
        case UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter):
            return .apply
        case UInt16(kVK_Escape):
            return .dismiss
        default:
            return nil
        }
    }
}

private final class GlassPanelContainerView: NSView {
    private let cornerRadius: CGFloat
    private let effectView = NSVisualEffectView()
    private let tintView = PassthroughLayerView()
    private let highlightView = PassthroughLayerView()
    private let borderView = PassthroughLayerView()
    private let tintLayer = CAGradientLayer()
    private let highlightLayer = CAGradientLayer()
    private weak var installedContentView: NSView?

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func installContentView(_ view: NSView) {
        if installedContentView !== view {
            installedContentView?.removeFromSuperview()
            addSubview(view, positioned: .below, relativeTo: borderView)
            installedContentView = view
        }

        needsLayout = true
    }

    override func layout() {
        super.layout()

        effectView.frame = bounds
        tintView.frame = bounds
        tintLayer.frame = tintView.bounds
        highlightView.frame = bounds
        highlightLayer.frame = highlightView.bounds
        borderView.frame = bounds
        installedContentView?.frame = bounds

        applyContinuousCorners(to: effectView.layer)
        applyContinuousCorners(to: tintView.layer)
        applyContinuousCorners(to: highlightView.layer)
        applyContinuousCorners(to: borderView.layer)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override var mouseDownCanMoveWindow: Bool {
        true
    }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.masksToBounds = true

        tintView.wantsLayer = true
        tintView.layer?.masksToBounds = true
        tintLayer.colors = [
            NSColor.white.withAlphaComponent(0.24).cgColor,
            NSColor.controlBackgroundColor.withAlphaComponent(0.035).cgColor,
            NSColor.white.withAlphaComponent(0.08).cgColor
        ]
        tintLayer.locations = [0, 0.58, 1]
        tintLayer.startPoint = CGPoint(x: 0, y: 1)
        tintLayer.endPoint = CGPoint(x: 1, y: 0)
        tintView.layer?.addSublayer(tintLayer)

        highlightView.wantsLayer = true
        highlightView.layer?.masksToBounds = true
        highlightLayer.colors = [
            NSColor.white.withAlphaComponent(0.54).cgColor,
            NSColor.white.withAlphaComponent(0.16).cgColor,
            NSColor.clear.cgColor
        ]
        highlightLayer.locations = [0, 0.24, 1]
        highlightLayer.startPoint = CGPoint(x: 0, y: 1)
        highlightLayer.endPoint = CGPoint(x: 1, y: 0)
        highlightView.layer?.addSublayer(highlightLayer)

        borderView.wantsLayer = true
        borderView.layer?.backgroundColor = NSColor.clear.cgColor
        borderView.layer?.borderColor = NSColor.white.withAlphaComponent(0.38).cgColor
        borderView.layer?.borderWidth = 1

        addSubview(effectView)
        addSubview(tintView)
        addSubview(highlightView)
        addSubview(borderView)
    }

    private func applyContinuousCorners(to layer: CALayer?) {
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
    }
}

private final class PassthroughLayerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private struct AgentOverlayShell<Content: View, ToolbarContent: View>: View {
    let onClose: () -> Void
    let toolbarContent: ToolbarContent
    let content: Content

    init(
        onClose: @escaping () -> Void,
        @ViewBuilder toolbarContent: () -> ToolbarContent,
        @ViewBuilder content: () -> Content
    ) {
        self.onClose = onClose
        self.toolbarContent = toolbarContent()
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            WindowDragRegion()
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )

            content
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )

            VStack(spacing: 0) {
                WindowDragRegion()
                    .frame(height: AgentOverlayHeaderLayout.dragRegionHeight)

                Spacer(minLength: 0)
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )

            HStack(spacing: AgentOverlayHeaderLayout.controlSpacing) {
                toolbarContent

                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(GlassIconButtonStyle(size: AgentOverlayHeaderLayout.controlSize))
                .keyboardShortcut(.cancelAction)
                .help("Close")
            }
            .padding(.top, AgentOverlayHeaderLayout.outerPadding)
            .padding(.trailing, AgentOverlayHeaderLayout.outerPadding)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
        .background(Color.clear)
    }
}

private struct AgentResultPagerNavigationControls: View {
    @ObservedObject var viewModel: AgentResultPagerViewModel

    var body: some View {
        if viewModel.suggestions.count > 1 {
            Button {
                viewModel.goToPrevious()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(GlassIconButtonStyle(size: AgentOverlayHeaderLayout.controlSize))
            .disabled(viewModel.canGoPrevious == false)
            .help("Previous suggestion")

            Button {
                viewModel.goToNext()
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(GlassIconButtonStyle(size: AgentOverlayHeaderLayout.controlSize))
            .disabled(viewModel.canGoNext == false)
            .help("Next suggestion")
        }
    }
}

private struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragRegionView {
        WindowDragRegionView()
    }

    func updateNSView(_ nsView: WindowDragRegionView, context: Context) {}
}

private final class WindowDragRegionView: NSView {
    override var mouseDownCanMoveWindow: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

private struct AgentThinkingOverlayContent: View {
    let detail: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                ProgressView()
                    .controlSize(.small)
            }

            VStack(spacing: 4) {
                Text("Thinking...")
                    .font(.system(size: 15, weight: .semibold))

                if detail.isEmpty == false {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .center
        )
        .background(Color.clear)
    }
}

private struct AgentStatusOverlayContent: View {
    let title: String
    let detail: String

    var body: some View {
        VStack {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)

                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 28)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .center
        )
        .background(Color.clear)
    }
}

private final class NonActivatingSuggestionPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}
