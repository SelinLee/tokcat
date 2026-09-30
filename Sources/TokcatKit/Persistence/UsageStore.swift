import Foundation
import SQLite3

/// Errors surfaced by `UsageStore`.
public enum UsageStoreError: Error {
    case openFailed(String)
    case executionFailed(String)
}

/// Local-only SQLite persistence for usage events and adapter read offsets.
/// No network I/O ever happens here — this is the whole point of the
/// "local-first" design.
// All database access after initialization is serialized by `queue`.
public final class UsageStore: @unchecked Sendable {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.tokcat.usage-store")

    public init(fileURL: URL) throws {
        var handle: OpaquePointer?
        let result = sqlite3_open(fileURL.path, &handle)
        guard result == SQLITE_OK, let handle else {
            let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            throw UsageStoreError.openFailed(message)
        }
        db = handle
        try migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    public static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tokcat", isDirectory: true)
        try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("tokcat.sqlite3")
    }

    private func migrate() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS adapter_offset (
                file_path TEXT PRIMARY KEY,
                byte_offset INTEGER NOT NULL
            );
            """)
        try exec("""
            CREATE TABLE IF NOT EXISTS token_event (
                timestamp REAL NOT NULL,
                source TEXT NOT NULL,
                model TEXT NOT NULL,
                input_tokens INTEGER NOT NULL,
                output_tokens INTEGER NOT NULL,
                cached_tokens INTEGER NOT NULL,
                cost_usd REAL NOT NULL,
                latency_ms REAL
            );
            """)
        try addColumnIfNeeded(table: "token_event", column: "provider", ddl: "TEXT")
        try addColumnIfNeeded(table: "token_event", column: "provider_id", ddl: "TEXT")
        try addColumnIfNeeded(table: "token_event", column: "cost_is_estimated", ddl: "INTEGER NOT NULL DEFAULT 1")
        try addColumnIfNeeded(table: "token_event", column: "request_id", ddl: "TEXT")
        try addColumnIfNeeded(table: "token_event", column: "data_origin", ddl: "TEXT")
        try addColumnIfNeeded(table: "token_event", column: "cache_read_tokens", ddl: "INTEGER")
        try addColumnIfNeeded(table: "token_event", column: "cache_write_tokens", ddl: "INTEGER")
        // Backfill split cache columns from the legacy combined total once.
        // Unknown historical cache is treated as cache-read (conservative).
        try exec("""
            UPDATE token_event
            SET cache_read_tokens = cached_tokens
            WHERE cache_read_tokens IS NULL;
            """)
        try exec("""
            UPDATE token_event
            SET cache_write_tokens = 0
            WHERE cache_write_tokens IS NULL;
            """)
        try exec("""
            CREATE INDEX IF NOT EXISTS idx_token_event_ts ON token_event(timestamp);
            """)
        // Existing databases can retain retired pet tables. Only usage tables
        // are read or written; upgrading never deletes a user's local history.
    }

    // MARK: - Adapter offsets

    public func saveAdapterOffset(filePath: String, byteOffset: UInt64) throws {
        try queue.sync {
            let sql = """
                INSERT INTO adapter_offset (file_path, byte_offset)
                VALUES (?, ?)
                ON CONFLICT(file_path) DO UPDATE SET byte_offset = excluded.byte_offset;
                """
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            try prepare(sql, into: &statement)

            sqlite3_bind_text(statement, 1, filePath, -1, Self.transient)
            sqlite3_bind_int64(statement, 2, Int64(bitPattern: byteOffset))

            try step(statement)
        }
    }

    public func loadAdapterOffsets() throws -> [String: UInt64] {
        try queue.sync {
            let sql = "SELECT file_path, byte_offset FROM adapter_offset;"
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            try prepare(sql, into: &statement)

            var result: [String: UInt64] = [:]
            while sqlite3_step(statement) == SQLITE_ROW {
                let path = String(cString: sqlite3_column_text(statement, 0))
                let offset = UInt64(bitPattern: sqlite3_column_int64(statement, 1))
                result[path] = offset
            }
            return result
        }
    }

    // MARK: - Token events (history)

    public func appendTokenEvent(_ event: TokenEvent) throws {
        try queue.sync {
            let sql = """
                INSERT INTO token_event
                    (timestamp, source, model, input_tokens, output_tokens, cached_tokens,
                     cost_usd, latency_ms, provider, provider_id, cost_is_estimated,
                     request_id, data_origin, cache_read_tokens, cache_write_tokens)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            try prepare(sql, into: &statement)

            sqlite3_bind_double(statement, 1, event.timestamp.timeIntervalSince1970)
            sqlite3_bind_text(statement, 2, event.source.rawValue, -1, Self.transient)
            sqlite3_bind_text(statement, 3, event.model, -1, Self.transient)
            sqlite3_bind_int(statement, 4, Int32(event.inputTokens))
            sqlite3_bind_int(statement, 5, Int32(event.outputTokens))
            sqlite3_bind_int(statement, 6, Int32(event.cachedTokens))
            sqlite3_bind_double(statement, 7, event.costUSD)
            if let latencyMs = event.latencyMs {
                sqlite3_bind_double(statement, 8, latencyMs)
            } else {
                sqlite3_bind_null(statement, 8)
            }
            if let provider = event.provider {
                sqlite3_bind_text(statement, 9, provider, -1, Self.transient)
            } else {
                sqlite3_bind_null(statement, 9)
            }
            if let providerId = event.providerId {
                sqlite3_bind_text(statement, 10, providerId, -1, Self.transient)
            } else {
                sqlite3_bind_null(statement, 10)
            }
            sqlite3_bind_int(statement, 11, event.costIsEstimated ? 1 : 0)
            if let requestId = event.requestId {
                sqlite3_bind_text(statement, 12, requestId, -1, Self.transient)
            } else {
                sqlite3_bind_null(statement, 12)
            }
            sqlite3_bind_text(statement, 13, event.dataOrigin.rawValue, -1, Self.transient)
            sqlite3_bind_int(statement, 14, Int32(event.cacheReadTokens))
            sqlite3_bind_int(statement, 15, Int32(event.cacheWriteTokens))

            try step(statement)
        }
    }

    public func loadAllTokenEvents() throws -> [TokenEvent] {
        try loadTokenEvents(from: nil, to: nil)
    }

    /// Loads token events with optional half-open range `[from, to)`.
    /// Pass `nil` bounds to leave that side unbounded.
    public func loadTokenEvents(from: Date?, to: Date?) throws -> [TokenEvent] {
        try queue.sync {
            var clauses: [String] = []
            if from != nil { clauses.append("timestamp >= ?") }
            if to != nil { clauses.append("timestamp < ?") }
            let whereSQL = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
            let sql = """
                SELECT rowid, timestamp, source, model, input_tokens, output_tokens, cached_tokens,
                       cost_usd, latency_ms, provider, provider_id, cost_is_estimated,
                       request_id, data_origin, cache_read_tokens, cache_write_tokens
                FROM token_event
                \(whereSQL)
                ORDER BY timestamp ASC;
                """
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            try prepare(sql, into: &statement)

            var bindIndex: Int32 = 1
            if let from {
                sqlite3_bind_double(statement, bindIndex, from.timeIntervalSince1970)
                bindIndex += 1
            }
            if let to {
                sqlite3_bind_double(statement, bindIndex, to.timeIntervalSince1970)
                bindIndex += 1
            }

            var events: [TokenEvent] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let rowID = sqlite3_column_int64(statement, 0)
                guard let sourceRaw = sqlite3_column_text(statement, 2).map({ String(cString: $0) }),
                      let source = AgentSource(rawValue: sourceRaw),
                      let model = sqlite3_column_text(statement, 3).map({ String(cString: $0) })
                else {
                    continue
                }
                let hasLatency = sqlite3_column_type(statement, 8) != SQLITE_NULL
                let provider: String? = sqlite3_column_type(statement, 9) == SQLITE_NULL
                    ? nil
                    : sqlite3_column_text(statement, 9).map { String(cString: $0) }
                let providerId: String? = sqlite3_column_type(statement, 10) == SQLITE_NULL
                    ? nil
                    : sqlite3_column_text(statement, 10).map { String(cString: $0) }
                let costIsEstimated: Bool
                if sqlite3_column_type(statement, 11) == SQLITE_NULL {
                    costIsEstimated = true
                } else {
                    costIsEstimated = sqlite3_column_int(statement, 11) != 0
                }
                let requestId: String? = sqlite3_column_type(statement, 12) == SQLITE_NULL
                    ? nil
                    : sqlite3_column_text(statement, 12).map { String(cString: $0) }
                let dataOrigin: TokenDataOrigin
                if sqlite3_column_type(statement, 13) != SQLITE_NULL,
                   let raw = sqlite3_column_text(statement, 13).map({ String(cString: $0) }),
                   let parsed = TokenDataOrigin(rawValue: raw) {
                    dataOrigin = parsed
                } else {
                    dataOrigin = .agent
                }
                let legacyCached = Int(sqlite3_column_int(statement, 6))
                let cacheRead: Int
                if sqlite3_column_type(statement, 14) == SQLITE_NULL {
                    cacheRead = legacyCached
                } else {
                    cacheRead = Int(sqlite3_column_int(statement, 14))
                }
                let cacheWrite: Int
                if sqlite3_column_type(statement, 15) == SQLITE_NULL {
                    cacheWrite = 0
                } else {
                    cacheWrite = Int(sqlite3_column_int(statement, 15))
                }
                events.append(
                    TokenEvent(
                        rowID: rowID,
                        timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                        source: source,
                        model: model,
                        provider: provider,
                        providerId: providerId,
                        requestId: requestId,
                        inputTokens: Int(sqlite3_column_int(statement, 4)),
                        outputTokens: Int(sqlite3_column_int(statement, 5)),
                        cacheReadTokens: cacheRead,
                        cacheWriteTokens: cacheWrite,
                        costUSD: sqlite3_column_double(statement, 7),
                        costIsEstimated: costIsEstimated,
                        latencyMs: hasLatency ? sqlite3_column_double(statement, 8) : nil,
                        dataOrigin: dataOrigin
                    )
                )
            }
            return events
        }
    }

    
    /// Agent-origin events that still need provider attribution.
    public func loadTokenEventsNeedingProviderBackfill(
        limit: Int = 2_000,
        olderThan rowIDCursor: Int64? = nil
    ) throws -> [TokenEvent] {
        try queue.sync {
            var clauses = [
                "(provider IS NULL OR provider = '')",
                "(data_origin IS NULL OR data_origin = 'agent')"
            ]
            if rowIDCursor != nil {
                clauses.append("rowid > ?")
            }
            let whereSQL = "WHERE " + clauses.joined(separator: " AND ")
            let sql = """
                SELECT rowid, timestamp, source, model, input_tokens, output_tokens, cached_tokens,
                       cost_usd, latency_ms, provider, provider_id, cost_is_estimated,
                       request_id, data_origin, cache_read_tokens, cache_write_tokens
                FROM token_event
                \(whereSQL)
                ORDER BY rowid ASC
                LIMIT ?;
                """
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            try prepare(sql, into: &statement)
            var bind: Int32 = 1
            if let rowIDCursor {
                sqlite3_bind_int64(statement, bind, rowIDCursor)
                bind += 1
            }
            sqlite3_bind_int(statement, bind, Int32(max(1, limit)))
            return try Self.readTokenEventRows(statement)
        }
    }

    /// Updates provider attribution fields for an existing event row.
    public func updateTokenEventAttribution(_ event: TokenEvent) throws {
        guard let rowID = event.rowID else {
            throw UsageStoreError.executionFailed("token event missing rowID")
        }
        try queue.sync {
            let sql = """
                UPDATE token_event SET
                    provider = ?,
                    provider_id = ?,
                    request_id = ?,
                    cost_usd = ?,
                    cost_is_estimated = ?,
                    latency_ms = ?
                WHERE rowid = ?;
                """
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            try prepare(sql, into: &statement)
            if let provider = event.provider {
                sqlite3_bind_text(statement, 1, provider, -1, Self.transient)
            } else {
                sqlite3_bind_null(statement, 1)
            }
            if let providerId = event.providerId {
                sqlite3_bind_text(statement, 2, providerId, -1, Self.transient)
            } else {
                sqlite3_bind_null(statement, 2)
            }
            if let requestId = event.requestId {
                sqlite3_bind_text(statement, 3, requestId, -1, Self.transient)
            } else {
                sqlite3_bind_null(statement, 3)
            }
            sqlite3_bind_double(statement, 4, event.costUSD)
            sqlite3_bind_int(statement, 5, event.costIsEstimated ? 1 : 0)
            if let latencyMs = event.latencyMs {
                sqlite3_bind_double(statement, 6, latencyMs)
            } else {
                sqlite3_bind_null(statement, 6)
            }
            sqlite3_bind_int64(statement, 7, rowID)
            try step(statement)
        }
    }

    public func updateTokenEventAttributions(_ events: [TokenEvent]) throws {
        for event in events {
            try updateTokenEventAttribution(event)
        }
    }

    /// Updates model / provider / cost fields for repaired historical rows.
    public func updateTokenEventDetails(_ events: [TokenEvent]) throws {
        for event in events {
            try updateTokenEventDetail(event)
        }
    }

    public func updateTokenEventDetail(_ event: TokenEvent) throws {
        guard let rowID = event.rowID else {
            throw UsageStoreError.executionFailed("token event missing rowID")
        }
        try queue.sync {
            let sql = """
                UPDATE token_event SET
                    model = ?,
                    provider = ?,
                    provider_id = ?,
                    cost_usd = ?,
                    cost_is_estimated = ?
                WHERE rowid = ?;
                """
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            try prepare(sql, into: &statement)
            sqlite3_bind_text(statement, 1, event.model, -1, Self.transient)
            if let provider = event.provider {
                sqlite3_bind_text(statement, 2, provider, -1, Self.transient)
            } else {
                sqlite3_bind_null(statement, 2)
            }
            if let providerId = event.providerId {
                sqlite3_bind_text(statement, 3, providerId, -1, Self.transient)
            } else {
                sqlite3_bind_null(statement, 3)
            }
            sqlite3_bind_double(statement, 4, event.costUSD)
            sqlite3_bind_int(statement, 5, event.costIsEstimated ? 1 : 0)
            sqlite3_bind_int64(statement, 6, rowID)
            try step(statement)
        }
    }

    /// Deletes CC Switch proxy rows whose normalized request id was matched onto
    /// an agent-origin event during backfill (removes historical double counts).
    public func deleteProxyEvents(matchingNormalizedRequestIds requestIds: Set<String>) throws -> Int {
        guard !requestIds.isEmpty else { return 0 }
        return try queue.sync {
            // Load candidate proxy rows and filter in Swift so normalization matches TokenEvent rules.
            let sql = """
                SELECT rowid, request_id
                FROM token_event
                WHERE data_origin = 'ccSwitchProxy'
                  AND request_id IS NOT NULL;
                """
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            try prepare(sql, into: &statement)
            var rowIDs: [Int64] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let rowID = sqlite3_column_int64(statement, 0)
                guard let raw = sqlite3_column_text(statement, 1).map({ String(cString: $0) }) else {
                    continue
                }
                if requestIds.contains(TokenEvent.normalizeRequestId(raw)) {
                    rowIDs.append(rowID)
                }
            }
            guard !rowIDs.isEmpty else { return 0 }

            var deleted = 0
            for rowID in rowIDs {
                var del: OpaquePointer?
                defer { sqlite3_finalize(del) }
                try prepare("DELETE FROM token_event WHERE rowid = ?;", into: &del)
                sqlite3_bind_int64(del, 1, rowID)
                try step(del)
                deleted += 1
            }
            return deleted
        }
    }

    private static func readTokenEventRows(_ statement: OpaquePointer?) throws -> [TokenEvent] {
        var events: [TokenEvent] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let rowID = sqlite3_column_int64(statement, 0)
            guard let sourceRaw = sqlite3_column_text(statement, 2).map({ String(cString: $0) }),
                  let source = AgentSource(rawValue: sourceRaw),
                  let model = sqlite3_column_text(statement, 3).map({ String(cString: $0) })
            else {
                continue
            }
            let hasLatency = sqlite3_column_type(statement, 8) != SQLITE_NULL
            let provider: String? = sqlite3_column_type(statement, 9) == SQLITE_NULL
                ? nil
                : sqlite3_column_text(statement, 9).map { String(cString: $0) }
            let providerId: String? = sqlite3_column_type(statement, 10) == SQLITE_NULL
                ? nil
                : sqlite3_column_text(statement, 10).map { String(cString: $0) }
            let costIsEstimated: Bool
            if sqlite3_column_type(statement, 11) == SQLITE_NULL {
                costIsEstimated = true
            } else {
                costIsEstimated = sqlite3_column_int(statement, 11) != 0
            }
            let requestId: String? = sqlite3_column_type(statement, 12) == SQLITE_NULL
                ? nil
                : sqlite3_column_text(statement, 12).map { String(cString: $0) }
            let dataOrigin: TokenDataOrigin
            if sqlite3_column_type(statement, 13) != SQLITE_NULL,
               let raw = sqlite3_column_text(statement, 13).map({ String(cString: $0) }),
               let parsed = TokenDataOrigin(rawValue: raw) {
                dataOrigin = parsed
            } else {
                dataOrigin = .agent
            }
            let legacyCached = Int(sqlite3_column_int(statement, 6))
            let cacheRead: Int
            if sqlite3_column_type(statement, 14) == SQLITE_NULL {
                cacheRead = legacyCached
            } else {
                cacheRead = Int(sqlite3_column_int(statement, 14))
            }
            let cacheWrite: Int
            if sqlite3_column_type(statement, 15) == SQLITE_NULL {
                cacheWrite = 0
            } else {
                cacheWrite = Int(sqlite3_column_int(statement, 15))
            }
            events.append(
                TokenEvent(
                    rowID: rowID,
                    timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                    source: source,
                    model: model,
                    provider: provider,
                    providerId: providerId,
                    requestId: requestId,
                    inputTokens: Int(sqlite3_column_int(statement, 4)),
                    outputTokens: Int(sqlite3_column_int(statement, 5)),
                    cacheReadTokens: cacheRead,
                    cacheWriteTokens: cacheWrite,
                    costUSD: sqlite3_column_double(statement, 7),
                    costIsEstimated: costIsEstimated,
                    latencyMs: hasLatency ? sqlite3_column_double(statement, 8) : nil,
                    dataOrigin: dataOrigin
                )
            )
        }
        return events
    }



    // MARK: - Low-level helpers

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func exec(_ sql: String) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw UsageStoreError.executionFailed(lastErrorMessage())
        }
    }

    private func prepare(_ sql: String, into statement: inout OpaquePointer?) throws {
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw UsageStoreError.executionFailed(lastErrorMessage())
        }
    }

    private func step(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw UsageStoreError.executionFailed(lastErrorMessage())
        }
    }

    private func lastErrorMessage() -> String {
        String(cString: sqlite3_errmsg(db))
    }

    private func tableColumns(_ table: String) throws -> Set<String> {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        try prepare("PRAGMA table_info(\(table));", into: &statement)
        var columns: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 1) {
                columns.insert(String(cString: name))
            }
        }
        return columns
    }

    private func addColumnIfNeeded(table: String, column: String, ddl: String) throws {
        let columns = try tableColumns(table)
        guard !columns.contains(column) else { return }
        try exec("ALTER TABLE \(table) ADD COLUMN \(column) \(ddl);")
    }



}
