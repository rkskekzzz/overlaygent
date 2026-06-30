import SwiftUI

struct PrivacyCopy: Equatable {
    var title: String
    var subtitle: String
    var sections: [DashboardCopySection]

    var searchableText: String {
        ([title, subtitle] + sections.flatMap { [$0.title, $0.body] })
            .joined(separator: " ")
    }

    static let dashboard = PrivacyCopy(
        title: "Privacy",
        subtitle: "Overlaygent keeps correction requests narrow and explicit.",
        sections: [
            DashboardCopySection(
                title: "Protected Fields",
                systemImageName: "lock.shield",
                body: "Secure text fields and password fields are never read. If macOS marks the focused input as private, the run stops before text is sent."
            ),
            DashboardCopySection(
                title: "App Rules",
                systemImageName: "app.badge.checkmark",
                body: "Enable or disable agents per app so writing help only runs in the apps you choose."
            ),
            DashboardCopySection(
                title: "Conversation Context",
                systemImageName: "bubble.left.and.bubble.right",
                body: "Conversation context is opt-in. When enabled, only the configured visible messages are included with the current input."
            ),
            DashboardCopySection(
                title: "Provider Requests",
                systemImageName: "server.rack",
                body: "Your configured third-party LLM provider receives the current input, active agent instructions, selected memory, and any opt-in context. The provider processes that data under its own terms and privacy policy. Your API key is stored separately and is used only for the provider you configure."
            ),
            DashboardCopySection(
                title: "Clipboard Fallback",
                systemImageName: "doc.on.clipboard",
                body: "Clipboard fallback is disabled by default and is only used after explicit opt-in when direct Accessibility edits are not available."
            ),
            DashboardCopySection(
                title: "Response Storage",
                systemImageName: "externaldrive.badge.xmark",
                body: "LLM responses are not cached by default. Overlaygent does not retain correction responses after the current run ends."
            )
        ]
    )
}

struct PrivacyView: View {
    let copy: PrivacyCopy

    init(copy: PrivacyCopy = .dashboard) {
        self.copy = copy
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(copy.sections) { section in
                        DashboardCopySectionView(section: section)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(copy.title, systemImage: "hand.raised")
                .font(.title)
                .fontWeight(.semibold)

            Text(copy.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
