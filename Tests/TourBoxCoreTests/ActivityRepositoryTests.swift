import Foundation
import Testing
@testable import TourBoxCore

@Test func persistsLatestTaskStateAcrossRepositoryInstances() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tourbox-status-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let databaseURL = directory.appendingPathComponent("status.sqlite3")
    let startedAt = Date(timeIntervalSince1970: 1_800_000_000)

    do {
        let repository = try ActivityRepository(databaseURL: databaseURL)
        try repository.upsert(
            AgentActivity(
                threadID: "thread-1",
                cwd: "/project",
                state: .thinking,
                updatedAt: startedAt,
                detail: "running"
            )
        )
    }

    let reopened = try ActivityRepository(databaseURL: databaseURL)
    let restored = try reopened.loadActivities()
    #expect(restored.count == 1)
    #expect(restored.first?.threadID == "thread-1")
    #expect(restored.first?.state == .thinking)
    #expect(restored.first?.detail == "running")
}

@Test func ignoresOlderLifecycleWritesAndAcknowledgesOnlyCompletion() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tourbox-status-order-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = try ActivityRepository(databaseURL: directory.appendingPathComponent("status.sqlite3"))
    let newer = Date(timeIntervalSince1970: 1_800_000_100)
    let older = Date(timeIntervalSince1970: 1_800_000_000)

    try repository.upsert(
        AgentActivity(threadID: "thread-1", cwd: "/project", state: .complete, updatedAt: newer)
    )
    let changed = try repository.upsert(
        AgentActivity(threadID: "thread-1", cwd: "/project", state: .thinking, updatedAt: older)
    )
    #expect(changed == false)
    #expect(try repository.loadActivities().first?.state == .complete)

    let thread = CodexThread(
        id: "thread-1",
        title: "Task",
        cwd: "/project",
        recencyAtMilliseconds: 1
    )
    try repository.acknowledgeCompletion(for: thread, at: newer.addingTimeInterval(1))
    #expect(try repository.loadActivities().first?.state == .idle)
}

@Test func recoversLatestLifecycleEdgeFromRolloutTail() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tourbox-rollout-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let activeURL = directory.appendingPathComponent("active.jsonl")
    let completeURL = directory.appendingPathComponent("complete.jsonl")
    try """
        {"timestamp":"2026-08-03T05:00:00.000Z","type":"event_msg","payload":{"type":"task_complete"}}
        {"timestamp":"2026-08-03T05:01:00.000Z","type":"event_msg","payload":{"type":"task_started"}}
        """.write(to: activeURL, atomically: true, encoding: .utf8)
    try """
        {"timestamp":"2026-08-03T05:00:00.000Z","type":"event_msg","payload":{"type":"task_started"}}
        {"timestamp":"2026-08-03T05:01:00.000Z","type":"event_msg","payload":{"type":"task_complete"}}
        """.write(to: completeURL, atomically: true, encoding: .utf8)

    let active = CodexThread(
        id: "active",
        title: "Active",
        cwd: "/active",
        recencyAtMilliseconds: 2,
        rolloutPath: activeURL.path
    )
    let complete = CodexThread(
        id: "complete",
        title: "Complete",
        cwd: "/complete",
        recencyAtMilliseconds: 1,
        rolloutPath: completeURL.path
    )
    let snapshots = RolloutStateReconciler(
        maximumRecoverableActiveAge: 1_000_000_000
    ).snapshots(for: [active, complete])
    #expect(snapshots.first(where: { $0.threadID == "active" })?.state == .thinking)
    #expect(snapshots.first(where: { $0.threadID == "complete" })?.state == .complete)
}

@Test func expiresOnlyStaleThinkingRows() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tourbox-status-expiry-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = try ActivityRepository(databaseURL: directory.appendingPathComponent("status.sqlite3"))
    let old = Date(timeIntervalSince1970: 1_700_000_000)
    try repository.upsert(AgentActivity(threadID: "old-run", state: .thinking, updatedAt: old))
    try repository.upsert(AgentActivity(threadID: "old-input", state: .needsInput, updatedAt: old))

    let expired = try repository.expireThinking(
        before: Date(timeIntervalSince1970: 1_700_000_100),
        at: Date(timeIntervalSince1970: 1_700_000_200)
    )
    let restored = try repository.loadActivities()
    #expect(expired == 1)
    #expect(restored.first(where: { $0.threadID == "old-run" })?.state == .idle)
    #expect(restored.first(where: { $0.threadID == "old-input" })?.state == .needsInput)
}

@Test func expiresStaleThinkingAndInputRowsForStartupRecovery() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tourbox-active-expiry-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = try ActivityRepository(databaseURL: directory.appendingPathComponent("status.sqlite3"))
    let old = Date(timeIntervalSince1970: 1_700_000_000)
    let recent = Date(timeIntervalSince1970: 1_700_000_150)
    try repository.upsert(AgentActivity(threadID: "old-run", state: .thinking, updatedAt: old))
    try repository.upsert(AgentActivity(threadID: "old-input", state: .needsInput, updatedAt: old))
    try repository.upsert(AgentActivity(threadID: "recent-input", state: .needsInput, updatedAt: recent))

    let expired = try repository.expireStaleActiveStates(
        before: Date(timeIntervalSince1970: 1_700_000_100),
        at: Date(timeIntervalSince1970: 1_700_000_200)
    )
    let restored = try repository.loadActivities()
    #expect(expired == 2)
    #expect(restored.first(where: { $0.threadID == "old-run" })?.state == .idle)
    #expect(restored.first(where: { $0.threadID == "old-input" })?.state == .idle)
    #expect(restored.first(where: { $0.threadID == "recent-input" })?.state == .needsInput)
}

@Test func maintenanceRemovesStaleOrphansAndExpiresRemainingActiveRows() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tourbox-status-maintenance-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = try ActivityRepository(databaseURL: directory.appendingPathComponent("status.sqlite3"))
    let old = Date(timeIntervalSince1970: 1_700_000_000)
    let recent = Date(timeIntervalSince1970: 1_700_000_150)
    let cutoff = Date(timeIntervalSince1970: 1_700_000_100)
    let maintenanceDate = Date(timeIntervalSince1970: 1_700_000_200)

    try repository.upsert(AgentActivity(threadID: "orphan", state: .thinking, updatedAt: old))
    try repository.upsert(AgentActivity(threadID: "kept", state: .thinking, updatedAt: old))
    try repository.upsert(AgentActivity(cwd: "/cwd-only", state: .needsInput, updatedAt: old))
    try repository.upsert(AgentActivity(threadID: "recent", state: .thinking, updatedAt: recent))
    try repository.upsert(AgentActivity(threadID: "fresh-orphan", state: .thinking, updatedAt: recent))
    try repository.upsert(AgentActivity(threadID: "idle-orphan", state: .idle, updatedAt: recent))
    try repository.upsert(AgentActivity(threadID: "completed", state: .complete, updatedAt: old))

    let result = try repository.performMaintenance(
        keepingThreadIDs: ["kept", "recent", "completed"],
        activeBefore: cutoff,
        at: maintenanceDate
    )
    let restored = try repository.loadActivities()

    #expect(result.removedOrphanCount == 2)
    #expect(result.expiredActiveCount == 2)
    #expect(restored.first(where: { $0.threadID == "orphan" }) == nil)
    #expect(restored.first(where: { $0.threadID == "kept" })?.state == .idle)
    #expect(restored.first(where: { $0.cwd == "/cwd-only" })?.state == .idle)
    #expect(restored.first(where: { $0.threadID == "recent" })?.state == .thinking)
    #expect(restored.first(where: { $0.threadID == "fresh-orphan" })?.state == .thinking)
    #expect(restored.first(where: { $0.threadID == "idle-orphan" }) == nil)
    #expect(restored.first(where: { $0.threadID == "completed" })?.state == .complete)
}

@Test func rolloutMonitorParsesOnlyChangedFiles() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tourbox-rollout-monitor-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let rolloutURL = directory.appendingPathComponent("active.jsonl")
    let started = """
        {"timestamp":"2026-08-03T05:00:00.000Z","type":"event_msg","payload":{"type":"task_started"}}
        """
    try started.write(to: rolloutURL, atomically: true, encoding: .utf8)
    let thread = CodexThread(
        id: "active",
        title: "Active",
        cwd: "/active",
        recencyAtMilliseconds: 1,
        rolloutPath: rolloutURL.path
    )
    let monitor = RolloutActivityMonitor(
        reconciler: RolloutStateReconciler(maximumRecoverableActiveAge: 1_000_000_000)
    )

    #expect(monitor.changedSnapshots(for: [thread], force: true).count == 1)
    #expect(monitor.changedSnapshots(for: [thread]).isEmpty)
    let handle = try FileHandle(forWritingTo: rolloutURL)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("\n{\"type\":\"event_msg\",\"payload\":{\"type\":\"agent_message\"}}\n".utf8))
    try handle.close()
    #expect(monitor.changedSnapshots(for: [thread]).count == 1)
}

@Test func rolloutChangeMonitorSharesOneBoundedFileScan() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tourbox-rollout-shared-monitor-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let firstURL = directory.appendingPathComponent("first.jsonl")
    let secondURL = directory.appendingPathComponent("second.jsonl")
    try "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\"}}\n"
        .write(to: firstURL, atomically: true, encoding: .utf8)
    try "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\"}}\n"
        .write(to: secondURL, atomically: true, encoding: .utf8)

    let threads = [
        CodexThread(
            id: "first",
            title: "First",
            cwd: "/first",
            recencyAtMilliseconds: 2,
            rolloutPath: firstURL.path
        ),
        CodexThread(
            id: "second",
            title: "Second",
            cwd: "/second",
            recencyAtMilliseconds: 1,
            rolloutPath: secondURL.path
        )
    ]
    let monitor = RolloutChangeMonitor(maximumThreads: 1)

    #expect(monitor.changedThreads(for: threads, force: true).map(\.id) == ["first"])
    #expect(monitor.changedThreads(for: threads).isEmpty)

    let handle = try FileHandle(forWritingTo: firstURL)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("changed".utf8))
    try handle.close()
    #expect(monitor.changedThreads(for: threads).map(\.id) == ["first"])
}

@Test func rolloutChangeMonitorFollowsSymbolicLinkTargets() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tourbox-rollout-link-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let targetURL = directory.appendingPathComponent("target.jsonl")
    let linkedURL = directory.appendingPathComponent("linked.jsonl")
    try Data("initial".utf8).write(to: targetURL)
    try FileManager.default.createSymbolicLink(at: linkedURL, withDestinationURL: targetURL)
    let thread = CodexThread(
        id: "linked",
        title: "Linked",
        cwd: "/linked",
        recencyAtMilliseconds: 1,
        rolloutPath: linkedURL.path
    )
    let monitor = RolloutChangeMonitor(maximumThreads: 1)

    #expect(monitor.changedThreads(for: [thread], force: true).map(\.id) == ["linked"])
    #expect(monitor.changedThreads(for: [thread]).isEmpty)
    let handle = try FileHandle(forWritingTo: targetURL)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(" changed".utf8))
    try handle.close()
    #expect(monitor.changedThreads(for: [thread]).map(\.id) == ["linked"])
}
