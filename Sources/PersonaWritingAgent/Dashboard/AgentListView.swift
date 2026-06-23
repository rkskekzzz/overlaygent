import SwiftUI

enum AgentSettingsSelection: Hashable {
    case orchestrator
    case agent(AgentProfile.ID)
}

@MainActor
final class AgentProfileListViewModel: ObservableObject {
    @Published private(set) var profiles: [AgentProfile]
    @Published private(set) var providers: [LLMProviderConfig]
    @Published var orchestratorSettings: OrchestratorSettings
    @Published var selection: AgentSettingsSelection?
    @Published var lastErrorMessage: String?

    private let store: AgentProfileStore
    private let providerStore: LLMProviderStore
    private let orchestratorSettingsStore: OrchestratorSettingsStore

    init(
        store: AgentProfileStore = .defaultStore,
        providerStore: LLMProviderStore = LLMProviderStore(),
        orchestratorSettingsStore: OrchestratorSettingsStore = .defaultStore
    ) {
        self.store = store
        self.providerStore = providerStore
        self.orchestratorSettingsStore = orchestratorSettingsStore

        do {
            let loadedProfiles = try store.loadProfiles()
            self.profiles = loadedProfiles
            self.providers = try providerStore.loadOrCreateDefaultProviders()
            self.orchestratorSettings = try orchestratorSettingsStore.loadSettings()
            self.selection = loadedProfiles.first.map { .agent($0.id) } ?? .orchestrator
        } catch {
            self.profiles = AgentProfileStore.defaultAgents()
            self.providers = [LLMProviderConfig.defaultOpenAICompatible(id: AgentProfileStore.defaultProviderID)]
            self.orchestratorSettings = OrchestratorSettings()
            self.selection = profiles.first.map { .agent($0.id) } ?? .orchestrator
            self.lastErrorMessage = "Failed to load agent settings: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func createProfile() -> AgentProfile.ID {
        let profile = AgentProfileStore.newAgent(providerID: providers.first?.id ?? AgentProfileStore.defaultProviderID)
        profiles.append(profile)
        selection = .agent(profile.id)
        persistProfiles()
        return profile.id
    }

    func reloadExternalSettings() {
        do {
            providers = try providerStore.loadOrCreateDefaultProviders()
            orchestratorSettings = try orchestratorSettingsStore.loadSettings()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Failed to reload agent settings: \(error.localizedDescription)"
        }
    }

    func deleteProfile(id: AgentProfile.ID) {
        profiles.removeAll { $0.id == id }

        if selectedProfileID == id {
            selection = profiles.first.map { .agent($0.id) } ?? .orchestrator
        }

        persistProfiles()
    }

    @discardableResult
    func duplicateProfile(id: AgentProfile.ID) -> AgentProfile.ID? {
        guard let profile = profiles.first(where: { $0.id == id }) else {
            return nil
        }

        let duplicate = AgentProfileStore.duplicate(profile)
        profiles.append(duplicate)
        selection = .agent(duplicate.id)
        persistProfiles()
        return duplicate.id
    }

    func setActive(id: AgentProfile.ID, isActive: Bool) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            return
        }

        profiles[index].isActive = isActive
        persistProfiles()
    }

    func updateProfile(_ profile: AgentProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            return
        }

        profiles[index] = profile
        persistProfiles()
    }

    func binding(for id: AgentProfile.ID) -> Binding<AgentProfile>? {
        guard profiles.contains(where: { $0.id == id }) else {
            return nil
        }

        return Binding(
            get: { [weak self] in
                self?.profiles.first(where: { $0.id == id }) ?? AgentProfileStore.newAgent()
            },
            set: { [weak self] updatedProfile in
                self?.updateProfile(updatedProfile)
            }
        )
    }

    var selectedProfileBinding: Binding<AgentProfile>? {
        guard let selectedProfileID else {
            return nil
        }

        return binding(for: selectedProfileID)
    }

    var selectedProfile: AgentProfile? {
        guard let selectedProfileID else {
            return nil
        }

        return profiles.first { $0.id == selectedProfileID }
    }

    var selectedProfileID: AgentProfile.ID? {
        guard case .agent(let id) = selection else {
            return nil
        }

        return id
    }

    var orchestratorSettingsBinding: Binding<OrchestratorSettings> {
        Binding(
            get: { [weak self] in
                self?.orchestratorSettings ?? OrchestratorSettings()
            },
            set: { [weak self] updatedSettings in
                let normalizedSettings = OrchestratorSettings(
                    id: updatedSettings.id,
                    name: updatedSettings.name,
                    description: updatedSettings.description,
                    maximumSelectedAgents: updatedSettings.maximumSelectedAgents
                )
                self?.orchestratorSettings = normalizedSettings
                self?.persistOrchestratorSettings()
            }
        )
    }

    private func persistProfiles() {
        do {
            try store.saveProfiles(profiles)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Failed to save agents: \(error.localizedDescription)"
        }
    }

    private func persistOrchestratorSettings() {
        do {
            try orchestratorSettingsStore.saveSettings(orchestratorSettings)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Failed to save orchestrator settings: \(error.localizedDescription)"
        }
    }
}

struct AgentListView: View {
    @StateObject private var viewModel: AgentProfileListViewModel
    @State private var path: [AgentSettingsSelection] = []

    @MainActor
    init() {
        _viewModel = StateObject(wrappedValue: AgentProfileListViewModel())
    }

    @MainActor
    init(store: AgentProfileStore) {
        _viewModel = StateObject(wrappedValue: AgentProfileListViewModel(store: store))
    }

    @MainActor
    init(
        store: AgentProfileStore,
        providerStore: LLMProviderStore,
        orchestratorSettingsStore: OrchestratorSettingsStore
    ) {
        _viewModel = StateObject(
            wrappedValue: AgentProfileListViewModel(
                store: store,
                providerStore: providerStore,
                orchestratorSettingsStore: orchestratorSettingsStore
            )
        )
    }

    @MainActor
    init(viewModel: AgentProfileListViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack(path: $path) {
            overview
                .toolbar {
                    ToolbarItem {
                        Button {
                            createAndOpenAgent()
                        } label: {
                            Label("Add Agent", systemImage: "plus")
                        }
                    }
                }
                .navigationDestination(for: AgentSettingsSelection.self) { selection in
                    AgentSettingsDestinationView(
                        selection: selection,
                        viewModel: viewModel,
                        openAgent: { agentID in
                            path = [.agent(agentID)]
                        },
                        closeDetail: {
                            path.removeAll()
                        }
                    )
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            viewModel.reloadExternalSettings()
        }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AgentSettingsHeroCard()

                SettingsListGroup {
                    NavigationLink(value: AgentSettingsSelection.orchestrator) {
                        SettingsNavigationRow(
                            systemImageName: "point.3.connected.trianglepath.dotted",
                            iconTint: .purple,
                            title: viewModel.orchestratorSettings.name,
                            subtitle: viewModel.orchestratorSettings.description.isEmpty
                                ? "Chooses which active agent suggestions are eligible to run."
                                : viewModel.orchestratorSettings.description,
                            trailingText: "Always On"
                        )
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Agent Personas")
                        .font(.headline)
                        .padding(.horizontal, 2)

                    if viewModel.profiles.isEmpty {
                        EmptyAgentListCard(createAgent: createAndOpenAgent)
                    } else {
                        SettingsListGroup {
                            ForEach(Array(viewModel.profiles.enumerated()), id: \.element.id) { index, profile in
                                if index > 0 {
                                    SettingsRowDivider()
                                }

                                NavigationLink(value: AgentSettingsSelection.agent(profile.id)) {
                                    SettingsNavigationRow(
                                        systemImageName: profile.isEnabled
                                            ? "person.crop.circle"
                                            : "person.crop.circle.badge.xmark",
                                        iconTint: profile.isActive ? .green : .gray,
                                        title: profile.name,
                                        subtitle: profile.description.isEmpty ? "No description" : profile.description,
                                        trailingText: profileStatusText(for: profile)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                statusNotices
            }
            .padding(28)
            .frame(maxWidth: 820, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var statusNotices: some View {
        if viewModel.providers.isEmpty {
            SettingsNoticeView(
                systemImageName: "exclamationmark.triangle",
                text: "No LLM providers configured.",
                tint: .orange
            )
        }

        if let lastErrorMessage = viewModel.lastErrorMessage {
            SettingsNoticeView(
                systemImageName: "exclamationmark.triangle",
                text: lastErrorMessage,
                tint: .red
            )
        }
    }

    private func createAndOpenAgent() {
        let agentID = viewModel.createProfile()
        path = [.agent(agentID)]
    }

    private func profileStatusText(for profile: AgentProfile) -> String {
        if profile.isEnabled == false {
            return "Disabled"
        }

        return profile.isActive ? "Active" : "Enabled"
    }
}

private struct AgentSettingsDestinationView: View {
    let selection: AgentSettingsSelection
    @ObservedObject var viewModel: AgentProfileListViewModel
    let openAgent: (AgentProfile.ID) -> Void
    let closeDetail: () -> Void

    var body: some View {
        switch selection {
        case .orchestrator:
            SettingsDetailPage(
                title: viewModel.orchestratorSettings.name,
                subtitle: "Root routing behavior for active agent suggestions.",
                systemImageName: "point.3.connected.trianglepath.dotted",
                iconTint: .purple
            ) {
                OrchestratorEditorView(settings: viewModel.orchestratorSettingsBinding)
                    .frame(maxWidth: 760, maxHeight: .infinity, alignment: .topLeading)
            }
            .toolbar {
                ToolbarItem {
                    Label("Always On", systemImage: "lock")
                        .foregroundStyle(.secondary)
                }
            }
        case .agent(let id):
            if let profile = viewModel.binding(for: id) {
                SettingsDetailPage(
                    title: profile.wrappedValue.name,
                    subtitle: profile.wrappedValue.description.isEmpty
                        ? "Configure this agent's identity, instructions, behavior, and provider."
                        : profile.wrappedValue.description,
                    systemImageName: profile.wrappedValue.isEnabled
                        ? "person.crop.circle"
                        : "person.crop.circle.badge.xmark",
                    iconTint: profile.wrappedValue.isActive ? .green : .gray
                ) {
                    AgentEditorView(
                        profile: profile,
                        providers: viewModel.providers
                    )
                    .frame(maxWidth: 760, maxHeight: .infinity, alignment: .topLeading)
                }
                .toolbar {
                    ToolbarItemGroup {
                        Button {
                            if let duplicateID = viewModel.duplicateProfile(id: id) {
                                openAgent(duplicateID)
                            }
                        } label: {
                            Label("Duplicate", systemImage: "doc.on.doc")
                        }

                        Button(role: .destructive) {
                            viewModel.deleteProfile(id: id)
                            closeDetail()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } else {
                MissingAgentView()
            }
        }
    }
}

private struct AgentSettingsHeroCard: View {
    var body: some View {
        VStack(spacing: 12) {
            SettingsIcon(
                systemImageName: "person.2",
                tint: .green,
                size: 64,
                symbolSize: 32
            )

            Text("Agents")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Manage the personas that can review and rewrite text from your active apps.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
        }
        .padding(.vertical, 34)
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct SettingsDetailPage<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImageName: String
    let iconTint: Color
    private let content: Content

    init(
        title: String,
        subtitle: String,
        systemImageName: String,
        iconTint: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImageName = systemImageName
        self.iconTint = iconTint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                SettingsIcon(
                    systemImageName: systemImageName,
                    tint: iconTint,
                    size: 52,
                    symbolSize: 25
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            content
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(title)
    }
}

private struct SettingsListGroup<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct SettingsNavigationRow: View {
    let systemImageName: String
    let iconTint: Color
    let title: String
    let subtitle: String
    let trailingText: String

    var body: some View {
        HStack(spacing: 14) {
            SettingsIcon(
                systemImageName: systemImageName,
                tint: iconTint,
                size: 36,
                symbolSize: 18
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Text(trailingText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

private struct SettingsIcon: View {
    let systemImageName: String
    let tint: Color
    let size: CGFloat
    let symbolSize: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(tint)

            Image(systemName: systemImageName)
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.14), radius: 3, x: 0, y: 1)
    }
}

private struct SettingsRowDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 68)
    }
}

private struct EmptyAgentListCard: View {
    let createAgent: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("No agents configured", systemImage: "person.crop.circle.badge.plus")
                .font(.headline)

            Text("Create an agent persona to start shaping rewrites for a specific tone, scope, or app context.")
                .foregroundStyle(.secondary)

            Button {
                createAgent()
            } label: {
                Label("Add Agent", systemImage: "plus")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct SettingsNoticeView: View {
    let systemImageName: String
    let text: String
    let tint: Color

    var body: some View {
        Label {
            Text(text)
                .font(.callout)
        } icon: {
            Image(systemName: systemImageName)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 2)
    }
}

private struct MissingAgentView: View {
    var body: some View {
        PlaceholderView()
            .navigationTitle("Agent Missing")
    }
}

private struct OrchestratorEditorView: View {
    @Binding var settings: OrchestratorSettings

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Name", text: $settings.name)
                TextField("Description", text: $settings.description, axis: .vertical)
            }

            Section("Behavior") {
                Stepper(
                    value: maximumSelectedAgentsBinding,
                    in: 1...4
                ) {
                    Text("Maximum Selected Agents: \(settings.maximumSelectedAgents)")
                }
            }

            Section("Safety") {
                Toggle("Always Available", isOn: .constant(true))
                    .disabled(true)
            }
        }
        .formStyle(.grouped)
    }

    private var maximumSelectedAgentsBinding: Binding<Int> {
        Binding(
            get: { settings.maximumSelectedAgents },
            set: { newValue in
                settings.maximumSelectedAgents = OrchestratorSettings.clampedMaximumSelectedAgents(newValue)
            }
        )
    }
}

private struct PlaceholderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No Agent Selected", systemImage: "person.crop.circle.badge.questionmark")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Create or select an agent persona to edit it.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
