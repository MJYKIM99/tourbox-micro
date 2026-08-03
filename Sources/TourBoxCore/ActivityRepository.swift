import Foundation
import SQLite3

public enum ActivityRepositoryError: LocalizedError {
    case open(String)
    case sqlite(String)

    public var errorDescription: String? {
        switch self {
        case .open(let message): "Unable to open the task-status database: \(message)"
        case .sqlite(let message): "Task-status database error: \(message)"
        }
    }
}

/// A small WAL-backed store for the latest known lifecycle state of a task.
///
/// It intentionally stores no prompt or response text. A row contains only the
/// task identity, working directory, state, short diagnostic detail, and time.
public final class ActivityRepository: @unchecked Sendable {
    public let databaseURL: URL

    private var database: OpaquePointer?
    private var writesSincePrune = 0
    private let lock = NSLock()

    public init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(databaseURL.path, &handle, flags, nil)
        guard result == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let handle { sqlite3_close(handle) }
            throw ActivityRepositoryError.open(message)
        }
        database = handle

        do {
            try execute("PRAGMA journal_mode=WAL;")
            try execute("PRAGMA synchronous=NORMAL;")
            try execute("PRAGMA busy_timeout=1000;")
            try execute("""
                CREATE TABLE IF NOT EXISTS task_status (
                    identity_key TEXT PRIMARY KEY,
                    thread_id TEXT,
                    cwd TEXT,
                    state TEXT NOT NULL,
                    detail TEXT,
                    updated_at_ms INTEGER NOT NULL,
                    acknowledged_at_ms INTEGER
                );
                """)
            try execute("""
                CREATE INDEX IF NOT EXISTS task_status_updated_idx
                ON task_status(updated_at_ms DESC);
                """)
            try execute("""
                CREATE INDEX IF NOT EXISTS task_status_thread_idx
                ON task_status(thread_id);
                """)
        } catch {
            sqlite3_close(handle)
            database = nil
            throw error
        }
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    public func loadActivities(limit: Int = 500) throws -> [AgentActivity] {
        try locked {
            let safeLimit = min(max(limit, 1), 2_000)
            let statement = try prepare("""
                SELECT thread_id, cwd, state, detail, updated_at_ms
                FROM task_status
                ORDER BY updated_at_ms DESC
                LIMIT ?;
                """)
            defer { sqlite3_finalize(statement) }
            try check(sqlite3_bind_int(statement, 1, Int32(safeLimit)))

            var activities: [AgentActivity] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let stateText = text(statement, column: 2),
                      let state = AgentState(rawValue: stateText) else { continue }
                activities.append(
                    AgentActivity(
                        threadID: text(statement, column: 0),
                        cwd: text(statement, column: 1),
                        state: state,
                        updatedAt: Date(
                            timeIntervalSince1970: Double(sqlite3_column_int64(statement, 4)) / 1_000
                        ),
                        detail: text(statement, column: 3)
                    )
                )
            }
            return activities
        }
    }

    @discardableResult
    public func upsert(_ activity: AgentActivity) throws -> Bool {
        guard let identityKey = Self.identityKey(for: activity) else { return false }
        return try locked {
            if let threadID = activity.threadID, let cwd = activity.cwd {
                let staleKey = "cwd:\(cwd)"
                if staleKey != identityKey {
                    let delete = try prepare("DELETE FROM task_status WHERE identity_key = ?;")
                    defer { sqlite3_finalize(delete) }
                    try bind(staleKey, to: delete, index: 1)
                    guard sqlite3_step(delete) == SQLITE_DONE else { throw sqliteError() }
                }
                _ = threadID
            }

            let statement = try prepare("""
                INSERT INTO task_status (
                    identity_key, thread_id, cwd, state, detail, updated_at_ms, acknowledged_at_ms
                ) VALUES (?, ?, ?, ?, ?, ?, NULL)
                ON CONFLICT(identity_key) DO UPDATE SET
                    thread_id = excluded.thread_id,
                    cwd = excluded.cwd,
                    state = excluded.state,
                    detail = excluded.detail,
                    updated_at_ms = excluded.updated_at_ms,
                    acknowledged_at_ms = CASE
                        WHEN excluded.state = 'complete' THEN NULL
                        ELSE task_status.acknowledged_at_ms
                    END
                WHERE excluded.updated_at_ms >= task_status.updated_at_ms;
                """)
            defer { sqlite3_finalize(statement) }

            try bind(identityKey, to: statement, index: 1)
            try bind(activity.threadID, to: statement, index: 2)
            try bind(activity.cwd, to: statement, index: 3)
            try bind(activity.state.rawValue, to: statement, index: 4)
            try bind(activity.detail, to: statement, index: 5)
            let timestamp = Int64((activity.updatedAt.timeIntervalSince1970 * 1_000).rounded())
            try check(sqlite3_bind_int64(statement, 6, timestamp))
            guard sqlite3_step(statement) == SQLITE_DONE else { throw sqliteError() }
            let changed = sqlite3_changes(database) > 0

            writesSincePrune += 1
            if writesSincePrune >= 50 {
                try pruneKeepingLatest(1_000)
                writesSincePrune = 0
            }
            return changed
        }
    }

    public func acknowledgeCompletion(for thread: CodexThread, at date: Date = Date()) throws {
        try locked {
            let statement = try prepare("""
                UPDATE task_status
                SET state = 'idle', acknowledged_at_ms = ?, updated_at_ms = ?
                WHERE state = 'complete'
                  AND (thread_id = ? OR (thread_id IS NULL AND cwd = ?));
                """)
            defer { sqlite3_finalize(statement) }
            let timestamp = Int64((date.timeIntervalSince1970 * 1_000).rounded())
            try check(sqlite3_bind_int64(statement, 1, timestamp))
            try check(sqlite3_bind_int64(statement, 2, timestamp))
            try bind(thread.id, to: statement, index: 3)
            try bind(thread.cwd, to: statement, index: 4)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw sqliteError() }
        }
    }

    @discardableResult
    public func expireThinking(before cutoff: Date, at date: Date = Date()) throws -> Int {
        try locked {
            let statement = try prepare("""
                UPDATE task_status
                SET state = 'idle', detail = NULL, updated_at_ms = ?
                WHERE state = 'thinking' AND updated_at_ms < ?;
                """)
            defer { sqlite3_finalize(statement) }
            let timestamp = Int64((date.timeIntervalSince1970 * 1_000).rounded())
            let cutoffTimestamp = Int64((cutoff.timeIntervalSince1970 * 1_000).rounded())
            try check(sqlite3_bind_int64(statement, 1, timestamp))
            try check(sqlite3_bind_int64(statement, 2, cutoffTimestamp))
            guard sqlite3_step(statement) == SQLITE_DONE else { throw sqliteError() }
            return Int(sqlite3_changes(database))
        }
    }

    private static func identityKey(for activity: AgentActivity) -> String? {
        if let threadID = activity.threadID, !threadID.isEmpty { return "thread:\(threadID)" }
        if let cwd = activity.cwd, !cwd.isEmpty { return "cwd:\(cwd)" }
        return nil
    }

    private func pruneKeepingLatest(_ count: Int) throws {
        let statement = try prepare("""
            DELETE FROM task_status
            WHERE identity_key IN (
                SELECT identity_key FROM task_status
                ORDER BY updated_at_ms DESC
                LIMIT -1 OFFSET ?
            );
            """)
        defer { sqlite3_finalize(statement) }
        try check(sqlite3_bind_int(statement, 1, Int32(count)))
        guard sqlite3_step(statement) == SQLITE_DONE else { throw sqliteError() }
    }

    private func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errorMessage)
            throw ActivityRepositoryError.sqlite(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw sqliteError() }
        return statement
    }

    private func bind(_ value: String?, to statement: OpaquePointer, index: Int32) throws {
        guard let value else {
            try check(sqlite3_bind_null(statement, index))
            return
        }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let result = value.withCString { pointer in
            sqlite3_bind_text(statement, index, pointer, -1, transient)
        }
        try check(result)
    }

    private func text(_ statement: OpaquePointer, column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let pointer = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: pointer)
    }

    private func check(_ result: Int32) throws {
        guard result == SQLITE_OK else { throw sqliteError() }
    }

    private func sqliteError() -> ActivityRepositoryError {
        let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "database closed"
        return .sqlite(message)
    }

    private func locked<T>(_ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
