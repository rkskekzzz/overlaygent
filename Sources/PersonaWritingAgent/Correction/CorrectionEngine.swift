import Foundation

protocol LLMProviderConfigLoading {
    func loadProviders() throws -> [LLMProviderConfig]
}

extension LLMProviderStore: LLMProviderConfigLoading {}

enum AgentCorrectionFailure: Error, Equatable, CustomStringConvertible {
    case missingProvider(providerID: UUID)
    case missingAPIKey(providerID: UUID)
    case apiKeyLoadFailed(providerID: UUID)
    case providerFailed(providerID: UUID, reason: String)
    case parseFailed(providerID: UUID)

    var description: String {
        switch self {
        case .missingProvider(let providerID):
            return "LLM provider configuration is missing for provider \(providerID.uuidString)."
        case .missingAPIKey(let providerID):
            return "LLM provider API key is missing for provider \(providerID.uuidString)."
        case .apiKeyLoadFailed(let providerID):
            return "LLM provider API key could not be loaded for provider \(providerID.uuidString)."
        case let .providerFailed(providerID, reason):
            return "LLM provider request failed for provider \(providerID.uuidString): \(reason)"
        case .parseFailed(let providerID):
            return "LLM provider response could not be parsed for provider \(providerID.uuidString)."
        }
    }
}

struct AgentCorrectionResult: Equatable {
    var agentID: UUID
    var agentName: String
    var providerID: UUID
    var result: CorrectionResult?
    var rawResponse: String?
    var failure: AgentCorrectionFailure?

    var isSuccess: Bool {
        result != nil && failure == nil
    }
}

struct CorrectionEngine {
    private let privacyGuard: PrivacyGuard
    private let messageFactory: AgentMessageFactory
    private let providerConfigLoader: any LLMProviderConfigLoading
    private let apiKeyStore: any LLMProviderAPIKeyStoring
    private let llmProvider: any LLMProvider
    private let responseCache: any LLMResponseCaching
    private let parser: CorrectionResultParser
    private let now: () -> Date

    init(
        providerConfigLoader: any LLMProviderConfigLoading,
        apiKeyStore: any LLMProviderAPIKeyStoring,
        llmProvider: any LLMProvider,
        responseCache: any LLMResponseCaching = NoopLLMResponseCache(),
        privacyGuard: PrivacyGuard = PrivacyGuard(),
        messageFactory: AgentMessageFactory = AgentMessageFactory(),
        parser: CorrectionResultParser = CorrectionResultParser(),
        now: @escaping () -> Date = Date.init
    ) {
        self.privacyGuard = privacyGuard
        self.messageFactory = messageFactory
        self.providerConfigLoader = providerConfigLoader
        self.apiKeyStore = apiKeyStore
        self.llmProvider = llmProvider
        self.responseCache = responseCache
        self.parser = parser
        self.now = now
    }

    func run(_ request: AgentRunRequest) async throws -> [AgentCorrectionResult] {
        let sanitizedRequest = try privacyGuard.validateAndRedact(request)
        let providerConfigs = try providerConfigLoader.loadProviders()
        let providersByID = Dictionary(
            providerConfigs.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var results: [AgentCorrectionResult] = []
        for bundle in messageFactory.makeBundles(for: sanitizedRequest) {
            try Task.checkCancellation()
            results.append(try await correctionResult(for: bundle, providersByID: providersByID))
        }

        return results
    }

    private func correctionResult(
        for bundle: AgentMessageBundle,
        providersByID: [UUID: LLMProviderConfig]
    ) async throws -> AgentCorrectionResult {
        guard let providerConfig = providersByID[bundle.providerID] else {
            return failedResult(for: bundle, failure: .missingProvider(providerID: bundle.providerID))
        }

        if let cachedRawResponse = try? responseCache.cachedRawResponse(
            for: bundle,
            provider: providerConfig,
            now: now()
        ),
           let cachedResult = parsedResult(
               rawResponse: cachedRawResponse,
               for: bundle
           ) {
            return cachedResult
        }

        let apiKey: String?
        do {
            apiKey = try apiKeyStore.readAPIKey(for: providerConfig)
        } catch {
            return failedResult(for: bundle, failure: .apiKeyLoadFailed(providerID: bundle.providerID))
        }

        guard apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return failedResult(for: bundle, failure: .missingAPIKey(providerID: bundle.providerID))
        }

        let rawResponse: String
        do {
            rawResponse = try await llmProvider.complete(
                bundle: bundle,
                provider: providerConfig,
                apiKey: apiKey
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return failedResult(
                for: bundle,
                failure: .providerFailed(
                    providerID: bundle.providerID,
                    reason: Self.safeProviderFailureReason(error)
                )
            )
        }

        guard let result = parsedResult(rawResponse: rawResponse, for: bundle) else {
            return failedResult(for: bundle, failure: .parseFailed(providerID: bundle.providerID))
        }

        try? responseCache.storeRawResponse(
            rawResponse,
            for: bundle,
            provider: providerConfig,
            now: now()
        )
        return result
    }

    private func parsedResult(
        rawResponse: String,
        for bundle: AgentMessageBundle
    ) -> AgentCorrectionResult? {
        guard let parsedResult = try? parser.parse(rawResponse) else {
            return nil
        }

        return AgentCorrectionResult(
            agentID: bundle.agentID,
            agentName: bundle.agentName,
            providerID: bundle.providerID,
            result: parsedResult,
            rawResponse: rawResponse,
            failure: nil
        )
    }

    private func failedResult(
        for bundle: AgentMessageBundle,
        failure: AgentCorrectionFailure
    ) -> AgentCorrectionResult {
        AgentCorrectionResult(
            agentID: bundle.agentID,
            agentName: bundle.agentName,
            providerID: bundle.providerID,
            result: nil,
            rawResponse: nil,
            failure: failure
        )
    }

    private static func safeProviderFailureReason(_ error: Error) -> String {
        if let providerError = error as? LLMProviderError {
            return providerError.description
        }

        return SafeLogger.redacted(String(describing: error))
    }
}
