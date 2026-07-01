import SwiftUI

struct ProviderSettingsView: View {
    @StateObject private var viewModel: ProviderSettingsViewModel
    @State private var path: [LLMProviderConfig.ID] = []

    init(
        store: LLMProviderStore = LLMProviderStore(),
        apiKeyStore: any LLMProviderAPIKeyStoring = KeychainStore(),
        chatGPTCredentialStore: (any ChatGPTSubscriptionCredentialStoring)? = nil,
        chatGPTCredentialImporter: any ChatGPTSubscriptionCredentialImporting = CodexAuthFileImporter(),
        modelLister: any LLMProviderModelListing = LLMProviderModelListerRouter()
    ) {
        _viewModel = StateObject(
            wrappedValue: ProviderSettingsViewModel(
                store: store,
                apiKeyStore: apiKeyStore,
                chatGPTCredentialStore: chatGPTCredentialStore,
                chatGPTCredentialImporter: chatGPTCredentialImporter,
                modelLister: modelLister
            )
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            overview
                .toolbar {
                    ToolbarItem {
                        Menu {
                            Button {
                                addAndOpenChatGPTSubscription()
                            } label: {
                                Label("ChatGPT Subscription", systemImage: "person.crop.circle.badge.checkmark")
                            }

                            Divider()

                            Button {
                                addAndOpenProvider()
                            } label: {
                                Label("OpenAI Compatible API", systemImage: "key")
                            }
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
                        ForEach(viewModel.providerCategoriesWithProviders, id: \.category.id) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.category.displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 2)

                                ProviderSettingsListGroup {
                                    ForEach(Array(group.providers.enumerated()), id: \.element.id) { index, provider in
                                        if index > 0 {
                                            ProviderSettingsRowDivider()
                                        }

                                        NavigationLink(value: provider.id) {
                                            ProviderNavigationRow(
                                                systemImageName: provider.systemImageName,
                                                iconTint: provider.iconTint,
                                                title: provider.name,
                                                subtitle: provider.providerSubtitle,
                                                trailingText: provider.defaultModel
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
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

    private func addAndOpenChatGPTSubscription() {
        let providerID = viewModel.addChatGPTSubscriptionProvider()
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
                subtitle: provider.wrappedValue.detailSubtitle,
                systemImageName: provider.wrappedValue.systemImageName,
                iconTint: provider.wrappedValue.iconTint
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    ProviderStatusStrip(
                        credentialStatus: viewModel.selectedProviderCredentialStatus,
                        hasUnsavedChanges: viewModel.hasUnsavedChanges
                    )

                    ProviderSettingsForm(
                        provider: provider,
                        apiKeyDraft: $viewModel.apiKeyDraft,
                        hasStoredAPIKey: viewModel.selectedProviderHasStoredAPIKey,
                        isSubscriptionProvider: provider.wrappedValue.category == .subscription,
                        chatGPTAccountID: viewModel.selectedChatGPTAccountID,
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
                        },
                        importChatGPTSubscription: {
                            viewModel.importSelectedChatGPTSubscription()
                        },
                        disconnectChatGPTSubscription: {
                            viewModel.disconnectSelectedChatGPTSubscription()
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
    let credentialStatus: ProviderCredentialStatus
    let hasUnsavedChanges: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                ProviderStatusPill(
                    systemImageName: credentialStatus.systemImageName,
                    text: credentialStatus.text,
                    tint: credentialStatus.tint
                )

                ProviderStatusPill(
                    systemImageName: hasUnsavedChanges ? "pencil.circle" : "checkmark.circle",
                    text: hasUnsavedChanges ? "Unsaved Changes" : "Saved",
                    tint: hasUnsavedChanges ? .orange : .secondary
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                ProviderStatusPill(
                    systemImageName: credentialStatus.systemImageName,
                    text: credentialStatus.text,
                    tint: credentialStatus.tint
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
    var isSubscriptionProvider: Bool
    var chatGPTAccountID: String?
    var availableModelIDs: [String]
    var isLoadingModelList: Bool
    var refreshModels: () -> Void
    var saveAPIKey: () -> Void
    var deleteAPIKey: () -> Void
    var importChatGPTSubscription: () -> Void
    var disconnectChatGPTSubscription: () -> Void

    var body: some View {
        Form {
            TextField("Provider name", text: $provider.name)

            if isSubscriptionProvider {
                LabeledContent("Account") {
                    Text(chatGPTAccountID ?? "Not connected")
                        .foregroundStyle(chatGPTAccountID == nil ? .secondary : .primary)
                }

                HStack {
                    Button {
                        importChatGPTSubscription()
                    } label: {
                        Label(
                            chatGPTAccountID == nil ? "Import Codex Login" : "Reimport Codex Login",
                            systemImage: "person.crop.circle.badge.checkmark"
                        )
                    }

                    Button(role: .destructive) {
                        disconnectChatGPTSubscription()
                    } label: {
                        Text("Disconnect")
                    }
                    .disabled(chatGPTAccountID == nil)
                }

                Text("Uses a local Codex ChatGPT login token copied into macOS Keychain for this provider.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
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
            }

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

            if isSubscriptionProvider == false {
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

struct ProviderCategoryGroup {
    var category: LLMProviderCategory
    var providers: [LLMProviderConfig]
}

struct ProviderCredentialStatus {
    var systemImageName: String
    var text: String
    var tint: Color

    static let noSelection = ProviderCredentialStatus(
        systemImageName: "questionmark.circle",
        text: "No Provider",
        tint: .secondary
    )

    static func apiKey(stored: Bool) -> ProviderCredentialStatus {
        ProviderCredentialStatus(
            systemImageName: stored ? "key.fill" : "key.slash",
            text: stored ? "API Key Stored" : "No API Key",
            tint: stored ? .green : .secondary
        )
    }

    static func chatGPT(accountID: String?) -> ProviderCredentialStatus {
        ProviderCredentialStatus(
            systemImageName: accountID == nil ? "person.crop.circle.badge.exclamationmark" : "person.crop.circle.badge.checkmark",
            text: accountID == nil ? "Login Required" : "ChatGPT Connected",
            tint: accountID == nil ? .secondary : .green
        )
    }
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
    @Published var selectedChatGPTAccountID: String?
    @Published var modelIDsByProviderID: [LLMProviderConfig.ID: [String]] = [:]
    @Published var isLoadingModelList = false

    private let store: LLMProviderStore
    private let apiKeyStore: any LLMProviderAPIKeyStoring
    private let chatGPTCredentialStore: any ChatGPTSubscriptionCredentialStoring
    private let chatGPTCredentialImporter: any ChatGPTSubscriptionCredentialImporting
    private let credentialResolver: any LLMProviderCredentialResolving
    private let modelLister: any LLMProviderModelListing
    private var hasLoaded = false
    private var lastSavedProviders: [LLMProviderConfig] = []
    private var providersPendingAPIKeyDeletion: [LLMProviderConfig] = []

    init(
        store: LLMProviderStore,
        apiKeyStore: any LLMProviderAPIKeyStoring = KeychainStore(),
        chatGPTCredentialStore: (any ChatGPTSubscriptionCredentialStoring)? = nil,
        chatGPTCredentialImporter: any ChatGPTSubscriptionCredentialImporting = CodexAuthFileImporter(),
        credentialResolver: (any LLMProviderCredentialResolving)? = nil,
        modelLister: any LLMProviderModelListing = LLMProviderModelListerRouter()
    ) {
        self.store = store
        self.apiKeyStore = apiKeyStore
        let resolvedChatGPTCredentialStore = chatGPTCredentialStore
            ?? apiKeyStore as? any ChatGPTSubscriptionCredentialStoring
            ?? NoopChatGPTSubscriptionCredentialStore()
        self.chatGPTCredentialStore = resolvedChatGPTCredentialStore
        self.chatGPTCredentialImporter = chatGPTCredentialImporter
        self.credentialResolver = credentialResolver ?? DefaultLLMProviderCredentialResolver(
            apiKeyStore: apiKeyStore,
            chatGPTCredentialStore: resolvedChatGPTCredentialStore
        )
        self.modelLister = modelLister
    }

    var providerCategoriesWithProviders: [ProviderCategoryGroup] {
        LLMProviderCategory.allCases.compactMap { category in
            let categoryProviders = providers.filter { $0.category == category }
            guard categoryProviders.isEmpty == false else {
                return nil
            }
            return ProviderCategoryGroup(category: category, providers: categoryProviders)
        }
    }

    var selectedProviderCredentialStatus: ProviderCredentialStatus {
        guard let selectedProvider else {
            return .noSelection
        }

        switch selectedProvider.auth.mode {
        case .subscriptionOAuth:
            return .chatGPT(accountID: selectedChatGPTAccountID)
        case .apiKey:
            return .apiKey(stored: selectedProviderHasStoredAPIKey)
        case .bearerTokenCommand:
            return ProviderCredentialStatus(
                systemImageName: "terminal",
                text: "Command Auth",
                tint: .secondary
            )
        case .none:
            return ProviderCredentialStatus(
                systemImageName: "lock.open",
                text: "No Auth",
                tint: .secondary
            )
        }
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
            selectedChatGPTAccountID = nil
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

    @discardableResult
    func addChatGPTSubscriptionProvider() -> LLMProviderConfig.ID {
        let provider = LLMProviderConfig.defaultChatGPTSubscription(name: uniqueChatGPTSubscriptionProviderName())
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

        guard provider.auth.mode == .apiKey else {
            statusMessage = "This provider does not use API key authentication."
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

        guard provider.auth.mode == .apiKey else {
            statusMessage = "This provider does not use API key authentication."
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

    func importSelectedChatGPTSubscription() {
        guard let provider = selectedProvider else {
            statusMessage = "Select a provider before importing ChatGPT login."
            hasError = true
            return
        }

        guard provider.auth.subscriptionService == .chatGPT else {
            statusMessage = "This provider is not a ChatGPT subscription provider."
            hasError = true
            return
        }

        do {
            let credential = try chatGPTCredentialImporter.importCredential()
            try chatGPTCredentialStore.saveChatGPTSubscriptionCredential(credential, for: provider)
            selectedChatGPTAccountID = credential.accountID
            statusMessage = "Imported ChatGPT subscription login to Keychain."
            hasError = false
        } catch {
            selectedChatGPTAccountID = nil
            statusMessage = "Could not import ChatGPT login: \(error.localizedDescription)"
            hasError = true
        }
    }

    func disconnectSelectedChatGPTSubscription() {
        guard let provider = selectedProvider else {
            statusMessage = "Select a provider before disconnecting ChatGPT login."
            hasError = true
            return
        }

        guard provider.auth.subscriptionService == .chatGPT else {
            statusMessage = "This provider is not a ChatGPT subscription provider."
            hasError = true
            return
        }

        do {
            try chatGPTCredentialStore.deleteChatGPTSubscriptionCredential(for: provider)
            selectedChatGPTAccountID = nil
            statusMessage = "Disconnected ChatGPT subscription login."
            hasError = false
        } catch {
            statusMessage = "Could not disconnect ChatGPT login: \(error.localizedDescription)"
            hasError = true
        }
    }

    func refreshSelectedProviderModels() async {
        guard let provider = selectedProvider else {
            statusMessage = "Select a provider before refreshing models."
            hasError = true
            return
        }

        let credential: LLMCredential
        do {
            credential = try await credentialResolver.credential(for: provider)
        } catch let error as LLMProviderCredentialError {
            if provider.auth.mode == .subscriptionOAuth {
                statusMessage = "Import ChatGPT login before refreshing models."
            } else if error == .missingCredential(mode: .apiKey) {
                statusMessage = "Save an API key before refreshing models."
            } else {
                statusMessage = "Could not load provider credential for model refresh: \(error.localizedDescription)"
            }
            hasError = true
            return
        } catch {
            statusMessage = "Could not load provider credential for model refresh: \(error.localizedDescription)"
            hasError = true
            return
        }

        isLoadingModelList = true
        statusMessage = "Loading models..."
        hasError = false

        do {
            let modelIDs = try await modelLister.listModels(provider: provider, credential: credential)
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
            try chatGPTCredentialStore.deleteChatGPTSubscriptionCredential(for: provider)
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
            selectedChatGPTAccountID = nil
            return
        }

        selectedChatGPTAccountID = nil

        do {
            if provider.auth.mode == .apiKey {
                let storedAPIKey = try apiKeyStore.readAPIKey(for: provider)
                selectedProviderHasStoredAPIKey = storedAPIKey?.isEmpty == false
            } else {
                selectedProviderHasStoredAPIKey = false
            }

            if provider.auth.subscriptionService == .chatGPT {
                let credential = try chatGPTCredentialStore
                    .readChatGPTSubscriptionCredential(for: provider)
                selectedChatGPTAccountID = credential?.isUsable == true
                    ? credential?.accountID
                    : nil
            }
        } catch {
            selectedProviderHasStoredAPIKey = false
            selectedChatGPTAccountID = nil
            statusMessage = "Could not load provider credential status: \(error.localizedDescription)"
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

    private func uniqueChatGPTSubscriptionProviderName() -> String {
        let baseName = "ChatGPT Subscription"
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

    var systemImageName: String {
        switch kind {
        case .chatGPTSubscription:
            return "person.crop.circle.badge.checkmark"
        case .openAICompatibleAPI:
            return "key"
        case .localOpenAICompatible:
            return "desktopcomputer"
        }
    }

    var iconTint: Color {
        switch category {
        case .subscription:
            return .green
        case .api:
            return .blue
        case .local:
            return .purple
        }
    }

    var providerSubtitle: String {
        switch kind {
        case .chatGPTSubscription:
            return "ChatGPT account subscription"
        case .openAICompatibleAPI, .localOpenAICompatible:
            return baseURL.absoluteString
        }
    }

    var detailSubtitle: String {
        "\(defaultModel) - \(providerSubtitle)"
    }
}

#Preview {
    ProviderSettingsView()
}
