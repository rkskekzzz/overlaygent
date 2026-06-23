import Foundation

protocol LLMResponseCaching: AnyObject {
    func cachedRawResponse(
        forCacheKey cacheKey: String,
        now: Date
    ) throws -> String?

    func storeRawResponse(
        _ rawResponse: String,
        forCacheKey cacheKey: String,
        now: Date
    ) throws

    func removeExpiredResponses(now: Date) throws
}

final class NoopLLMResponseCache: LLMResponseCaching {
    func cachedRawResponse(
        forCacheKey cacheKey: String,
        now: Date
    ) throws -> String? {
        nil
    }

    func storeRawResponse(
        _ rawResponse: String,
        forCacheKey cacheKey: String,
        now: Date
    ) throws {}

    func removeExpiredResponses(now: Date) throws {}
}
