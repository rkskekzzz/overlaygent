import Foundation
import Security

final class KeychainStore: LLMProviderAPIKeyStoring {
    private static let apiKeyAccount = "api-key"

    private let itemStore: KeychainItemStoring
    private let cacheLock = NSLock()
    private var cachedAPIKeysByServiceName: [String: String] = [:]

    init(itemStore: KeychainItemStoring = SecurityKeychainItemStore()) {
        self.itemStore = itemStore
    }

    func saveAPIKey(_ apiKey: String, for provider: LLMProviderConfig) throws {
        try saveAPIKey(apiKey, serviceName: provider.keychainServiceName)
    }

    func readAPIKey(for provider: LLMProviderConfig) throws -> String? {
        try readAPIKey(serviceName: provider.keychainServiceName)
    }

    func deleteAPIKey(for provider: LLMProviderConfig) throws {
        try deleteAPIKey(serviceName: provider.keychainServiceName)
    }

    func saveAPIKey(_ apiKey: String, serviceName: String) throws {
        guard let data = apiKey.data(using: .utf8) else {
            throw KeychainStoreError.invalidAPIKeyEncoding
        }

        try itemStore.saveGenericPassword(
            data,
            service: serviceName,
            account: Self.apiKeyAccount
        )
        cacheAPIKey(apiKey, serviceName: serviceName)
    }

    func readAPIKey(serviceName: String) throws -> String? {
        if let cachedAPIKey = cachedAPIKey(serviceName: serviceName) {
            return cachedAPIKey
        }

        guard let data = try itemStore.readGenericPassword(
            service: serviceName,
            account: Self.apiKeyAccount
        ) else {
            return nil
        }

        guard let apiKey = String(data: data, encoding: .utf8) else {
            throw KeychainStoreError.invalidStoredAPIKeyData
        }

        cacheAPIKey(apiKey, serviceName: serviceName)
        return apiKey
    }

    func deleteAPIKey(serviceName: String) throws {
        try itemStore.deleteGenericPassword(
            service: serviceName,
            account: Self.apiKeyAccount
        )
        removeCachedAPIKey(serviceName: serviceName)
    }

    private func cachedAPIKey(serviceName: String) -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cachedAPIKeysByServiceName[serviceName]
    }

    private func cacheAPIKey(_ apiKey: String, serviceName: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cachedAPIKeysByServiceName[serviceName] = apiKey
    }

    private func removeCachedAPIKey(serviceName: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cachedAPIKeysByServiceName[serviceName] = nil
    }
}

protocol KeychainItemStoring {
    func saveGenericPassword(_ data: Data, service: String, account: String) throws
    func readGenericPassword(service: String, account: String) throws -> Data?
    func deleteGenericPassword(service: String, account: String) throws
}

struct SecurityKeychainItemStore: KeychainItemStoring {
    func saveGenericPassword(_ data: Data, service: String, account: String) throws {
        let query = baseQuery(service: service, account: account)
        let updateAttributes = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            updateAttributes as CFDictionary
        )

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            break
        default:
            throw KeychainStoreError.keychainOperationFailed(
                operation: .save,
                status: updateStatus
            )
        }

        var addAttributes = query
        addAttributes[kSecValueData as String] = data
        addAttributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        addAttributes[kSecAttrSynchronizable as String] = kCFBooleanFalse

        let addStatus = SecItemAdd(addAttributes as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            try updateExistingGenericPassword(data, service: service, account: account)
            return
        }

        guard addStatus == errSecSuccess else {
            throw KeychainStoreError.keychainOperationFailed(
                operation: .save,
                status: addStatus
            )
        }
    }

    func readGenericPassword(service: String, account: String) throws -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainStoreError.invalidStoredAPIKeyData
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainStoreError.keychainOperationFailed(
                operation: .read,
                status: status
            )
        }
    }

    func deleteGenericPassword(service: String, account: String) throws {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)

        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw KeychainStoreError.keychainOperationFailed(
                operation: .delete,
                status: status
            )
        }
    }

    private func updateExistingGenericPassword(
        _ data: Data,
        service: String,
        account: String
    ) throws {
        let status = SecItemUpdate(
            baseQuery(service: service, account: account) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        guard status == errSecSuccess else {
            throw KeychainStoreError.keychainOperationFailed(
                operation: .save,
                status: status
            )
        }
    }

    private func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
    }
}

enum KeychainOperation: String {
    case save
    case read
    case delete
}

enum KeychainStoreError: Error, Equatable {
    case invalidAPIKeyEncoding
    case invalidStoredAPIKeyData
    case keychainOperationFailed(operation: KeychainOperation, status: OSStatus)
}

extension KeychainStoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidAPIKeyEncoding:
            return "The API key could not be encoded for Keychain storage."
        case .invalidStoredAPIKeyData:
            return "The stored API key could not be decoded from Keychain data."
        case let .keychainOperationFailed(operation, status):
            return "Keychain \(operation.rawValue) failed with status \(status)."
        }
    }
}
