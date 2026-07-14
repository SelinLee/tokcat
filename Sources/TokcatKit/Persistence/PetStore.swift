import Foundation
import SQLite3

/// Errors surfaced by `PetStore`.
public enum PetStoreError: Error {
    case openFailed(String)
    case executionFailed(String)
}

/// Local-only SQLite persistence for `PetState` and adapter read-offsets.
/// No network I/O ever happens here — this is the whole point of the
/// "local-first" design.
public final class PetStore {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.tokcat.petstore")

    public init(fileURL: URL) throws {
        var handle: OpaquePointer?
        let result = sqlite3_open(fileURL.path, &handle)
        guard result == SQLITE_OK, let handle else {
            let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            throw PetStoreError.openFailed(message)
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
            CREATE TABLE IF NOT EXISTS pet_state (
                id INTEGER PRIMARY KEY CHECK (id = 0),
                level INTEGER NOT NULL,
                xp REAL NOT NULL,
                intelligence REAL NOT NULL,
                vitality REAL NOT NULL,
                energy REAL NOT NULL,
                hunger REAL NOT NULL,
                mood REAL NOT NULL
            );
            """)
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
        // Pet growth / streak fields (added after MVP).
        try addColumnIfNeeded(table: "pet_state", column: "last_fed_at", ddl: "REAL")
        try addColumnIfNeeded(table: "pet_state", column: "active_day_keys", ddl: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfNeeded(table: "pet_state", column: "streak_days", ddl: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfNeeded(table: "pet_state", column: "total_tokens_fed", ddl: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfNeeded(table: "pet_state", column: "daily_xp_earned", ddl: "REAL NOT NULL DEFAULT 0")
        try addColumnIfNeeded(table: "pet_state", column: "daily_xp_day_key", ddl: "TEXT")
        try addColumnIfNeeded(table: "pet_state", column: "unlocked_achievements", ddl: "TEXT NOT NULL DEFAULT ''")
        try exec("""
            CREATE TABLE IF NOT EXISTS pet_meta (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            """)
        try exec("""
            CREATE TABLE IF NOT EXISTS pet_timeline_event (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                timestamp REAL NOT NULL,
                title TEXT NOT NULL,
                detail TEXT NOT NULL,
                payload_json TEXT NOT NULL DEFAULT '{}'
            );
            """)
        try exec("""
            CREATE INDEX IF NOT EXISTS idx_pet_timeline_ts
            ON pet_timeline_event(timestamp DESC);
            """)
        try exec("""
            CREATE INDEX IF NOT EXISTS idx_token_event_ts
            ON token_event(timestamp);
            """)
        try exec("""
            CREATE TABLE IF NOT EXISTS inventory (
                item_id TEXT PRIMARY KEY,
                quantity INTEGER NOT NULL,
                obtained_at REAL NOT NULL,
                source TEXT NOT NULL
            );
            """)
        try exec("""
            CREATE TABLE IF NOT EXISTS equipment (
                slot TEXT PRIMARY KEY,
                item_id TEXT NOT NULL
            );
            """)
        try exec("""
            CREATE TABLE IF NOT EXISTS loot_rolls (
                id TEXT PRIMARY KEY,
                timestamp REAL NOT NULL,
                trigger_kind TEXT NOT NULL,
                item_id TEXT,
                rarity TEXT,
                source TEXT,
                was_pity INTEGER NOT NULL DEFAULT 0,
                hit INTEGER NOT NULL DEFAULT 0,
                day_key TEXT,
                miss_streak INTEGER,
                drops_today INTEGER
            );
            """)
        try exec("""
            CREATE INDEX IF NOT EXISTS idx_loot_rolls_ts
            ON loot_rolls(timestamp DESC);
            """)
    }


    // MARK: - PetState

    public func savePetState(_ state: PetState) throws {
        try queue.sync {
            let sql = """
                INSERT INTO pet_state (
                    id, level, xp, intelligence, vitality, energy, hunger, mood,
                    last_fed_at, active_day_keys, streak_days, total_tokens_fed,
                    daily_xp_earned, daily_xp_day_key, unlocked_achievements
                )
                VALUES (0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    level = excluded.level,
                    xp = excluded.xp,
                    intelligence = excluded.intelligence,
                    vitality = excluded.vitality,
                    energy = excluded.energy,
                    hunger = excluded.hunger,
                    mood = excluded.mood,
                    last_fed_at = excluded.last_fed_at,
                    active_day_keys = excluded.active_day_keys,
                    streak_days = excluded.streak_days,
                    total_tokens_fed = excluded.total_tokens_fed,
                    daily_xp_earned = excluded.daily_xp_earned,
                    daily_xp_day_key = excluded.daily_xp_day_key,
                    unlocked_achievements = excluded.unlocked_achievements;
                """
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            try prepare(sql, into: &statement)

            sqlite3_bind_int(statement, 1, Int32(state.level))
            sqlite3_bind_double(statement, 2, state.xp)
            sqlite3_bind_double(statement, 3, state.stats.intelligence)
            sqlite3_bind_double(statement, 4, state.stats.vitality)
            sqlite3_bind_double(statement, 5, state.stats.energy)
            sqlite3_bind_double(statement, 6, state.hunger)
            sqlite3_bind_double(statement, 7, state.mood)
            if let lastFedAt = state.lastFedAt {
                sqlite3_bind_double(statement, 8, lastFedAt.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(statement, 8)
            }
            sqlite3_bind_text(statement, 9, encodeCSV(state.activeDayKeys), -1, Self.transient)
            sqlite3_bind_int(statement, 10, Int32(state.streakDays))
            sqlite3_bind_int64(statement, 11, Int64(state.totalTokensFed))
            sqlite3_bind_double(statement, 12, state.dailyXPEarned)
            if let dayKey = state.dailyXPDayKey {
                sqlite3_bind_text(statement, 13, dayKey, -1, Self.transient)
            } else {
                sqlite3_bind_null(statement, 13)
            }
            sqlite3_bind_text(statement, 14, encodeCSV(state.unlockedAchievements), -1, Self.transient)

            try step(statement)
        }
    }

    public func loadPetState() throws -> PetState? {
        try queue.sync {
            let sql = """
                SELECT level, xp, intelligence, vitality, energy, hunger, mood,
                       last_fed_at, active_day_keys, streak_days, total_tokens_fed,
                       daily_xp_earned, daily_xp_day_key, unlocked_achievements
                FROM pet_state WHERE id = 0;
                """
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            try prepare(sql, into: &statement)

            let stepResult = sqlite3_step(statement)
            guard stepResult == SQLITE_ROW else {
                if stepResult == SQLITE_DONE { return nil }
                throw PetStoreError.executionFailed(lastErrorMessage())
            }

            let lastFed: Date?
            if sqlite3_column_type(statement, 7) == SQLITE_NULL {
                lastFed = nil
            } else {
                lastFed = Date(timeIntervalSince1970: sqlite3_column_double(statement, 7))
            }
            let activeKeys = decodeCSV(sqlite3_column_text(statement, 8).map { String(cString: $0) })
            let streak = Int(sqlite3_column_int(statement, 9))
            let totalTokens = Int(sqlite3_column_int64(statement, 10))
            let dailyXP = sqlite3_column_double(statement, 11)
            let dayKey = sqlite3_column_text(statement, 12).map { String(cString: $0) }
            let achievements = decodeCSV(sqlite3_column_text(statement, 13).map { String(cString: $0) })

            return PetState(
                level: Int(sqlite3_column_int(statement, 0)),
                xp: sqlite3_column_double(statement, 1),
                stats: PetStats(
                    intelligence: sqlite3_column_double(statement, 2),
                    vitality: sqlite3_column_double(statement, 3),
                    energy: sqlite3_column_double(statement, 4)
                ),
                hunger: sqlite3_column_double(statement, 5),
                mood: sqlite3_column_double(statement, 6),
                lastFedAt: lastFed,
                activeDayKeys: activeKeys,
                streakDays: streak,
                totalTokensFed: totalTokens,
                dailyXPEarned: dailyXP,
                dailyXPDayKey: dayKey,
                unlockedAchievements: achievements
            )
        }
    }

    public func savePetMeta(key: String, value: String) throws {
        try queue.sync {
            let sql = """
                INSERT INTO pet_meta (key, value) VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value;
                """
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            try prepare(sql, into: &statement)
            sqlite3_bind_text(statement, 1, key, -1, Self.transient)
            sqlite3_bind_text(statement, 2, value, -1, Self.transient)
            try step(statement)
        }
    }

    public func loadPetMeta(key: String) throws -> String? {
        try queue.sync {
            let sql = "SELECT value FROM pet_meta WHERE key = ? LIMIT 1;"
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            try prepare(sql, into: &statement)
            sqlite3_bind_text(statement, 1, key, -1, Self.transient)
            let stepResult = sqlite3_step(statement)
            guard stepResult == SQLITE_ROW else {
                if stepResult == SQLITE_DONE { return nil }
                throw PetStoreError.executionFailed(lastErrorMessage())
            }
            return sqlite3_column_text(statement, 0).map { String(cString: $0) }
        }
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
            throw PetStoreError.executionFailed("token event missing rowID")
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
            throw PetStoreError.executionFailed("token event missing rowID")
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



    // MARK: - Inventory / equipment / loot

    public func saveInventory(_ items: [InventoryItem]) throws {
        try queue.sync {
            try exec("DELETE FROM inventory;")
            let sql = """
                INSERT INTO inventory (item_id, quantity, obtained_at, source)
                VALUES (?, ?, ?, ?);
                """
            for item in items {
                var statement: OpaquePointer?
                defer { sqlite3_finalize(statement) }
                try prepare(sql, into: &statement)
                sqlite3_bind_text(statement, 1, item.itemID, -1, Self.transient)
                sqlite3_bind_int(statement, 2, Int32(item.quantity))
                sqlite3_bind_double(statement, 3, item.obtainedAt.timeIntervalSince1970)
                sqlite3_bind_text(statement, 4, item.source.rawValue, -1, Self.transient)
                try step(statement)
            }
        }
    }

    public func loadInventory() throws -> [InventoryItem] {
        try queue.sync {
            let sql = """
                SELECT item_id, quantity, obtained_at, source
                FROM inventory
                ORDER BY obtained_at DESC;
                """
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            try prepare(sql, into: &statement)
            var items: [InventoryItem] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let itemID = sqlite3_column_text(statement, 0).map({ String(cString: $0) }),
                      let sourceRaw = sqlite3_column_text(statement, 3).map({ String(cString: $0) }),
                      let source = LootSource(rawValue: sourceRaw)
                else { continue }
                items.append(
                    InventoryItem(
                        itemID: itemID,
                        quantity: Int(sqlite3_column_int(statement, 1)),
                        obtainedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                        source: source
                    )
                )
            }
            return items
        }
    }

    public func saveEquipment(_ loadout: EquipmentLoadout) throws {
        try queue.sync {
            try exec("DELETE FROM equipment;")
            let sql = "INSERT INTO equipment (slot, item_id) VALUES (?, ?);"
            for (slot, itemID) in loadout.slots {
                var statement: OpaquePointer?
                defer { sqlite3_finalize(statement) }
                try prepare(sql, into: &statement)
                sqlite3_bind_text(statement, 1, slot, -1, Self.transient)
                sqlite3_bind_text(statement, 2, itemID, -1, Self.transient)
                try step(statement)
            }
        }
    }

    public func loadEquipment() throws -> EquipmentLoadout {
        try queue.sync {
            let sql = "SELECT slot, item_id FROM equipment;"
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            try prepare(sql, into: &statement)
            var slots: [String: String] = [:]
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let slot = sqlite3_column_text(statement, 0).map({ String(cString: $0) }),
                      let itemID = sqlite3_column_text(statement, 1).map({ String(cString: $0) })
                else { continue }
                slots[slot] = itemID
            }
            return EquipmentLoadout(slots: slots)
        }
    }

    public func saveLootProgress(_ progress: LootProgressState) throws {
        try savePetMeta(key: "loot_progress_json", value: Self.encodeLootProgress(progress))
    }

    public func loadLootProgress() throws -> LootProgressState {
        guard let raw = try loadPetMeta(key: "loot_progress_json") else {
            return LootProgressState()
        }
        return Self.decodeLootProgress(raw)
    }

    public func appendLootRoll(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        triggerKind: String,
        drop: LootDrop?,
        hit: Bool,
        progress: LootProgressState
    ) throws {
        try queue.sync {
            let sql = """
                INSERT INTO loot_rolls
                    (id, timestamp, trigger_kind, item_id, rarity, source, was_pity, hit, day_key, miss_streak, drops_today)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            try prepare(sql, into: &statement)
            sqlite3_bind_text(statement, 1, id, -1, Self.transient)
            sqlite3_bind_double(statement, 2, timestamp.timeIntervalSince1970)
            sqlite3_bind_text(statement, 3, triggerKind, -1, Self.transient)
            if let drop {
                sqlite3_bind_text(statement, 4, drop.item.id, -1, Self.transient)
                sqlite3_bind_text(statement, 5, drop.item.rarity.rawValue, -1, Self.transient)
                sqlite3_bind_text(statement, 6, drop.source.rawValue, -1, Self.transient)
                sqlite3_bind_int(statement, 7, drop.wasPity ? 1 : 0)
            } else {
                sqlite3_bind_null(statement, 4)
                sqlite3_bind_null(statement, 5)
                sqlite3_bind_null(statement, 6)
                sqlite3_bind_int(statement, 7, 0)
            }
            sqlite3_bind_int(statement, 8, hit ? 1 : 0)
            if let dayKey = progress.dayKey {
                sqlite3_bind_text(statement, 9, dayKey, -1, Self.transient)
            } else {
                sqlite3_bind_null(statement, 9)
            }
            sqlite3_bind_int(statement, 10, Int32(progress.missStreak))
            sqlite3_bind_int(statement, 11, Int32(progress.dropsToday))
            try step(statement)
        }
    }

    public func clearInventoryAndLoot() throws {
        try queue.sync {
            try exec("DELETE FROM inventory;")
            try exec("DELETE FROM equipment;")
            try exec("DELETE FROM loot_rolls;")
        }
        try savePetMeta(key: "loot_progress_json", value: Self.encodeLootProgress(LootProgressState()))
    }

    // MARK: - Pet timeline events

    public func appendPetTimelineEvent(_ event: PetTimelineEvent) throws {
        try queue.sync {
            let sql = """
                INSERT OR REPLACE INTO pet_timeline_event
                    (id, kind, timestamp, title, detail, payload_json)
                VALUES (?, ?, ?, ?, ?, ?);
                """
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            try prepare(sql, into: &statement)
            sqlite3_bind_text(statement, 1, event.id, -1, Self.transient)
            sqlite3_bind_text(statement, 2, event.kind.rawValue, -1, Self.transient)
            sqlite3_bind_double(statement, 3, event.timestamp.timeIntervalSince1970)
            sqlite3_bind_text(statement, 4, event.title, -1, Self.transient)
            sqlite3_bind_text(statement, 5, event.detail, -1, Self.transient)
            let payloadJSON = Self.encodePayload(event.payload)
            sqlite3_bind_text(statement, 6, payloadJSON, -1, Self.transient)
            try step(statement)
        }
    }

    public func appendPetTimelineEvents(_ events: [PetTimelineEvent]) throws {
        for event in events {
            try appendPetTimelineEvent(event)
        }
    }

    /// Newest-first timeline for the pet archive UI.
    public func loadRecentPetTimelineEvents(limit: Int = 40) throws -> [PetTimelineEvent] {
        try queue.sync {
            let sql = """
                SELECT id, kind, timestamp, title, detail, payload_json
                FROM pet_timeline_event
                ORDER BY timestamp DESC
                LIMIT ?;
                """
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            try prepare(sql, into: &statement)
            sqlite3_bind_int(statement, 1, Int32(max(1, limit)))
            var items: [PetTimelineEvent] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let id = sqlite3_column_text(statement, 0).map({ String(cString: $0) }),
                      let kindRaw = sqlite3_column_text(statement, 1).map({ String(cString: $0) }),
                      let kind = PetEventKind(rawValue: kindRaw),
                      let title = sqlite3_column_text(statement, 3).map({ String(cString: $0) })
                else { continue }
                let detail = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
                let payloadRaw = sqlite3_column_text(statement, 5).map { String(cString: $0) }
                items.append(
                    PetTimelineEvent(
                        id: id,
                        kind: kind,
                        timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                        title: title,
                        detail: detail,
                        payload: Self.decodePayload(payloadRaw)
                    )
                )
            }
            return items
        }
    }

    public func clearPetTimelineEvents() throws {
        try queue.sync {
            try exec("DELETE FROM pet_timeline_event;")
        }
    }

    // MARK: - Low-level helpers

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func exec(_ sql: String) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw PetStoreError.executionFailed(lastErrorMessage())
        }
    }

    private func prepare(_ sql: String, into statement: inout OpaquePointer?) throws {
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw PetStoreError.executionFailed(lastErrorMessage())
        }
    }

    private func step(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw PetStoreError.executionFailed(lastErrorMessage())
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



    private static func encodeLootProgress(_ progress: LootProgressState) -> String {
        guard let data = try? JSONEncoder().encode(progress),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private static func decodeLootProgress(_ raw: String) -> LootProgressState {
        guard let data = raw.data(using: .utf8),
              let progress = try? JSONDecoder().decode(LootProgressState.self, from: data) else {
            return LootProgressState()
        }
        return progress
    }

    private static func encodePayload(_ payload: [String: String]) -> String {
        guard !payload.isEmpty,
              let data = try? JSONEncoder().encode(payload),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private static func decodePayload(_ raw: String?) -> [String: String] {
        guard let raw, let data = raw.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    private func encodeCSV(_ values: [String]) -> String {
        values
            .map { $0.replacingOccurrences(of: ",", with: "_") }
            .filter { !$0.isEmpty }
            .joined(separator: ",")
    }

    private func decodeCSV(_ raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        return raw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }
}
