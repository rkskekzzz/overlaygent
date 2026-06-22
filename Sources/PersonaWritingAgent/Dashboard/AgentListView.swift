import SwiftUI

@MainActor
final class AgentProfileListViewModel: ObservableObject {
    @Published private(set) var profiles: [AgentProfile]
    @Published var selectedProfileID: AgentProfile.ID?
    @Published var lastErrorMessage: String?

    private let store: AgentProfileStore

    init(store: AgentProfileStore = .defaultStore) {
        self.store = store

        do {
            let loadedProfiles = try store.loadProfiles()
            self.profiles = loadedProfiles
            self.selectedProfileID = loadedProfiles.first?.id
        } catch {
            self.profiles = AgentProfileStore.defaultAgents()
            self.selectedProfileID = profiles.first?.id
            self.lastErrorMessage = "Failed to load agents: \(error.localizedDescription)"
        }
    }

    func createProfile() {
        let profile = AgentProfileStore.newAgent()
        profiles.append(profile)
        selectedProfileID = profile.id
        persistProfiles()
    }

    func deleteProfile(id: AgentProfile.ID) {
        profiles.removeAll { $0.id == id }

        if selectedProfileID == id {
            selectedProfileID = profiles.first?.id
        }

        persistProfiles()
    }

    func duplicateProfile(id: AgentProfile.ID) {
        guard let profile = profiles.first(where: { $0.id == id }) else {
            return
        }

        let duplicate = AgentProfileStore.duplicate(profile)
        profiles.append(duplicate)
        selectedProfileID = duplicate.id
        persistProfiles()
    }

    func toggleActive(id: AgentProfile.ID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            return
        }

        profiles[index].isActive.toggle()
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

    private func persistProfiles() {
        do {
            try store.saveProfiles(profiles)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Failed to save agents: \(error.localizedDescription)"
        }
    }
}

struct AgentListView: View {
    @StateObject private var viewModel: AgentProfileListViewModel

    @MainActor
    init() {
        _viewModel = StateObject(wrappedValue: AgentProfileListViewModel())
    }

    @MainActor
    init(store: AgentProfileStore) {
        _viewModel = StateObject(wrappedValue: AgentProfileListViewModel(store: store))
    }

    @MainActor
    init(viewModel: AgentProfileListViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $viewModel.selectedProfileID) {
                    ForEach(viewModel.profiles) { profile in
                        AgentRowView(
                            profile: profile,
                            onActiveToggle: {
                                viewModel.toggleActive(id: profile.id)
                            }
                        )
                        .tag(profile.id)
                    }
                    .onDelete { offsets in
                        deleteProfiles(at: offsets)
                    }
                }

                Divider()

                HStack(spacing: 8) {
                    Button {
                        viewModel.createProfile()
                    } label: {
                        Label("Add Agent", systemImage: "plus")
                    }

                    Button {
                        if let selectedProfileID = viewModel.selectedProfileID {
                            viewModel.duplicateProfile(id: selectedProfileID)
                        }
                    } label: {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }
                    .disabled(viewModel.selectedProfileID == nil)

                    Button(role: .destructive) {
                        if let selectedProfileID = viewModel.selectedProfileID {
                            viewModel.deleteProfile(id: selectedProfileID)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(viewModel.selectedProfileID == nil)
                }
                .padding(12)
            }
            .navigationTitle("Agents")
            .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
        } detail: {
            VStack(alignment: .leading, spacing: 16) {
                if let profile = viewModel.selectedProfileBinding {
                    AgentEditorView(profile: profile)
                } else {
                    PlaceholderView()
                }

                if let lastErrorMessage = viewModel.lastErrorMessage {
                    Label(lastErrorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 820, minHeight: 540)
    }

    private func deleteProfiles(at offsets: IndexSet) {
        let ids = offsets.map { viewModel.profiles[$0].id }
        for id in ids {
            viewModel.deleteProfile(id: id)
        }
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

private struct AgentRowView: View {
    let profile: AgentProfile
    let onActiveToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(profile.description.isEmpty ? "No description" : profile.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Toggle("Active", isOn: activeBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .help("Active in menu")
        }
        .padding(.vertical, 4)
        .opacity(profile.isEnabled ? 1 : 0.55)
    }

    private var activeBinding: Binding<Bool> {
        Binding(
            get: { profile.isActive },
            set: { _ in onActiveToggle() }
        )
    }
}
