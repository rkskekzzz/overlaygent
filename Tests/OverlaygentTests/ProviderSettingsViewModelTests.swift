import Foundation
import SwiftUI
import XCTest
@testable import Overlaygent

@MainActor
final class ProviderSettingsViewModelTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ProviderSettingsViewModelTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testDeletingOnlySelectedProviderDoesNotCrashStaleBindingAndDefersKeyDeletionUntilSave() throws {
        let apiKeyStore = InMemoryProviderAPIKeyStore()
        let provider = provider(idSuffix: "101")
        let viewModel = makeViewModel(apiKeyStore: apiKeyStore)
        viewModel.providers = [provider]
        viewModel.selectedProviderID = provider.id

        let staleBinding = try XCTUnwrap(viewModel.selectedProviderBinding)

        viewModel.deleteSelectedProvider()

        XCTAssertEqual(viewModel.providers, [])
        XCTAssertNil(viewModel.selectedProviderID)
        XCTAssertTrue(viewModel.hasUnsavedChanges)
        XCTAssertEqual(apiKeyStore.deletedServiceNames, [])
        XCTAssertEqual(staleBinding.wrappedValue.id, provider.id)

        viewModel.save()

        XCTAssertEqual(apiKeyStore.deletedServiceNames, [provider.keychainServiceName])
    }

    func testDeletingChatGPTSubscriptionProviderDefersCredentialDeletionUntilSave() {
        let credentialStore = InMemoryChatGPTCredentialStore()
        let provider = LLMProviderConfig.defaultChatGPTSubscription(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000105")!
        )
        credentialStore.credentialsByServiceName[provider.keychainServiceName] = ChatGPTSubscriptionCredential(
            accessToken: "access-token",
            accountID: "account-id",
            expiresAt: nil,
            sourceDescription: nil
        )
        let viewModel = makeViewModel(chatGPTCredentialStore: credentialStore)
        viewModel.providers = [provider]
        viewModel.selectedProviderID = provider.id

        viewModel.deleteSelectedProvider()

        XCTAssertEqual(credentialStore.deletedServiceNames, [])
        XCTAssertNotNil(credentialStore.credentialsByServiceName[provider.keychainServiceName])

        viewModel.save()

        XCTAssertEqual(credentialStore.deletedServiceNames, [provider.keychainServiceName])
        XCTAssertNil(credentialStore.credentialsByServiceName[provider.keychainServiceName])
    }

    func testSelectedProviderBindingUpdatesByIDAfterArrayMutation() throws {
        let first = provider(idSuffix: "201", name: "First")
        let second = provider(idSuffix: "202", name: "Second")
        let viewModel = makeViewModel()
        viewModel.providers = [first, second]
        viewModel.selectedProviderID = second.id

        let binding = try XCTUnwrap(viewModel.selectedProviderBinding)
        viewModel.providers.removeFirst()

        var updated = binding.wrappedValue
        updated.defaultModel = "updated-model"
        binding.wrappedValue = updated

        XCTAssertEqual(viewModel.providers, [updated])
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }

    func testSavingAndDeletingSelectedAPIKeyUsesKeychainStoreOnly() {
        let apiKeyStore = InMemoryProviderAPIKeyStore()
        let provider = provider(idSuffix: "301")
        let viewModel = makeViewModel(apiKeyStore: apiKeyStore)
        viewModel.providers = [provider]
        viewModel.selectedProviderID = provider.id

        viewModel.apiKeyDraft = "  sk-test-secret  "
        viewModel.saveSelectedAPIKey()

        XCTAssertEqual(apiKeyStore.apiKeysByServiceName[provider.keychainServiceName], "sk-test-secret")
        XCTAssertEqual(viewModel.apiKeyDraft, "")
        XCTAssertTrue(viewModel.selectedProviderHasStoredAPIKey)
        XCTAssertEqual(viewModel.statusMessage, "Saved API key to Keychain.")

        viewModel.deleteSelectedAPIKey()

        XCTAssertNil(apiKeyStore.apiKeysByServiceName[provider.keychainServiceName])
        XCTAssertFalse(viewModel.selectedProviderHasStoredAPIKey)
        XCTAssertEqual(viewModel.statusMessage, "Deleted API key from Keychain.")
    }

    func testSelectingProviderLoadsStoredAPIKeyPresenceWithoutExposingSecret() {
        let apiKeyStore = InMemoryProviderAPIKeyStore()
        let provider = provider(idSuffix: "401")
        apiKeyStore.apiKeysByServiceName[provider.keychainServiceName] = "sk-existing-secret"
        let viewModel = makeViewModel(apiKeyStore: apiKeyStore)
        viewModel.providers = [provider]

        viewModel.selectedProviderID = provider.id

        XCTAssertTrue(viewModel.selectedProviderHasStoredAPIKey)
        XCTAssertEqual(viewModel.apiKeyDraft, "")
    }

    func testRefreshingSelectedProviderModelsUsesStoredAPIKeyAndCachesModelIDs() async {
        let apiKeyStore = InMemoryProviderAPIKeyStore()
        let modelLister = MockProviderModelLister(result: .success(["gpt-4.1-mini", "gpt-5.2"]))
        let provider = provider(idSuffix: "501")
        apiKeyStore.apiKeysByServiceName[provider.keychainServiceName] = "  sk-existing-secret  "
        let viewModel = makeViewModel(apiKeyStore: apiKeyStore, modelLister: modelLister)
        viewModel.providers = [provider]
        viewModel.selectedProviderID = provider.id
        viewModel.hasUnsavedChanges = false

        await viewModel.refreshSelectedProviderModels()

        XCTAssertEqual(viewModel.availableModelIDs(for: provider.id), ["gpt-4.1-mini", "gpt-5.2"])
        XCTAssertEqual(modelLister.capturedProviders, [provider])
        XCTAssertEqual(modelLister.capturedCredentials, [.apiKey("sk-existing-secret")])
        XCTAssertEqual(viewModel.statusMessage, "Loaded 2 models.")
        XCTAssertFalse(viewModel.hasError)
        XCTAssertFalse(viewModel.isLoadingModelList)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
    }

    func testRefreshingSelectedProviderModelsRequiresStoredAPIKey() async {
        let modelLister = MockProviderModelLister(result: .success(["gpt-5.2"]))
        let provider = provider(idSuffix: "601")
        let viewModel = makeViewModel(modelLister: modelLister)
        viewModel.providers = [provider]
        viewModel.selectedProviderID = provider.id

        await viewModel.refreshSelectedProviderModels()

        XCTAssertEqual(modelLister.capturedProviders, [])
        XCTAssertEqual(viewModel.availableModelIDs(for: provider.id), [])
        XCTAssertEqual(viewModel.statusMessage, "Save an API key before refreshing models.")
        XCTAssertTrue(viewModel.hasError)
        XCTAssertFalse(viewModel.isLoadingModelList)
    }

    func testAddingImportingAndDisconnectingChatGPTSubscriptionProvider() {
        let credentialStore = InMemoryChatGPTCredentialStore()
        let importer = MockChatGPTCredentialImporter(
            credential: ChatGPTSubscriptionCredential(
                accessToken: "access-token",
                accountID: "account-id",
                expiresAt: nil,
                sourceDescription: "/tmp/auth.json"
            )
        )
        let viewModel = makeViewModel(
            chatGPTCredentialStore: credentialStore,
            chatGPTCredentialImporter: importer
        )

        let providerID = viewModel.addChatGPTSubscriptionProvider()

        guard let provider = viewModel.providers.first else {
            return XCTFail("Expected provider.")
        }
        XCTAssertEqual(provider.id, providerID)
        XCTAssertEqual(provider.category, .subscription)
        XCTAssertEqual(provider.kind, .chatGPTSubscription)
        XCTAssertEqual(viewModel.selectedProviderCredentialStatus.text, "Login Required")

        viewModel.importSelectedChatGPTSubscription()

        XCTAssertEqual(credentialStore.credentialsByServiceName[provider.keychainServiceName]?.accountID, "account-id")
        XCTAssertEqual(viewModel.selectedChatGPTAccountID, "account-id")
        XCTAssertEqual(viewModel.selectedProviderCredentialStatus.text, "ChatGPT Connected")
        XCTAssertEqual(viewModel.statusMessage, "Imported ChatGPT subscription login to Keychain.")

        viewModel.disconnectSelectedChatGPTSubscription()

        XCTAssertNil(credentialStore.credentialsByServiceName[provider.keychainServiceName])
        XCTAssertNil(viewModel.selectedChatGPTAccountID)
        XCTAssertEqual(viewModel.selectedProviderCredentialStatus.text, "Login Required")
    }

    func testRefreshingChatGPTSubscriptionModelsUsesStoredSubscriptionCredential() async {
        let credentialStore = InMemoryChatGPTCredentialStore()
        let modelLister = MockProviderModelLister(result: .success(["gpt-5.2", "gpt-5.3-codex"]))
        let provider = LLMProviderConfig.defaultChatGPTSubscription(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000701")!
        )
        credentialStore.credentialsByServiceName[provider.keychainServiceName] = ChatGPTSubscriptionCredential(
            accessToken: "access-token",
            accountID: "account-id",
            expiresAt: nil,
            sourceDescription: nil
        )
        let viewModel = makeViewModel(
            chatGPTCredentialStore: credentialStore,
            modelLister: modelLister
        )
        viewModel.providers = [provider]
        viewModel.selectedProviderID = provider.id

        await viewModel.refreshSelectedProviderModels()

        XCTAssertEqual(viewModel.availableModelIDs(for: provider.id), ["gpt-5.2", "gpt-5.3-codex"])
        XCTAssertEqual(modelLister.capturedProviders, [provider])
        XCTAssertEqual(
            modelLister.capturedCredentials,
            [.chatGPTSubscription(accessToken: "access-token", accountID: "account-id")]
        )
        XCTAssertEqual(viewModel.statusMessage, "Loaded 2 models.")
        XCTAssertFalse(viewModel.hasError)
    }

    func testExpiredChatGPTSubscriptionCredentialRequiresImportBeforeModelRefresh() async {
        let credentialStore = InMemoryChatGPTCredentialStore()
        let modelLister = MockProviderModelLister(result: .success(["gpt-5.2"]))
        let provider = LLMProviderConfig.defaultChatGPTSubscription(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000702")!
        )
        credentialStore.credentialsByServiceName[provider.keychainServiceName] = ChatGPTSubscriptionCredential(
            accessToken: "expired-access-token",
            accountID: "expired-account-id",
            expiresAt: Date(timeIntervalSince1970: 1),
            sourceDescription: nil
        )
        let viewModel = makeViewModel(
            chatGPTCredentialStore: credentialStore,
            modelLister: modelLister
        )
        viewModel.providers = [provider]
        viewModel.selectedProviderID = provider.id

        XCTAssertNil(viewModel.selectedChatGPTAccountID)
        XCTAssertEqual(viewModel.selectedProviderCredentialStatus.text, "Login Required")

        await viewModel.refreshSelectedProviderModels()

        XCTAssertEqual(modelLister.capturedProviders, [])
        XCTAssertEqual(viewModel.statusMessage, "Import ChatGPT login before refreshing models.")
        XCTAssertTrue(viewModel.hasError)
    }

    private func makeViewModel(
        apiKeyStore: InMemoryProviderAPIKeyStore = InMemoryProviderAPIKeyStore(),
        chatGPTCredentialStore: InMemoryChatGPTCredentialStore = InMemoryChatGPTCredentialStore(),
        chatGPTCredentialImporter: any ChatGPTSubscriptionCredentialImporting = MockChatGPTCredentialImporter(
            credential: ChatGPTSubscriptionCredential(
                accessToken: "unused-access-token",
                accountID: "unused-account-id",
                expiresAt: nil,
                sourceDescription: nil
            )
        ),
        modelLister: any LLMProviderModelListing = MockProviderModelLister(result: .success([]))
    ) -> ProviderSettingsViewModel {
        ProviderSettingsViewModel(
            store: LLMProviderStore(fileURL: temporaryDirectory.appendingPathComponent("providers.json")),
            apiKeyStore: apiKeyStore,
            chatGPTCredentialStore: chatGPTCredentialStore,
            chatGPTCredentialImporter: chatGPTCredentialImporter,
            modelLister: modelLister
        )
    }

    private func provider(
        idSuffix: String,
        name: String = "Provider"
    ) -> LLMProviderConfig {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000\(idSuffix)")!
        return LLMProviderConfig.defaultOpenAICompatible(
            id: id,
            name: name,
            defaultModel: "model-\(idSuffix)"
        )
    }
}

private final class InMemoryProviderAPIKeyStore: LLMProviderAPIKeyStoring {
    var apiKeysByServiceName: [String: String] = [:]
    var deletedServiceNames: [String] = []

    func saveAPIKey(_ apiKey: String, for provider: LLMProviderConfig) throws {
        apiKeysByServiceName[provider.keychainServiceName] = apiKey
    }

    func readAPIKey(for provider: LLMProviderConfig) throws -> String? {
        apiKeysByServiceName[provider.keychainServiceName]
    }

    func deleteAPIKey(for provider: LLMProviderConfig) throws {
        deletedServiceNames.append(provider.keychainServiceName)
        apiKeysByServiceName.removeValue(forKey: provider.keychainServiceName)
    }
}

private final class InMemoryChatGPTCredentialStore: ChatGPTSubscriptionCredentialStoring {
    var credentialsByServiceName: [String: ChatGPTSubscriptionCredential] = [:]
    var deletedServiceNames: [String] = []

    func saveChatGPTSubscriptionCredential(
        _ credential: ChatGPTSubscriptionCredential,
        for provider: LLMProviderConfig
    ) throws {
        credentialsByServiceName[provider.keychainServiceName] = credential
    }

    func readChatGPTSubscriptionCredential(
        for provider: LLMProviderConfig
    ) throws -> ChatGPTSubscriptionCredential? {
        credentialsByServiceName[provider.keychainServiceName]
    }

    func deleteChatGPTSubscriptionCredential(for provider: LLMProviderConfig) throws {
        deletedServiceNames.append(provider.keychainServiceName)
        credentialsByServiceName.removeValue(forKey: provider.keychainServiceName)
    }
}

private struct MockChatGPTCredentialImporter: ChatGPTSubscriptionCredentialImporting {
    var credential: ChatGPTSubscriptionCredential

    func importCredential() throws -> ChatGPTSubscriptionCredential {
        credential
    }
}

private final class MockProviderModelLister: LLMProviderModelListing {
    private let result: Result<[String], Error>
    private(set) var capturedProviders: [LLMProviderConfig] = []
    private(set) var capturedCredentials: [LLMCredential] = []

    init(result: Result<[String], Error>) {
        self.result = result
    }

    func listModels(
        provider: LLMProviderConfig,
        credential: LLMCredential
    ) async throws -> [String] {
        capturedProviders.append(provider)
        capturedCredentials.append(credential)
        return try result.get()
    }
}
