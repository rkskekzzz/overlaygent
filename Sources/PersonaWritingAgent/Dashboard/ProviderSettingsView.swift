import SwiftUI

struct ProviderSettingsView: View {
    @StateObject private var viewModel: ProviderSettingsViewModel

    init(
        store: LLMProviderStore = LLMProviderStore(),
        apiKeyStore: any LLMProviderAPIKeyStoring = KeychainStore()
    ) {
        _viewModel = StateObject(
            wrappedValue: ProviderSettingsViewModel(
                store: store,
                apiKeyStore: apiKeyStore
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("LLM Provider", systemImage: "server.rack")
                .font(.title)
                .fontWeight(.semibold)

            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 10) {
                    List(viewModel.providers, selection: $viewModel.selectedProviderID) { provider in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(provider.name)
                                .font(.headline)
                            Text(provider.defaultModel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(provider.id as UUID?)
                    }
                    .frame(minWidth: 220, idealWidth: 240, maxWidth: 280)

                    HStack {
                        Button {
                            viewModel.addProvider()
                        } label: {
                            Label("Add", systemImage: "plus")
                        }

                        Button(role: .destructive) {
                            viewModel.deleteSelectedProvider()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(viewModel.selectedProviderID == nil)
                    }
                }

                Divider()

                Group {
                    if let selectedProvider = viewModel.selectedProviderBinding {
                        ProviderSettingsForm(
                            provider: selectedProvider,
                            apiKeyDraft: $viewModel.apiKeyDraft,
                            hasStoredAPIKey: viewModel.selectedProviderHasStoredAPIKey,
                            saveAPIKey: {
                                viewModel.saveSelectedAPIKey()
                            },
                            deleteAPIKey: {
                                viewModel.deleteSelectedAPIKey()
                            }
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No provider selected")
                                .font(.headline)
                            Text("Create a provider to configure model defaults.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            }

            Divider()

            HStack(spacing: 12) {
                if let statusMessage = viewModel.statusMessage {
                    Text(statusMessage)
                        .font(.callout)
                        .foregroundStyle(viewModel.hasError ? .red : .secondary)
                }

                Spacer()

                Button {
                    viewModel.load()
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
            }
        }
        .padding(28)
        .frame(minWidth: 760, minHeight: 460, alignment: .topLeading)
        .task {
            viewModel.loadIfNeeded()
        }
    }
}

private struct ProviderSettingsForm: View {
    @Binding var provider: LLMProviderConfig
    @Binding var apiKeyDraft: String
    var hasStoredAPIKey: Bool
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

            TextField("Default model", text: $provider.defaultModel)

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
        .frame(maxWidth: 520, maxHeight: .infinity, alignment: .topLeading)
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

    private let store: LLMProviderStore
    private let apiKeyStore: any LLMProviderAPIKeyStoring
    private var hasLoaded = false
    private var lastSavedProviders: [LLMProviderConfig] = []
    private var providersPendingAPIKeyDeletion: [LLMProviderConfig] = []

    init(
        store: LLMProviderStore,
        apiKeyStore: any LLMProviderAPIKeyStoring = KeychainStore()
    ) {
        self.store = store
        self.apiKeyStore = apiKeyStore
    }

    var selectedProviderBinding: Binding<LLMProviderConfig>? {
        guard let selectedProviderID,
              providers.contains(where: { $0.id == selectedProviderID }) else {
            return nil
        }

        return Binding(
            get: {
                self.provider(withID: selectedProviderID)
                    ?? LLMProviderConfig.deletedSelectionPlaceholder(id: selectedProviderID)
            },
            set: { updatedProvider in
                guard let index = self.providers.firstIndex(where: { $0.id == selectedProviderID }) else {
                    return
                }

                self.providers[index] = updatedProvider
                self.markProviderSettingsDirty()
            }
        )
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

    func addProvider() {
        let provider = LLMProviderConfig.defaultOpenAICompatible(name: uniqueProviderName())
        providers.append(provider)
        selectedProviderID = provider.id
        hasUnsavedChanges = true
        statusMessage = nil
        hasError = false
    }

    func deleteSelectedProvider() {
        guard let selectedProviderID,
              let index = providers.firstIndex(where: { $0.id == selectedProviderID }) else {
            return
        }

        let provider = providers[index]
        providersPendingAPIKeyDeletion.append(provider)

        providers.remove(at: index)
        self.selectedProviderID = providers.indices.contains(index)
            ? providers[index].id
            : providers.last?.id
        hasUnsavedChanges = true
        statusMessage = nil
        hasError = false
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
