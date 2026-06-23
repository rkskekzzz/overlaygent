import SwiftUI

struct ProviderSettingsView: View {
    @StateObject private var viewModel: ProviderSettingsViewModel
    @State private var path: [LLMProviderConfig.ID] = []

    init(
        store: LLMProviderStore = LLMProviderStore(),
        apiKeyStore: any LLMProviderAPIKeyStoring = KeychainStore(),
        modelLister: any LLMProviderModelListing = OpenAICompatibleModelLister()
    ) {
        _viewModel = StateObject(
            wrappedValue: ProviderSettingsViewModel(
                store: store,
                apiKeyStore: apiKeyStore,
                modelLister: modelLister
            )
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            overview
                .navigationTitle("LLM Provider")
                .toolbar {
                    ToolbarItem {
                        Button {
                            addAndOpenProvider()
                        } label: {
                            Label("Add Provider", systemImage: "plus")
                        }
                    }
                }
                .navigationDestination(for: LLMProviderConfig.ID.self) { providerID in
                    ProviderSettingsDestinationView(
                        providerID: providerID,
                        viewModel: viewModel,
                        closeDetail: {
                            path.removeAll()
                        }
                    )
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            viewModel.loadIfNeeded()
        }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ProviderSettingsHeroCard()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Providers")
                        .font(.headline)
                        .padding(.horizontal, 2)

                    if viewModel.providers.isEmpty {
                        EmptyProviderListCard(addProvider: addAndOpenProvider)
                    } else {
                        ProviderSettingsListGroup {
                            ForEach(Array(viewModel.providers.enumerated()), id: \.element.id) { index, provider in
                                if index > 0 {
                                    ProviderSettingsRowDivider()
                                }

                                NavigationLink(value: provider.id) {
                                    ProviderNavigationRow(
                                        systemImageName: "server.rack",
                                        iconTint: .blue,
                                        title: provider.name,
                                        subtitle: provider.baseURL.absoluteString,
                                        trailingText: provider.defaultModel
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                statusNotices

                ProviderOverviewActionBar(
                    hasProviders: viewModel.providers.isEmpty == false,
                    hasUnsavedChanges: viewModel.hasUnsavedChanges,
                    reload: {
                        viewModel.load()
                    },
                    save: {
                        viewModel.save()
                    }
                )
            }
            .padding(28)
            .frame(maxWidth: 820, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var statusNotices: some View {
        if let statusMessage = viewModel.statusMessage {
            ProviderSettingsNoticeView(
                systemImageName: viewModel.hasError ? "exclamationmark.triangle" : "checkmark.circle",
                text: statusMessage,
                tint: viewModel.hasError ? .red : .secondary
            )
        }

        if viewModel.hasUnsavedChanges {
            ProviderSettingsNoticeView(
                systemImageName: "pencil.circle",
                text: "Provider settings have unsaved changes.",
                tint: .orange
            )
        }
    }

    private func addAndOpenProvider() {
        let providerID = viewModel.addProvider()
        path = [providerID]
    }
}

private struct ProviderSettingsDestinationView: View {
    let providerID: LLMProviderConfig.ID
    @ObservedObject var viewModel: ProviderSettingsViewModel
    let closeDetail: () -> Void

    var body: some View {
        if let provider = viewModel.binding(for: providerID) {
            ProviderSettingsDetailPage(
                title: provider.wrappedValue.name,
                subtitle: "\(provider.wrappedValue.defaultModel) - \(provider.wrappedValue.baseURL.absoluteString)",
                systemImageName: "server.rack",
                iconTint: .blue
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    ProviderStatusStrip(
                        hasStoredAPIKey: viewModel.selectedProviderHasStoredAPIKey,
                        hasUnsavedChanges: viewModel.hasUnsavedChanges
                    )

                    ProviderSettingsForm(
                        provider: provider,
                        apiKeyDraft: $viewModel.apiKeyDraft,
                        hasStoredAPIKey: viewModel.selectedProviderHasStoredAPIKey,
                        availableModelIDs: viewModel.availableModelIDs(for: providerID),
                        isLoadingModelList: viewModel.isLoadingModelList,
                        refreshModels: {
                            Task {
                                await viewModel.refreshSelectedProviderModels()
                            }
                        },
                        saveAPIKey: {
                            viewModel.saveSelectedAPIKey()
                        },
                        deleteAPIKey: {
                            viewModel.deleteSelectedAPIKey()
                        }
                    )
                    .frame(maxWidth: 760, maxHeight: .infinity, alignment: .topLeading)

                    if let statusMessage = viewModel.statusMessage {
                        ProviderSettingsNoticeView(
                            systemImageName: viewModel.hasError ? "exclamationmark.triangle" : "checkmark.circle",
                            text: statusMessage,
                            tint: viewModel.hasError ? .red : .secondary
                        )
                    }
                }
            }
            .onAppear {
                viewModel.selectProvider(id: providerID)
            }
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        viewModel.load()
                        viewModel.selectProvider(id: providerID)
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }

                    Button {
                        viewModel.save()
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .keyboardShortcut("s", modifiers: [.command])
                    .disabled(viewModel.providers.isEmpty || viewModel.hasUnsavedChanges == false)

                    Button(role: .destructive) {
                        viewModel.deleteProvider(id: providerID)
                        closeDetail()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        } else {
            MissingProviderView()
        }
    }
}

private struct ProviderSettingsHeroCard: View {
    var body: some View {
        VStack(spacing: 12) {
            ProviderSettingsIcon(
                systemImageName: "server.rack",
                tint: .blue,
                size: 64,
                symbolSize: 30
            )

            Text("LLM Provider")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Configure the model endpoints and Keychain-backed API keys used by your agents.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 600)
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

private struct ProviderSettingsDetailPage<Content: View>: View {
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
                ProviderSettingsIcon(
                    systemImageName: systemImageName,
                    tint: iconTint,
                    size: 52,
                    symbolSize: 24
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

private struct ProviderSettingsListGroup<Content: View>: View {
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

private struct ProviderNavigationRow: View {
    let systemImageName: String
    let iconTint: Color
    let title: String
    let subtitle: String
    let trailingText: String

    var body: some View {
        HStack(spacing: 14) {
            ProviderSettingsIcon(
                systemImageName: systemImageName,
                tint: iconTint,
                size: 36,
                symbolSize: 17
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

private struct ProviderSettingsIcon: View {
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

private struct ProviderSettingsRowDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 68)
    }
}

private struct EmptyProviderListCard: View {
    let addProvider: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("No providers configured", systemImage: "server.rack")
                .font(.headline)

            Text("Create a provider to configure model defaults, endpoint timing, and API key storage.")
                .foregroundStyle(.secondary)

            Button {
                addProvider()
            } label: {
                Label("Add Provider", systemImage: "plus")
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

private struct ProviderStatusStrip: View {
    let hasStoredAPIKey: Bool
    let hasUnsavedChanges: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                ProviderStatusPill(
                    systemImageName: hasStoredAPIKey ? "key.fill" : "key.slash",
                    text: hasStoredAPIKey ? "API Key Stored" : "No API Key",
                    tint: hasStoredAPIKey ? .green : .secondary
                )

                ProviderStatusPill(
                    systemImageName: hasUnsavedChanges ? "pencil.circle" : "checkmark.circle",
                    text: hasUnsavedChanges ? "Unsaved Changes" : "Saved",
                    tint: hasUnsavedChanges ? .orange : .secondary
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                ProviderStatusPill(
                    systemImageName: hasStoredAPIKey ? "key.fill" : "key.slash",
                    text: hasStoredAPIKey ? "API Key Stored" : "No API Key",
                    tint: hasStoredAPIKey ? .green : .secondary
                )

                ProviderStatusPill(
                    systemImageName: hasUnsavedChanges ? "pencil.circle" : "checkmark.circle",
                    text: hasUnsavedChanges ? "Unsaved Changes" : "Saved",
                    tint: hasUnsavedChanges ? .orange : .secondary
                )
            }
        }
    }
}

private struct ProviderStatusPill: View {
    let systemImageName: String
    let text: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: systemImageName)
            .font(.caption)
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(tint.opacity(0.12))
            )
    }
}

private struct ProviderSettingsNoticeView: View {
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

private struct MissingProviderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Provider Missing", systemImage: "server.rack")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Create or select a provider to edit it.")
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Provider Missing")
    }
}

private struct ProviderOverviewActionBar: View {
    let hasProviders: Bool
    let hasUnsavedChanges: Bool
    let reload: () -> Void
    let save: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Text(hasUnsavedChanges ? "Unsaved provider changes" : "Provider settings are up to date")
                    .font(.callout)
                    .foregroundStyle(hasUnsavedChanges ? .orange : .secondary)

                Spacer()

                footerActions
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(hasUnsavedChanges ? "Unsaved provider changes" : "Provider settings are up to date")
                    .font(.callout)
                    .foregroundStyle(hasUnsavedChanges ? .orange : .secondary)

                HStack {
                    Spacer()
                    footerActions
                }
            }
        }
    }

    private var footerActions: some View {
        HStack(spacing: 8) {
            Button {
                reload()
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }

            Button {
                save()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(hasProviders == false || hasUnsavedChanges == false)
        }
    }
}

private struct ProviderSettingsForm: View {
    @Binding var provider: LLMProviderConfig
    @Binding var apiKeyDraft: String
    var hasStoredAPIKey: Bool
    var availableModelIDs: [String]
    var isLoadingModelList: Bool
    var refreshModels: () -> Void
    var saveAPIKey: () -> Void
    var deleteAPIKey: () -> Void

    var body: some View {
        Form {
            TextField("Provider name", text: $provider.name)

            TextField(
                "Base URL",
                text: Binding(
                    get: { provider.baseURL.absoluteString },
                    set: { newValue in
                        if let url = URL(string: newValue), url.scheme?.isEmpty == false {
                            provider.baseURL = url
                        }
                    }
                )
            )

            HStack {
                TextField("Default model", text: $provider.defaultModel)

                Menu {
                    ForEach(modelMenuIDs, id: \.self) { modelID in
                        Button(modelID) {
                            provider.defaultModel = modelID
                        }
                    }
                } label: {
                    Label("Models", systemImage: "list.bullet")
                }
                .disabled(modelMenuIDs.isEmpty)

                Button {
                    refreshModels()
                } label: {
                    Label(
                        isLoadingModelList ? "Loading" : "Refresh",
                        systemImage: "arrow.clockwise"
                    )
                }
                .disabled(isLoadingModelList)
            }

            Picker("Reasoning effort", selection: reasoningEffortSelection) {
                Text("Provider default").tag("")
                ForEach(ReasoningEffort.allCases) { effort in
                    Text(effort.displayName).tag(effort.rawValue)
                }
            }

            HStack {
                TextField("Temperature", value: $provider.temperature, formatter: Self.temperatureFormatter)
                Slider(value: $provider.temperature, in: 0...2, step: 0.1)
                    .frame(maxWidth: 180)
            }

            TextField("Max tokens", value: $provider.maxTokens, formatter: Self.integerFormatter)

            TextField("Timeout seconds", value: $provider.timeoutSeconds, formatter: Self.timeoutFormatter)

            SecureField(apiKeyFieldTitle, text: $apiKeyDraft)

            HStack {
                Text(apiKeyStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(hasStoredAPIKey ? "Update Key" : "Save Key") {
                    saveAPIKey()
                }
                .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(role: .destructive) {
                    deleteAPIKey()
                } label: {
                    Text("Delete Key")
                }
                .disabled(hasStoredAPIKey == false)
            }

            Text("API key is stored in macOS Keychain and is never written to provider settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var modelMenuIDs: [String] {
        let normalizedDefaultModel = provider.defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedDefaultModel.isEmpty == false,
              availableModelIDs.contains(normalizedDefaultModel) == false else {
            return availableModelIDs
        }

        return [normalizedDefaultModel] + availableModelIDs
    }

    private var reasoningEffortSelection: Binding<String> {
        Binding(
            get: {
                provider.reasoningEffort?.rawValue ?? ""
            },
            set: { rawValue in
                provider.reasoningEffort = ReasoningEffort(rawValue: rawValue)
            }
        )
    }

    private var apiKeyFieldTitle: String {
        hasStoredAPIKey ? "New API key" : "API key"
    }

    private var apiKeyStatusText: String {
        hasStoredAPIKey ? "A key is stored for this provider." : "No API key is stored."
    }

    private static let temperatureFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.minimum = 0
        formatter.maximum = 2
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let timeoutFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.minimum = 1
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.minimum = 1
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}

@MainActor
final class ProviderSettingsViewModel: ObservableObject {
    @Published var providers: [LLMProviderConfig] = []
    @Published var selectedProviderID: UUID? {
        didSet {
            guard selectedProviderID != oldValue else {
                return
            }

            loadAPIKeyStateForSelectedProvider()
        }
    }
    @Published var statusMessage: String?
    @Published var hasError = false
    @Published var hasUnsavedChanges = false
    @Published var apiKeyDraft = ""
    @Published var selectedProviderHasStoredAPIKey = false
    @Published var modelIDsByProviderID: [LLMProviderConfig.ID: [String]] = [:]
    @Published var isLoadingModelList = false

    private let store: LLMProviderStore
    private let apiKeyStore: any LLMProviderAPIKeyStoring
    private let modelLister: any LLMProviderModelListing
    private var hasLoaded = false
    private var lastSavedProviders: [LLMProviderConfig] = []
    private var providersPendingAPIKeyDeletion: [LLMProviderConfig] = []

    init(
        store: LLMProviderStore,
        apiKeyStore: any LLMProviderAPIKeyStoring = KeychainStore(),
        modelLister: any LLMProviderModelListing = OpenAICompatibleModelLister()
    ) {
        self.store = store
        self.apiKeyStore = apiKeyStore
        self.modelLister = modelLister
    }

    var selectedProviderBinding: Binding<LLMProviderConfig>? {
        guard let selectedProviderID else {
            return nil
        }

        return binding(for: selectedProviderID)
    }

    func binding(for id: LLMProviderConfig.ID) -> Binding<LLMProviderConfig>? {
        guard providers.contains(where: { $0.id == id }) else {
            return nil
        }

        return Binding(
            get: {
                self.provider(withID: id)
                    ?? LLMProviderConfig.deletedSelectionPlaceholder(id: id)
            },
            set: { updatedProvider in
                guard let index = self.providers.firstIndex(where: { $0.id == id }) else {
                    return
                }

                self.providers[index] = updatedProvider
                self.markProviderSettingsDirty()
            }
        )
    }

    func availableModelIDs(for providerID: LLMProviderConfig.ID) -> [String] {
        modelIDsByProviderID[providerID] ?? []
    }

    func loadIfNeeded() {
        guard hasLoaded == false else {
            return
        }

        load()
    }

    func load() {
        do {
            providers = try store.loadOrCreateDefaultProviders()
            lastSavedProviders = providers
            providersPendingAPIKeyDeletion = []
            modelIDsByProviderID = [:]
            selectedProviderID = providers.first?.id
            loadAPIKeyStateForSelectedProvider()
            hasUnsavedChanges = false
            hasLoaded = true
            statusMessage = "Loaded provider settings."
            hasError = false
        } catch {
            statusMessage = "Could not load provider settings: \(error.localizedDescription)"
            hasError = true
            apiKeyDraft = ""
            selectedProviderHasStoredAPIKey = false
        }
    }

    @discardableResult
    func addProvider() -> LLMProviderConfig.ID {
        let provider = LLMProviderConfig.defaultOpenAICompatible(name: uniqueProviderName())
        providers.append(provider)
        selectedProviderID = provider.id
        hasUnsavedChanges = true
        statusMessage = nil
        hasError = false
        return provider.id
    }

    func selectProvider(id: LLMProviderConfig.ID) {
        guard providers.contains(where: { $0.id == id }) else {
            return
        }

        selectedProviderID = id
    }

    func deleteSelectedProvider() {
        guard let selectedProviderID,
              let index = providers.firstIndex(where: { $0.id == selectedProviderID }) else {
            return
        }

        let provider = providers[index]
        providersPendingAPIKeyDeletion.append(provider)

        providers.remove(at: index)
        modelIDsByProviderID[provider.id] = nil
        self.selectedProviderID = providers.indices.contains(index)
            ? providers[index].id
            : providers.last?.id
        hasUnsavedChanges = true
        statusMessage = nil
        hasError = false
    }

    func deleteProvider(id: LLMProviderConfig.ID) {
        selectedProviderID = id
        deleteSelectedProvider()
    }

    func save() {
        do {
            try store.saveProviders(providers)
            try deleteAPIKeysForRemovedProviders()
            lastSavedProviders = providers
            providersPendingAPIKeyDeletion = []
            hasUnsavedChanges = false
            statusMessage = "Saved provider settings."
            hasError = false
        } catch {
            statusMessage = "Could not save provider settings: \(error.localizedDescription)"
            hasError = true
        }
    }

    func saveSelectedAPIKey() {
        guard let provider = selectedProvider else {
            statusMessage = "Select a provider before saving an API key."
            hasError = true
            return
        }

        let apiKey = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard apiKey.isEmpty == false else {
            statusMessage = "Enter an API key before saving."
            hasError = true
            return
        }

        do {
            try apiKeyStore.saveAPIKey(apiKey, for: provider)
            apiKeyDraft = ""
            selectedProviderHasStoredAPIKey = true
            statusMessage = "Saved API key to Keychain."
            hasError = false
        } catch {
            statusMessage = "Could not save API key: \(error.localizedDescription)"
            hasError = true
        }
    }

    func deleteSelectedAPIKey() {
        guard let provider = selectedProvider else {
            statusMessage = "Select a provider before deleting an API key."
            hasError = true
            return
        }

        do {
            try apiKeyStore.deleteAPIKey(for: provider)
            apiKeyDraft = ""
            selectedProviderHasStoredAPIKey = false
            statusMessage = "Deleted API key from Keychain."
            hasError = false
        } catch {
            statusMessage = "Could not delete API key: \(error.localizedDescription)"
            hasError = true
        }
    }

    func refreshSelectedProviderModels() async {
        guard let provider = selectedProvider else {
            statusMessage = "Select a provider before refreshing models."
            hasError = true
            return
        }

        let apiKey: String
        do {
            apiKey = try apiKeyStore.readAPIKey(for: provider)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            statusMessage = "Could not load API key for model refresh: \(error.localizedDescription)"
            hasError = true
            return
        }

        guard apiKey.isEmpty == false else {
            statusMessage = "Save an API key before refreshing models."
            hasError = true
            return
        }

        isLoadingModelList = true
        statusMessage = "Loading models..."
        hasError = false

        do {
            let modelIDs = try await modelLister.listModels(provider: provider, apiKey: apiKey)
            modelIDsByProviderID[provider.id] = modelIDs
            statusMessage = modelIDs.isEmpty
                ? "No models were returned for this provider."
                : "Loaded \(modelIDs.count) models."
            hasError = false
        } catch {
            statusMessage = "Could not load models: \(error.localizedDescription)"
            hasError = true
        }

        isLoadingModelList = false
    }

    private var selectedProvider: LLMProviderConfig? {
        guard let selectedProviderID else {
            return nil
        }

        return provider(withID: selectedProviderID)
    }

    private func provider(withID id: UUID) -> LLMProviderConfig? {
        providers.first { $0.id == id }
    }

    private func markProviderSettingsDirty() {
        hasUnsavedChanges = true
        statusMessage = nil
        hasError = false
    }

    private func deleteAPIKeysForRemovedProviders() throws {
        let savedProviderIDs = Set(providers.map(\.id))
        let removedSavedProviders = lastSavedProviders.filter { savedProviderIDs.contains($0.id) == false }
        let providersToDelete = uniqueProvidersByID(removedSavedProviders + providersPendingAPIKeyDeletion)

        for provider in providersToDelete {
            try apiKeyStore.deleteAPIKey(for: provider)
        }
    }

    private func uniqueProvidersByID(_ providers: [LLMProviderConfig]) -> [LLMProviderConfig] {
        var seenIDs: Set<UUID> = []
        var uniqueProviders: [LLMProviderConfig] = []

        for provider in providers where seenIDs.insert(provider.id).inserted {
            uniqueProviders.append(provider)
        }

        return uniqueProviders
    }

    private func loadAPIKeyStateForSelectedProvider() {
        apiKeyDraft = ""

        guard let provider = selectedProvider else {
            selectedProviderHasStoredAPIKey = false
            return
        }

        do {
            let storedAPIKey = try apiKeyStore.readAPIKey(for: provider)
            selectedProviderHasStoredAPIKey = storedAPIKey?.isEmpty == false
        } catch {
            selectedProviderHasStoredAPIKey = false
            statusMessage = "Could not load API key status: \(error.localizedDescription)"
            hasError = true
        }
    }

    private func uniqueProviderName() -> String {
        let baseName = "OpenAI Compatible"
        let existingNames = Set(providers.map(\.name))

        guard existingNames.contains(baseName) else {
            return baseName
        }

        var suffix = 2
        while existingNames.contains("\(baseName) \(suffix)") {
            suffix += 1
        }

        return "\(baseName) \(suffix)"
    }
}

private extension LLMProviderConfig {
    static func deletedSelectionPlaceholder(id: UUID) -> LLMProviderConfig {
        LLMProviderConfig.defaultOpenAICompatible(
            id: id,
            name: "Deleted Provider",
            defaultModel: ""
        )
    }
}

#Preview {
    ProviderSettingsView()
}
