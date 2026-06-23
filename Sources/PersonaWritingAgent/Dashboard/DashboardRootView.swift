import SwiftUI

struct DashboardRootView: View {
    @State private var selection: DashboardSection?
    private let dependencies: DashboardDependencies

    init(
        initialSelection: DashboardSection = .general,
        dependencies: DashboardDependencies = .live
    ) {
        self.dependencies = dependencies
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        HStack(spacing: 0) {
            List(DashboardSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImageName)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .frame(width: 220)

            Divider()

            DashboardSectionDetailView(
                section: selection ?? .general,
                dependencies: dependencies
            )
        }
        .frame(minWidth: 720, minHeight: 500)
    }
}

private struct DashboardSectionDetailView: View {
    let section: DashboardSection
    let dependencies: DashboardDependencies

    @ViewBuilder
    var body: some View {
        switch section {
        case .general:
            OnboardingView()
        case .llmProvider:
            ProviderSettingsView(
                store: dependencies.llmProviderStore,
                apiKeyStore: dependencies.apiKeyStore
            )
        case .agents:
            AgentListView(
                store: dependencies.agentProfileStore,
                providerStore: dependencies.llmProviderStore,
                orchestratorSettingsStore: dependencies.orchestratorSettingsStore
            )
        case .privacy:
            PrivacyView()
        case .diagnostics:
            DiagnosticsView()
        case .appRules:
            VStack(alignment: .leading, spacing: 20) {
                Label(section.title, systemImage: section.systemImageName)
                    .font(.title)
                    .fontWeight(.semibold)

                Divider()

                Spacer()
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
