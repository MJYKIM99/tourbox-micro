import Foundation
import SQLite3
import Testing
@testable import TourBoxCore

@Test func threadRepositoryReturnsEmptyForMissingDatabase() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tourbox-thread-missing-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }

    let threads = try ThreadRepository(
        databaseURL: directory.appendingPathComponent("missing.sqlite3")
    ).loadRecentThreads()

    #expect(threads.isEmpty)
}

@Test func threadRepositoryLoadsOnlyVisibleThreadsInRecencyOrder() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tourbox-thread-query-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let databaseURL = directory.appendingPathComponent("state.sqlite3")

    try createThreadDatabase(at: databaseURL, statements: """
        INSERT INTO threads VALUES
          ('older', 'Older', '/older', 'older preview', 100, 1, '/older.jsonl', 0, 'cli'),
          ('newer', 'Newer', '/newer', 'newer preview', 300, 0, NULL, 0, 'cli'),
          ('archived', 'Archived', '/archived', 'archived preview', 500, 0, NULL, 1, 'cli'),
          ('blank', 'Blank', '/blank', '', 600, 0, NULL, 0, 'cli'),
          ('metadata', 'Metadata', '/metadata', 'metadata preview', 700, 0, NULL, 0, '{"kind":"system"}');
        """)

    let threads = try ThreadRepository(databaseURL: databaseURL).loadRecentThreads()

    #expect(threads.map(\.id) == ["newer", "older"])
    #expect(threads.first?.rolloutPath == nil)
    #expect(threads.last?.isPinned == true)
}

@Test func threadRepositoryUsesBoundedLimitAndReportsSchemaErrors() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tourbox-thread-limit-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let databaseURL = directory.appendingPathComponent("state.sqlite3")

    let rows = (1...8).map { index in
        "('thread-\(index)', 'Thread \(index)', '/project', 'preview', \(index), 0, NULL, 0, 'cli')"
    }.joined(separator: ",\n")
    try createThreadDatabase(at: databaseURL, statements: "INSERT INTO threads VALUES \(rows);")

    let threads = try ThreadRepository(databaseURL: databaseURL).loadRecentThreads(limit: 6)
    #expect(threads.count == 6)
    #expect(threads.first?.id == "thread-8")

    let invalidURL = directory.appendingPathComponent("invalid.sqlite3")
    try createSQLiteDatabase(at: invalidURL, statements: "CREATE TABLE unrelated (id TEXT);")
    do {
        _ = try ThreadRepository(databaseURL: invalidURL).loadRecentThreads()
        Issue.record("Expected an invalid Codex schema to fail")
    } catch {
        let repositoryError = try #require(error as? ThreadRepositoryError)
        #expect(repositoryError.diagnostic.operation == "schema")
        #expect(repositoryError.diagnostic.primaryCode != SQLITE_OK)
        #expect(repositoryError.diagnostic.extendedCode != SQLITE_OK)
        #expect(repositoryError.localizedDescription.contains(invalidURL.path) == false)
    }
}

@Test func threadRepositoryDiscoversNewestVersionedDatabase() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tourbox-thread-discovery-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    for name in ["state_5.sqlite", "state_12.sqlite", "state_backup.sqlite", "state_20.sqlite-wal"] {
        try Data().write(to: directory.appendingPathComponent(name))
    }

    #expect(ThreadRepository.discoverDatabaseURL(in: directory).lastPathComponent == "state_12.sqlite")
}

@Test func threadDatabaseFingerprintTracksMainDatabaseAndWriteAheadLog() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tourbox-thread-fingerprint-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let databaseURL = directory.appendingPathComponent("state.sqlite3")
    let repository = ThreadRepository(databaseURL: databaseURL)

    let missing = repository.changeFingerprint()
    #expect(repository.changeFingerprint() == missing)

    try createThreadDatabase(at: databaseURL, statements: "")
    let created = repository.changeFingerprint()
    #expect(created != missing)
    #expect(repository.changeFingerprint() == created)

    let walURL = URL(fileURLWithPath: databaseURL.path + "-wal")
    try Data("first commit".utf8).write(to: walURL)
    let firstWAL = repository.changeFingerprint()
    #expect(firstWAL != created)

    try Data("second, larger commit".utf8).write(to: walURL)
    #expect(repository.changeFingerprint() != firstWAL)
}

@Test func threadDatabaseFingerprintFollowsLinksAndDetectsAtomicReplacement() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tourbox-thread-replacement-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let targetURL = directory.appendingPathComponent("target.sqlite3")
    let linkedURL = directory.appendingPathComponent("linked.sqlite3")
    try createThreadDatabase(at: targetURL, statements: "")
    try FileManager.default.createSymbolicLink(at: linkedURL, withDestinationURL: targetURL)
    let repository = ThreadRepository(databaseURL: linkedURL)
    let original = repository.changeFingerprint()

    let originalData = try Data(contentsOf: targetURL)
    let originalDate = try #require(
        FileManager.default.attributesOfItem(atPath: targetURL.path)[.modificationDate] as? Date
    )
    let replacementURL = directory.appendingPathComponent("replacement.sqlite3")
    try originalData.write(to: replacementURL)
    try FileManager.default.setAttributes([.modificationDate: originalDate], ofItemAtPath: replacementURL.path)
    try FileManager.default.removeItem(at: targetURL)
    try FileManager.default.moveItem(at: replacementURL, to: targetURL)

    #expect(repository.changeFingerprint() != original)
}

private func createThreadDatabase(at url: URL, statements: String) throws {
    try createSQLiteDatabase(at: url, statements: """
        CREATE TABLE threads (
            id TEXT NOT NULL,
            title TEXT NOT NULL,
            cwd TEXT NOT NULL,
            preview TEXT NOT NULL,
            recency_at_ms INTEGER NOT NULL,
            is_pinned INTEGER NOT NULL,
            rollout_path TEXT,
            archived INTEGER NOT NULL,
            source TEXT NOT NULL
        );
        \(statements)
        """)
}

private func createSQLiteDatabase(at url: URL, statements: String) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
        if let database { sqlite3_close(database) }
        throw ThreadRepositoryTestError.sqlite("Unable to create test database")
    }
    defer { sqlite3_close(database) }

    var errorMessage: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(database, statements, nil, nil, &errorMessage) == SQLITE_OK else {
        let message = errorMessage.map { String(cString: $0) } ?? "Unknown SQLite error"
        sqlite3_free(errorMessage)
        throw ThreadRepositoryTestError.sqlite(message)
    }
}

private enum ThreadRepositoryTestError: Error {
    case sqlite(String)
}
