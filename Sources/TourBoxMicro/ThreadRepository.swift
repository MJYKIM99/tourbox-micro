import Foundation
import TourBoxCore

struct ThreadRepository: Sendable {
    let databaseURL: URL

    init(databaseURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/state_5.sqlite")) {
        self.databaseURL = databaseURL
    }

    func loadRecentThreads(limit: Int = 80) throws -> [CodexThread] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return [] }

        let safeLimit = min(max(limit, 6), 500)
        let query = """
        SELECT id, title, cwd, preview, recency_at_ms, is_pinned, rollout_path
        FROM threads
        WHERE archived = 0
          AND preview <> ''
          AND source NOT LIKE '{%'
        ORDER BY recency_at_ms DESC
        LIMIT \(safeLimit);
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-json", databaseURL.path, query]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? "sqlite3 failed"
            throw NSError(domain: "TourBoxMicro.ThreadRepository", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: message.trimmingCharacters(in: .whitespacesAndNewlines)
            ])
        }

        return try JSONDecoder().decode([Row].self, from: data).map { row in
            CodexThread(
                id: row.id,
                title: ThreadDisplayText.title(rawTitle: row.title, preview: row.preview),
                cwd: row.cwd,
                preview: row.preview,
                recencyAtMilliseconds: row.recencyAtMilliseconds,
                isPinned: row.isPinned != 0,
                rolloutPath: row.rolloutPath
            )
        }
    }

    private struct Row: Decodable {
        let id: String
        let title: String
        let cwd: String
        let preview: String
        let recencyAtMilliseconds: Int64
        let isPinned: Int
        let rolloutPath: String

        enum CodingKeys: String, CodingKey {
            case id, title, cwd, preview
            case recencyAtMilliseconds = "recency_at_ms"
            case isPinned = "is_pinned"
            case rolloutPath = "rollout_path"
        }
    }
}
