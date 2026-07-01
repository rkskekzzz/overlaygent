import Foundation
import XCTest
@testable import Overlaygent

final class KeychainStoreTests: XCTestCase {
    func testSaveAndReadAPIKeyRoundTripsThroughInjectedStore() throws {
        let itemStore = InMemoryKeychainItemStore()
        let keychainStore = KeychainStore(itemStore: itemStore)
        let provider = makeProvider(serviceName: "test.service.primary")

        try keychainStore.saveAPIKey("sk-test-secret", for: provider)

        XCTAssertEqual(try keychainStore.readAPIKey(for: provider), "sk-test-secret")
    }

    func testSaveOverwritesExistingAPIKeyForProvider() throws {
        let itemStore = InMemoryKeychainItemStore()
        let keychainStore = KeychainStore(itemStore: itemStore)
        let provider = makeProvider(serviceName: "test.service.overwrite")

        try keychainStore.saveAPIKey("first-secret", for: provider)
        try keychainStore.saveAPIKey("second-secret", for: provider)

        XCTAssertEqual(try keychainStore.readAPIKey(for: provider), "second-secret")
    }

    func testSaveCachesAPIKeyWithoutImmediateKeychainRead() throws {
        let itemStore = InMemoryKeychainItemStore()
        let keychainStore = KeychainStore(itemStore: itemStore)

        try keychainStore.saveAPIKey("sk-cached-secret", serviceName: "test.service.save-cache")

        XCTAssertEqual(try keychainStore.readAPIKey(serviceName: "test.service.save-cache"), "sk-cached-secret")
        XCTAssertTrue(itemStore.readRequests.isEmpty)
    }

    func testReadAPIKeyUsesInMemoryCacheAfterFirstKeychainRead() throws {
        let itemStore = InMemoryKeychainItemStore()
        let keychainStore = KeychainStore(itemStore: itemStore)
        try itemStore.saveGenericPassword(
            Data("sk-read-cache".utf8),
            service: "test.service.read-cache",
            account: "api-key"
        )

        XCTAssertEqual(try keychainStore.readAPIKey(serviceName: "test.service.read-cache"), "sk-read-cache")
        XCTAssertEqual(try keychainStore.readAPIKey(serviceName: "test.service.read-cache"), "sk-read-cache")
        XCTAssertEqual(itemStore.readRequests.count, 1)
    }

    func testProvidersAreIsolatedByKeychainServiceName() throws {
        let itemStore = InMemoryKeychainItemStore()
        let keychainStore = KeychainStore(itemStore: itemStore)
        let firstProvider = makeProvider(serviceName: "test.service.first")
        let secondProvider = makeProvider(serviceName: "test.service.second")

        try keychainStore.saveAPIKey("first-secret", for: firstProvider)
        try keychainStore.saveAPIKey("second-secret", for: secondProvider)

        XCTAssertEqual(try keychainStore.readAPIKey(for: firstProvider), "first-secret")
        XCTAssertEqual(try keychainStore.readAPIKey(for: secondProvider), "second-secret")
    }

    func testChatGPTSubscriptionCredentialRoundTripsSeparatelyFromAPIKey() throws {
        let itemStore = InMemoryKeychainItemStore()
        let keychainStore = KeychainStore(itemStore: itemStore)
        let provider = LLMProviderConfig.defaultChatGPTSubscription(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000701")!
        )
        let credential = ChatGPTSubscriptionCredential(
            accessToken: "access-token",
            accountID: "account-id",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
            sourceDescription: "/Users/example/.codex/auth.json"
        )

        try keychainStore.saveAPIKey("sk-api-secret", serviceName: provider.keychainServiceName)
        try keychainStore.saveChatGPTSubscriptionCredential(credential, for: provider)

        XCTAssertEqual(try keychainStore.readAPIKey(serviceName: provider.keychainServiceName), "sk-api-secret")
        XCTAssertEqual(try keychainStore.readChatGPTSubscriptionCredential(for: provider), credential)

        try keychainStore.deleteChatGPTSubscriptionCredential(for: provider)

        XCTAssertNil(try keychainStore.readChatGPTSubscriptionCredential(for: provider))
        XCTAssertEqual(try keychainStore.readAPIKey(serviceName: provider.keychainServiceName), "sk-api-secret")
    }

    func testDeleteAPIKeyRemovesStoredSecretAndIsIdempotent() throws {
        let itemStore = InMemoryKeychainItemStore()
        let keychainStore = KeychainStore(itemStore: itemStore)
        let provider = makeProvider(serviceName: "test.service.delete")

        try keychainStore.saveAPIKey("delete-me", for: provider)
        try keychainStore.deleteAPIKey(for: provider)
        try keychainStore.deleteAPIKey(for: provider)

        XCTAssertNil(try keychainStore.readAPIKey(for: provider))
    }

    func testReadReturnsNilWhenAPIKeyIsMissing() throws {
        let keychainStore = KeychainStore(itemStore: InMemoryKeychainItemStore())

        XCTAssertNil(try keychainStore.readAPIKey(serviceName: "test.service.missing"))
    }

    func testInvalidStoredDataThrowsDecodeError() throws {
        let itemStore = InMemoryKeychainItemStore()
        let keychainStore = KeychainStore(itemStore: itemStore)
        try itemStore.saveGenericPassword(
            Data([0xFF, 0xFE]),
            service: "test.service.invalid-data",
            account: "api-key"
        )

        XCTAssertThrowsError(try keychainStore.readAPIKey(serviceName: "test.service.invalid-data")) { error in
            XCTAssertEqual(error as? KeychainStoreError, .invalidStoredAPIKeyData)
        }
    }

    func testKeychainErrorsDoNotIncludePlaintextAPIKey() {
        let itemStore = FailingKeychainItemStore(
            error: KeychainStoreError.keychainOperationFailed(operation: .save, status: -1)
        )
        let keychainStore = KeychainStore(itemStore: itemStore)
        let secret = "sk-secret-that-must-not-appear"

        XCTAssertThrowsError(try keychainStore.saveAPIKey(secret, serviceName: "test.service.failure")) { error in
            XCTAssertFalse(String(describing: error).contains(secret))
            XCTAssertFalse((error as NSError).localizedDescription.contains(secret))
        }
    }

    private func makeProvider(serviceName: String) -> LLMProviderConfig {
        LLMProviderConfig(
            id: UUID(),
            name: "Test Provider",
            baseURL: URL(string: "https://example.com/v1")!,
            defaultModel: "test-model",
            temperature: 0.2,
            maxTokens: 1_000,
            timeoutSeconds: 30,
            keychainServiceName: serviceName
        )
    }
}

private final class InMemoryKeychainItemStore: KeychainItemStoring {
    private struct Key: Hashable {
        var service: String
        var account: String
    }

    private(set) var readRequests: [(service: String, account: String)] = []
    private var storage: [Key: Data] = [:]

    func saveGenericPassword(_ data: Data, service: String, account: String) throws {
        storage[Key(service: service, account: account)] = data
    }

    func readGenericPassword(service: String, account: String) throws -> Data? {
        readRequests.append((service: service, account: account))
        return storage[Key(service: service, account: account)]
    }

    func deleteGenericPassword(service: String, account: String) throws {
        storage.removeValue(forKey: Key(service: service, account: account))
    }
}

private struct FailingKeychainItemStore: KeychainItemStoring {
    let error: Error

    func saveGenericPassword(_ data: Data, service: String, account: String) throws {
        throw error
    }

    func readGenericPassword(service: String, account: String) throws -> Data? {
        throw error
    }

    func deleteGenericPassword(service: String, account: String) throws {
        throw error
    }
}
