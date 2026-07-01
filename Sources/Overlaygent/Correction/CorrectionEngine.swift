import Foundation

protocol LLMProviderConfigLoading {
    func loadProviders() throws -> [LLMProviderConfig]
}

extension LLMProviderStore: LLMProviderConfigLoading {}

enum AgentCorrectionFailure: Error, Equatable, CustomStringConvertible {
    case missingProvider(providerID: UUID)
    case missingAPIKey(providerID: UUID)
    case apiKeyLoadFailed(providerID: UUID)
    case missingCredential(providerID: UUID, mode: LLMProviderAuthMode)
    case credentialLoadFailed(providerID: UUID, reason: String)
    case loginRequired(providerID: UUID)
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
        case let .missingCredential(providerID, mode):
            return "LLM provider credential is missing for provider \(providerID.uuidString) using \(mode.rawValue) auth."
        case let .credentialLoadFailed(providerID, reason):
            return "LLM provider credential could not be loaded for provider \(providerID.uuidString): \(reason)"
        case .loginRequired(let providerID):
            return "LLM provider requires ChatGPT subscription login for provider \(providerID.uuidString)."
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

protocol AgentCorrectionRuntime {
    func correctionResult(
        for bundle: AgentMessageBundle,
        providersByID: [UUID: LLMProviderConfig]
    ) async throws -> AgentCorrectionResult
}

struct LLMProviderCorrectionRuntime: AgentCorrectionRuntime {
    private let credentialResolver: any LLMProviderCredentialResolving
    private let llmProvider: any LLMProvider
    private let responseCache: any LLMResponseCaching
    private let responseCacheKeyFactory: any LLMResponseCacheKeyMaking
    private let parser: CorrectionResultParser
    private let now: () -> Date

    init(
        credentialResolver: any LLMProviderCredentialResolving,
        llmProvider: any LLMProvider,
        responseCache: any LLMResponseCaching = NoopLLMResponseCache(),
        responseCacheKeyFactory: any LLMResponseCacheKeyMaking = LLMResponseCacheKeyFactory(),
        parser: CorrectionResultParser = CorrectionResultParser(),
        now: @escaping () -> Date = Date.init
    ) {
        self.credentialResolver = credentialResolver
        self.llmProvider = llmProvider
        self.responseCache = responseCache
        self.responseCacheKeyFactory = responseCacheKeyFactory
        self.parser = parser
        self.now = now
    }

    func correctionResult(
        for bundle: AgentMessageBundle,
        providersByID: [UUID: LLMProviderConfig]
    ) async throws -> AgentCorrectionResult {
        guard let providerConfig = providersByID[bundle.providerID] else {
            return failedResult(for: bundle, failure: .missingProvider(providerID: bundle.providerID))
        }

        let cacheKey = try? responseCacheKeyFactory.cacheKey(for: bundle, provider: providerConfig)
        if let cacheKey,
           let cachedRawResponse = try? responseCache.cachedRawResponse(
               forCacheKey: cacheKey,
               now: now()
           ),
           let cachedResult = parsedResult(
               rawResponse: cachedRawResponse,
               for: bundle
           ) {
            return cachedResult
        }

        let credential: LLMCredential
        do {
            credential = try await credentialResolver.credential(for: providerConfig)
        } catch let error as LLMProviderCredentialError {
            return failedResult(
                for: bundle,
                failure: credentialFailure(for: bundle.providerID, provider: providerConfig, error: error)
            )
        } catch {
            return failedResult(
                for: bundle,
                failure: .credentialLoadFailed(
                    providerID: bundle.providerID,
                    reason: SafeLogger.redacted(String(describing: error))
                )
            )
        }

        let rawResponse: String
        do {
            rawResponse = try await llmProvider.complete(
                bundle: bundle,
                provider: providerConfig,
                credential: credential
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

        if let cacheKey {
            try? responseCache.storeRawResponse(
                rawResponse,
                forCacheKey: cacheKey,
                now: now()
            )
        }
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

    private func credentialFailure(
        for providerID: UUID,
        provider: LLMProviderConfig,
        error: LLMProviderCredentialError
    ) -> AgentCorrectionFailure {
        switch error {
        case .missingCredential(let mode):
            if provider.auth.mode == .subscriptionOAuth {
                return .loginRequired(providerID: providerID)
            }
            if mode == .apiKey {
                return .missingAPIKey(providerID: providerID)
            }
            return .missingCredential(providerID: providerID, mode: mode)
        case .unsupportedAuthMode:
            return .credentialLoadFailed(providerID: providerID, reason: error.localizedDescription)
        }
    }
}

struct CorrectionEngine {
    private let privacyGuard: PrivacyGuard
    private let messageFactory: AgentMessageFactory
    private let providerConfigLoader: any LLMProviderConfigLoading
    private let runtime: any AgentCorrectionRuntime

    init(
        providerConfigLoader: any LLMProviderConfigLoading,
        apiKeyStore: any LLMProviderAPIKeyStoring,
        chatGPTCredentialStore: (any ChatGPTSubscriptionCredentialStoring)? = nil,
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
        let credentialStore = chatGPTCredentialStore ?? apiKeyStore as? any ChatGPTSubscriptionCredentialStoring
        let resolver = DefaultLLMProviderCredentialResolver(
            apiKeyStore: apiKeyStore,
            chatGPTCredentialStore: credentialStore ?? NoopChatGPTSubscriptionCredentialStore()
        )
        self.runtime = LLMProviderCorrectionRuntime(
            credentialResolver: resolver,
            llmProvider: llmProvider,
            responseCache: responseCache,
            parser: parser,
            now: now
        )
    }

    init(
        providerConfigLoader: any LLMProviderConfigLoading,
        credentialResolver: any LLMProviderCredentialResolving,
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
        self.runtime = LLMProviderCorrectionRuntime(
            credentialResolver: credentialResolver,
            llmProvider: llmProvider,
            responseCache: responseCache,
            parser: parser,
            now: now
        )
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
            results.append(
                try await runtime.correctionResult(
                    for: bundle,
                    providersByID: providersByID
                )
            )
        }

        return results
    }
}
