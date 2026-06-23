import Foundation

protocol LLMResponseCacheKeyMaking {
    func cacheKey(
        for bundle: AgentMessageBundle,
        provider: LLMProviderConfig
    ) throws -> String
}

enum LLMResponseCacheKeyFactoryError: Error {
    case encodeFailed
}

struct LLMResponseCacheKeyFactory: LLMResponseCacheKeyMaking {
    private let encoder: JSONEncoder
    private let hasher: TextSnapshotHasher

    init(
        encoder: JSONEncoder = JSONEncoder(),
        hasher: TextSnapshotHasher = TextSnapshotHasher()
    ) {
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.hasher = hasher
    }

    func cacheKey(
        for bundle: AgentMessageBundle,
        provider: LLMProviderConfig
    ) throws -> String {
        let payload = LLMResponseCacheKeyPayload(
            bundle: LLMResponseCacheBundleFingerprint(bundle),
            provider: LLMResponseCacheProviderFingerprint(
                id: provider.id.uuidString,
                baseURL: provider.baseURL.absoluteString,
                defaultModel: provider.defaultModel,
                temperature: provider.temperature,
                maxTokens: provider.maxTokens
            )
        )

        guard let json = try? encoder.encode(payload),
              let string = String(data: json, encoding: .utf8) else {
            throw LLMResponseCacheKeyFactoryError.encodeFailed
        }

        return hasher.hash(text: string)
    }
}

private struct LLMResponseCacheKeyPayload: Encodable {
    var version = 2
    var bundle: LLMResponseCacheBundleFingerprint
    var provider: LLMResponseCacheProviderFingerprint
}

private struct LLMResponseCacheBundleFingerprint: Encodable {
    var agentID: UUID
    var agentName: String
    var providerID: UUID
    var resolvedModel: String?
    var messages: [AgentMessage]
    var outputSchemaID: String
    var budgetMetadata: AgentMessageBudgetMetadata

    init(_ bundle: AgentMessageBundle) {
        self.agentID = bundle.agentID
        self.agentName = bundle.agentName
        self.providerID = bundle.providerID
        self.resolvedModel = bundle.resolvedModel
        self.messages = bundle.messages.map(Self.normalizedMessage)
        self.outputSchemaID = bundle.outputSchemaID
        self.budgetMetadata = bundle.budgetMetadata
    }

    private static func normalizedMessage(_ message: AgentMessage) -> AgentMessage {
        guard message.role == .user else {
            return message
        }

        return AgentMessage(
            role: message.role,
            content: message.content
                .components(separatedBy: "\n")
                .map { line in
                    line.hasPrefix("Selected range:")
                        ? "Selected range: <ignored for cache>"
                        : line
                }
                .joined(separator: "\n")
        )
    }
}

private struct LLMResponseCacheProviderFingerprint: Encodable {
    var id: String
    var baseURL: String
    var defaultModel: String
    var temperature: Double
    var maxTokens: Int
}
