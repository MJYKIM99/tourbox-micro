import Foundation
import SQLite3

public struct ThreadRepository: Sendable {
    public let databaseURL: URL

    public init(databaseURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/state_5.sqlite")) {
        self.databaseURL = databaseURL
    }

    public func loadRecentThreads(limit: Int = 80) throws -> [CodexThread] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return [] }

        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            defer { if let database { sqlite3_close(database) } }
            throw RepositoryError.sqlite(message: database.map(sqliteMessage) ?? "无法打开 Codex 状态数据库")
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 500)

        let query = """
        SELECT id, title, cwd, preview, recency_at_ms, is_pinned, rollout_path
        FROM threads
        WHERE archived = 0
          AND preview <> ''
          AND source NOT LIKE '{%'
        ORDER BY recency_at_ms DESC
        LIMIT ?;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw RepositoryError.sqlite(message: sqliteMessage(database))
        }
        defer { sqlite3_finalize(statement) }

        let safeLimit = min(max(limit, 6), 500)
        guard sqlite3_bind_int(statement, 1, Int32(safeLimit)) == SQLITE_OK else {
            throw RepositoryError.sqlite(message: sqliteMessage(database))
        }

        var threads: [CodexThread] = []
        threads.reserveCapacity(safeLimit)
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                let title = text(statement, column: 1)
                let preview = text(statement, column: 3)
                threads.append(
                    CodexThread(
                        id: text(statement, column: 0),
                        title: ThreadDisplayText.title(rawTitle: title, preview: preview),
                        cwd: text(statement, column: 2),
                        preview: preview,
                        recencyAtMilliseconds: sqlite3_column_int64(statement, 4),
                        isPinned: sqlite3_column_int(statement, 5) != 0,
                        rolloutPath: optionalText(statement, column: 6)
                    )
                )
            case SQLITE_DONE:
                return threads
            default:
                throw RepositoryError.sqlite(message: sqliteMessage(database))
            }
        }
    }

    private func text(_ statement: OpaquePointer, column: Int32) -> String {
        guard let value = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: value)
    }

    private func optionalText(_ statement: OpaquePointer, column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: value)
    }

    private func sqliteMessage(_ database: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(database))
    }

    private enum RepositoryError: LocalizedError {
        case sqlite(message: String)

        var errorDescription: String? {
            switch self {
            case .sqlite(let message): message
            }
        }
    }
}
