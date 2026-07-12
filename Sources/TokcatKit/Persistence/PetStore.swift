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
    }

    // MARK: - PetState

    public func savePetState(_ state: PetState) throws {
        try queue.sync {
            let sql = """
                INSERT INTO pet_state (id, level, xp, intelligence, vitality, energy, hunger, mood)
                VALUES (0, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    level = excluded.level,
                    xp = excluded.xp,
                    intelligence = excluded.intelligence,
                    vitality = excluded.vitality,
                    energy = excluded.energy,
                    hunger = excluded.hunger,
                    mood = excluded.mood;
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

            try step(statement)
        }
    }

    public func loadPetState() throws -> PetState? {
        try queue.sync {
            let sql = """
                SELECT level, xp, intelligence, vitality, energy, hunger, mood
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

            return PetState(
                level: Int(sqlite3_column_int(statement, 0)),
                xp: sqlite3_column_double(statement, 1),
                stats: PetStats(
                    intelligence: sqlite3_column_double(statement, 2),
                    vitality: sqlite3_column_double(statement, 3),
                    energy: sqlite3_column_double(statement, 4)
                ),
                hunger: sqlite3_column_double(statement, 5),
                mood: sqlite3_column_double(statement, 6)
            )
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
                    (timestamp, source, model, input_tokens, output_tokens, cached_tokens, cost_usd, latency_ms)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?);
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

            try step(statement)
        }
    }

    public func loadAllTokenEvents() throws -> [TokenEvent] {
        try queue.sync {
            let sql = """
                SELECT timestamp, source, model, input_tokens, output_tokens, cached_tokens, cost_usd, latency_ms
                FROM token_event ORDER BY timestamp ASC;
                """
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            try prepare(sql, into: &statement)

            var events: [TokenEvent] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let sourceRaw = sqlite3_column_text(statement, 1).map({ String(cString: $0) }),
                      let source = AgentSource(rawValue: sourceRaw),
                      let model = sqlite3_column_text(statement, 2).map({ String(cString: $0) })
                else {
                    continue
                }
                let hasLatency = sqlite3_column_type(statement, 7) != SQLITE_NULL
                events.append(
                    TokenEvent(
                        timestamp: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)),
                        source: source,
                        model: model,
                        inputTokens: Int(sqlite3_column_int(statement, 3)),
                        outputTokens: Int(sqlite3_column_int(statement, 4)),
                        cachedTokens: Int(sqlite3_column_int(statement, 5)),
                        costUSD: sqlite3_column_double(statement, 6),
                        latencyMs: hasLatency ? sqlite3_column_double(statement, 7) : nil
                    )
                )
            }
            return events
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
}
