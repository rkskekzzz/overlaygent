import SwiftUI

enum AgentOverlayHeaderLayout {
    static let outerPadding: CGFloat = 14
    static let controlSize: CGFloat = 24
    static let controlSpacing: CGFloat = 6
    static let dragRegionHeight: CGFloat = 46

    static let closeControlReserve = controlSize
    static let pagerControlReserve = (controlSize * 3) + (controlSpacing * 2)
}

@MainActor
final class AgentResultPagerViewModel: ObservableObject {
    @Published private(set) var suggestions: [AgentSuggestion]
    @Published private(set) var currentPageIndex: Int

    init(
        suggestions: [AgentSuggestion],
        initialPageIndex: Int = 0
    ) {
        self.suggestions = suggestions
        self.currentPageIndex = Self.clampedPageIndex(initialPageIndex, suggestionCount: suggestions.count)
    }

    var currentSuggestion: AgentSuggestion? {
        guard suggestions.indices.contains(currentPageIndex) else {
            return nil
        }

        return suggestions[currentPageIndex]
    }

    var currentPageNumber: Int {
        suggestions.isEmpty ? 0 : currentPageIndex + 1
    }

    var pageStatusText: String {
        "\(currentPageNumber) of \(suggestions.count)"
    }

    var canGoPrevious: Bool {
        currentPageIndex > 0
    }

    var canGoNext: Bool {
        currentPageIndex < suggestions.count - 1
    }

    func goToPrevious() {
        guard canGoPrevious else {
            return
        }

        currentPageIndex -= 1
    }

    func goToNext() {
        guard canGoNext else {
            return
        }

        currentPageIndex += 1
    }

    func selectPage(at index: Int) {
        guard suggestions.indices.contains(index) else {
            return
        }

        currentPageIndex = index
    }

    func replaceSuggestions(
        _ suggestions: [AgentSuggestion],
        preferredPageIndex: Int? = nil
    ) {
        self.suggestions = suggestions
        currentPageIndex = Self.clampedPageIndex(
            preferredPageIndex ?? currentPageIndex,
            suggestionCount: suggestions.count
        )
    }

    private static func clampedPageIndex(_ index: Int, suggestionCount: Int) -> Int {
        guard suggestionCount > 0 else {
            return 0
        }

        return min(max(index, 0), suggestionCount - 1)
    }
}

struct AgentResultPagerView: View {
    @StateObject private var viewModel: AgentResultPagerViewModel

    private let onApply: (AgentSuggestion) -> Void

    @MainActor
    init(
        suggestions: [AgentSuggestion],
        initialPageIndex: Int = 0,
        onApply: @escaping (AgentSuggestion) -> Void,
        onDismiss: @escaping (AgentSuggestion?) -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: AgentResultPagerViewModel(
                suggestions: suggestions,
                initialPageIndex: initialPageIndex
            )
        )
        self.onApply = onApply
        _ = onDismiss
    }

    @MainActor
    init(
        viewModel: AgentResultPagerViewModel,
        onApply: @escaping (AgentSuggestion) -> Void,
        onDismiss: @escaping (AgentSuggestion?) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onApply = onApply
        _ = onDismiss
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let suggestion = viewModel.currentSuggestion {
                compactHeader(for: suggestion)

                ScrollView {
                    SuggestionDetailView(suggestion: suggestion)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                actionBar(for: suggestion)
            } else {
                emptyState
            }
        }
        .padding(14)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background(Color.clear)
    }

    private func compactHeader(for suggestion: AgentSuggestion) -> some View {
        HStack(spacing: 8) {
            Text(suggestion.agentName)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)

            if viewModel.suggestions.count > 1 {
                Text(viewModel.pageStatusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
        }
        .frame(height: AgentOverlayHeaderLayout.controlSize, alignment: .center)
        .padding(.trailing, headerControlReserve)
    }

    private var headerControlReserve: CGFloat {
        viewModel.suggestions.count > 1
            ? AgentOverlayHeaderLayout.pagerControlReserve
            : AgentOverlayHeaderLayout.closeControlReserve
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No suggestions", systemImage: "text.badge.xmark")
                .font(.headline)

            Text("Run an active agent to preview edits here.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func actionBar(for suggestion: AgentSuggestion) -> some View {
        HStack(spacing: 8) {
            Spacer()

            Button {
                onApply(suggestion)
            } label: {
                Label("Apply", systemImage: "checkmark")
            }
            .buttonStyle(GlassPrimaryButtonStyle())
            .keyboardShortcut(.return)
        }
    }
}

private struct SuggestionDetailView: View {
    let suggestion: AgentSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let summary = suggestion.summary, summary.isEmpty == false {
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(previewText)
                .font(.system(size: 13))
                .lineSpacing(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.16))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
                )

            if suggestion.edits.isEmpty == false {
                Text("\(suggestion.edits.count) edit\(suggestion.edits.count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var previewText: String {
        if let fullRewrite = suggestion.fullRewrite,
           fullRewrite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return fullRewrite
        }

        if let replacement = suggestion.edits.first?.replacement,
           replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return replacement
        }

        if let summary = suggestion.summary,
           summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return summary
        }

        return "No rewrite returned."
    }
}

struct AgentResultPagerView_Previews: PreviewProvider {
    static var previews: some View {
        AgentResultPagerView(
            suggestions: [
                AgentSuggestion(
                    agentName: "Friendly Rewrite",
                    result: CorrectionResult(
                        summary: "Made the response warmer and easier to read.",
                        edits: [
                            CorrectionEdit(
                                rangeStart: 0,
                                rangeEnd: 13,
                                original: "Ship this now",
                                replacement: "Could we ship this today",
                                reason: "Softens the request without changing intent."
                            )
                        ],
                        fullRewrite: "Could we ship this today after the final review passes?"
                    )
                ),
                AgentSuggestion(
                    agentName: "Concise Reviewer",
                    result: CorrectionResult(
                        summary: "Reduced the wording while keeping the action clear.",
                        edits: [],
                        fullRewrite: "Ship after final review passes."
                    )
                )
            ],
            onApply: { _ in },
            onDismiss: { _ in }
        )
    }
}
