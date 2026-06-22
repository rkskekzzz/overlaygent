import Foundation
import SwiftUI
import XCTest
@testable import PersonaWritingAgent

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

    private func makeViewModel(
        apiKeyStore: InMemoryProviderAPIKeyStore = InMemoryProviderAPIKeyStore()
    ) -> ProviderSettingsViewModel {
        ProviderSettingsViewModel(
            store: LLMProviderStore(fileURL: temporaryDirectory.appendingPathComponent("providers.json")),
            apiKeyStore: apiKeyStore
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
