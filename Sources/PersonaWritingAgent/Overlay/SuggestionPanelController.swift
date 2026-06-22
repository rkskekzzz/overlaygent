import AppKit
import Foundation
import QuartzCore
import SwiftUI

final class SuggestionPanelController: NSObject, SuggestionPanelPresenting {
    let preferredContentSize = AgentStatusOverlayLayout.preferredContentSize

    private var hostingController: NSHostingController<AnyView>?
    private lazy var contentContainer = GlassPanelContainerView(cornerRadius: 22)
    private lazy var panel: NSPanel = makePanel()

    func setPlaceholder(title: String, detail: String) {
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
        _ suggestions: [AgentSuggestionDisplayModel],
        onApply: @escaping (AgentSuggestionDisplayModel) -> Bool,
        onDismiss: @escaping (AgentSuggestionDisplayModel?) -> Void
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
        _ suggestions: [AgentSuggestionDisplayModel],
        onApply: @escaping (AgentSuggestionDisplayModel) -> Bool,
        onDismiss: @escaping (AgentSuggestionDisplayModel?) -> Void
    ) {
        guard suggestions.isEmpty == false else {
            setPlaceholder(title: "Agent Suggestions", detail: "No successful suggestions.")
            return
        }

        let pagerView = AgentResultPagerView(
            suggestions: suggestions,
            onApply: { [weak self] suggestion in
                if onApply(suggestion) {
                    self?.hide()
                }
            },
            onDismiss: { [weak self] suggestion in
                onDismiss(suggestion)
                self?.hide()
            }
        )
        installOverlayContent(
            AnyView(pagerView),
            onClose: { [weak self] in
                onDismiss(nil)
                self?.hide()
            }
        )
    }

    func show(frame: CGRect) {
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
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

        contentContainer.frame = CGRect(origin: .zero, size: preferredContentSize)
        panel.contentView = contentContainer
        return panel
    }

    private func installOverlayContent(
        _ content: AnyView,
        onClose: @escaping () -> Void
    ) {
        let rootView = AnyView(
            AgentOverlayShell(onClose: onClose) {
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

private struct AgentOverlayShell<Content: View>: View {
    let onClose: () -> Void
    let content: Content

    init(
        onClose: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.onClose = onClose
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            content
                .frame(
                    width: AgentStatusOverlayLayout.preferredContentSize.width,
                    height: AgentStatusOverlayLayout.preferredContentSize.height
                )

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(GlassIconButtonStyle(size: 24))
            .keyboardShortcut(.cancelAction)
            .help("Close")
            .padding(10)
        }
        .frame(
            width: AgentStatusOverlayLayout.preferredContentSize.width,
            height: AgentStatusOverlayLayout.preferredContentSize.height
        )
        .background(Color.clear)
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
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 240)
                }
            }
        }
        .frame(
            width: AgentStatusOverlayLayout.preferredContentSize.width,
            height: AgentStatusOverlayLayout.preferredContentSize.height,
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
            .frame(width: AgentStatusOverlayLayout.contentWidth, alignment: .topLeading)
        }
        .frame(
            width: AgentStatusOverlayLayout.preferredContentSize.width,
            height: AgentStatusOverlayLayout.preferredContentSize.height,
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
