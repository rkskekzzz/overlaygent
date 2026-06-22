import SwiftUI

struct DashboardCopySection: Identifiable, Equatable {
    var title: String
    var systemImageName: String
    var body: String

    var id: String {
        title
    }
}

struct OnboardingCopy: Equatable {
    var title: String
    var subtitle: String
    var sections: [DashboardCopySection]

    var searchableText: String {
        ([title, subtitle] + sections.flatMap { [$0.title, $0.body] })
            .joined(separator: " ")
    }

    static let dashboard = OnboardingCopy(
        title: "Welcome to Persona Writing Agent",
        subtitle: "A menu bar writing assistant for the text field you are using right now.",
        sections: [
            DashboardCopySection(
                title: "Accessibility Permission",
                systemImageName: "accessibility",
                body: "macOS Accessibility permission lets the app read the current focused input and apply your chosen edit back to that field."
            ),
            DashboardCopySection(
                title: "Current Input Only",
                systemImageName: "text.cursor",
                body: "The app works from the focused editable field through the OS Accessibility API. It does not watch every keystroke and is not a keylogger."
            ),
            DashboardCopySection(
                title: "You Stay in Control",
                systemImageName: "slider.horizontal.3",
                body: "Run agents from the menu bar, choose which apps are enabled, and keep conversation context or clipboard fallback off unless you opt in."
            )
        ]
    )
}

struct OnboardingView: View {
    let copy: OnboardingCopy

    init(copy: OnboardingCopy = .dashboard) {
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
            Label(copy.title, systemImage: "sparkles")
                .font(.title)
                .fontWeight(.semibold)

            Text(copy.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct DashboardCopySectionView: View {
    let section: DashboardCopySection

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: section.systemImageName)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 6) {
                Text(section.title)
                    .font(.headline)

                Text(section.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
