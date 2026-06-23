import Foundation
import SQLite3

enum SQLiteLLMResponseCacheError: Error, CustomStringConvertible {
    case openFailed(String)
    case prepareFailed(String)
    case executeFailed(String)
    case bindFailed(String)
    case stepFailed(String)

    var description: String {
        switch self {
        case let .openFailed(message):
            return "Could not open LLM response cache: \(message)"
        case let .prepareFailed(message):
            return "Could not prepare LLM response cache statement: \(message)"
        case let .executeFailed(message):
            return "Could not execute LLM response cache statement: \(message)"
        case let .bindFailed(message):
            return "Could not bind LLM response cache statement: \(message)"
        case let .stepFailed(message):
            return "Could not step LLM response cache statement: \(message)"
        }
    }
}

final class SQLiteLLMResponseCache: LLMResponseCaching {
    static let defaultFileName = "llm-response-cache.sqlite3"
    static let defaultTTL: TimeInterval = 30 * 24 * 60 * 60

    private let fileURL: URL
    private let fileManager: FileManager
    private let ttl: TimeInterval
    private let lock = NSLock()

    init(
        fileURL: URL = SQLiteLLMResponseCache.defaultFileURL(),
        fileManager: FileManager = .default,
        ttl: TimeInterval = SQLiteLLMResponseCache.defaultTTL
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.ttl = ttl
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        ApplicationSupportPaths(fileManager: fileManager).fileURL(named: defaultFileName)
    }

    func cachedRawResponse(
        forCacheKey cacheKey: String,
        now: Date
    ) throws -> String? {
        try locked {
            let database = try openDatabase()
            defer { sqlite3_close(database) }
            try ensureSchema(database)
            try removeExpiredResponses(database: database, now: now)

            let statement = try prepare(
                """
                SELECT raw_response
                FROM llm_response_cache
                WHERE cache_key = ? AND expires_at > ?
                LIMIT 1;
                """,
                database: database
            )
            defer { sqlite3_finalize(statement) }

            try bind(cacheKey, at: 1, in: statement)
            try bind(now.timeIntervalSince1970, at: 2, in: statement)

            let stepResult = sqlite3_step(statement)
            guard stepResult == SQLITE_ROW else {
                guard stepResult == SQLITE_DONE else {
                    throw SQLiteLLMResponseCacheError.stepFailed(errorMessage(database))
                }
                return nil
            }

            guard let rawText = sqlite3_column_text(statement, 0) else {
                return nil
            }

            try updateLastAccessed(
                cacheKey: cacheKey,
                now: now,
                database: database
            )
            return String(cString: rawText)
        }
    }

    func storeRawResponse(
        _ rawResponse: String,
        forCacheKey cacheKey: String,
        now: Date
    ) throws {
        try locked {
            let database = try openDatabase()
            defer { sqlite3_close(database) }
            try ensureSchema(database)
            try removeExpiredResponses(database: database, now: now)

            let statement = try prepare(
                """
                INSERT OR REPLACE INTO llm_response_cache
                    (cache_key, raw_response, created_at, last_accessed_at, expires_at)
                VALUES (?, ?, ?, ?, ?);
                """,
                database: database
            )
            defer { sqlite3_finalize(statement) }

            let createdAt = now.timeIntervalSince1970
            try bind(cacheKey, at: 1, in: statement)
            try bind(rawResponse, at: 2, in: statement)
            try bind(createdAt, at: 3, in: statement)
            try bind(createdAt, at: 4, in: statement)
            try bind(createdAt + ttl, at: 5, in: statement)
            try stepDone(statement, database: database)
        }
    }

    func removeExpiredResponses(now: Date) throws {
        try locked {
            let database = try openDatabase()
            defer { sqlite3_close(database) }
            try ensureSchema(database)
            try removeExpiredResponses(database: database, now: now)
        }
    }

    private func locked<T>(_ operation: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }

    private func openDatabase() throws -> OpaquePointer {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(fileURL.path, &database, flags, nil)
        guard result == SQLITE_OK, let database else {
            let message = database.map(errorMessage) ?? "unknown sqlite open error"
            sqlite3_close(database)
            throw SQLiteLLMResponseCacheError.openFailed(message)
        }

        return database
    }

    private func ensureSchema(_ database: OpaquePointer) throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS llm_response_cache (
                cache_key TEXT PRIMARY KEY NOT NULL,
                raw_response TEXT NOT NULL,
                created_at REAL NOT NULL,
                last_accessed_at REAL NOT NULL,
                expires_at REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_llm_response_cache_expires_at
                ON llm_response_cache(expires_at);
            """,
            database: database
        )
    }

    private func removeExpiredResponses(database: OpaquePointer, now: Date) throws {
        let statement = try prepare(
            "DELETE FROM llm_response_cache WHERE expires_at <= ?;",
            database: database
        )
        defer { sqlite3_finalize(statement) }

        try bind(now.timeIntervalSince1970, at: 1, in: statement)
        try stepDone(statement, database: database)
    }

    private func updateLastAccessed(
        cacheKey: String,
        now: Date,
        database: OpaquePointer
    ) throws {
        let statement = try prepare(
            "UPDATE llm_response_cache SET last_accessed_at = ? WHERE cache_key = ?;",
            database: database
        )
        defer { sqlite3_finalize(statement) }

        try bind(now.timeIntervalSince1970, at: 1, in: statement)
        try bind(cacheKey, at: 2, in: statement)
        try stepDone(statement, database: database)
    }

    private func execute(_ sql: String, database: OpaquePointer) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorPointer)
        guard result == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? errorMessage(database)
            sqlite3_free(errorPointer)
            throw SQLiteLLMResponseCacheError.executeFailed(message)
        }
    }

    private func prepare(_ sql: String, database: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw SQLiteLLMResponseCacheError.prepareFailed(errorMessage(database))
        }
        return statement
    }

    private func bind(_ value: String, at index: Int32, in statement: OpaquePointer) throws {
        let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, index, value, -1, sqliteTransient) == SQLITE_OK else {
            throw SQLiteLLMResponseCacheError.bindFailed("text at index \(index)")
        }
    }

    private func bind(_ value: TimeInterval, at index: Int32, in statement: OpaquePointer) throws {
        guard sqlite3_bind_double(statement, index, value) == SQLITE_OK else {
            throw SQLiteLLMResponseCacheError.bindFailed("double at index \(index)")
        }
    }

    private func stepDone(_ statement: OpaquePointer, database: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteLLMResponseCacheError.stepFailed(errorMessage(database))
        }
    }

    private func errorMessage(_ database: OpaquePointer) -> String {
        sqlite3_errmsg(database).map { String(cString: $0) } ?? "unknown sqlite error"
    }
}
