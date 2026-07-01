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
        NavigationSplitView {
            List(DashboardSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImageName)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
        } detail: {
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
                apiKeyStore: dependencies.apiKeyStore,
                chatGPTCredentialStore: dependencies.chatGPTCredentialStore
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
