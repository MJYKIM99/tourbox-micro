import Foundation
import Testing
@testable import TourBoxCore

struct RolloutPresentationReaderTests {
    @Test func returnsLastSentenceFromLatestAgentMessage() throws {
        let url = try temporaryRollout(lines: [
            #"{"timestamp":"2026-08-03T01:00:00.000Z","type":"event_msg","payload":{"type":"task_started"}}"#,
            #"{"timestamp":"2026-08-03T01:00:01.000Z","type":"event_msg","payload":{"type":"agent_message","message":"正在修改界面。\n已经换成真正的毛玻璃效果。"}}"#
        ])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let snapshot = RolloutPresentationReader().snapshot(for: thread(rolloutPath: url.path))

        #expect(snapshot?.latestMessage == "已经换成真正的毛玻璃效果")
    }

    @Test func readsTaskCompleteLastMessageAndStripsMarkdown() throws {
        let url = try temporaryRollout(lines: [
            ###"{"timestamp":"2026-08-03T01:00:02.000Z","type":"event_msg","payload":{"type":"task_complete","last_agent_message":"## 完成\n- 已运行 30 个测试\n- [应用已安装](/Applications/TourBox%20Micro.app)！"}}"###
        ])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let snapshot = RolloutPresentationReader().snapshot(for: thread(rolloutPath: url.path))

        #expect(snapshot?.latestMessage == "应用已安装")
    }

    @Test func doesNotShowMessageFromBeforeCurrentTaskStart() throws {
        let url = try temporaryRollout(lines: [
            #"{"timestamp":"2026-08-03T01:00:00.000Z","type":"event_msg","payload":{"type":"agent_message","message":"上一轮已经完成。"}}"#,
            #"{"timestamp":"2026-08-03T01:00:03.000Z","type":"event_msg","payload":{"type":"task_started"}}"#
        ])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let snapshot = RolloutPresentationReader().snapshot(for: thread(rolloutPath: url.path))

        #expect(snapshot?.latestMessage == "Working; waiting for new progress…")
    }

    @Test func ignoresUserAndReasoningItems() throws {
        let url = try temporaryRollout(lines: [
            #"{"timestamp":"2026-08-03T01:00:00.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"最初标题"}]}}"#,
            #"{"timestamp":"2026-08-03T01:00:01.000Z","type":"response_item","payload":{"type":"reasoning","summary":[]}}"#,
            #"{"timestamp":"2026-08-03T01:00:02.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"第一句。最后进展。"}]}}"#
        ])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let snapshot = RolloutPresentationReader().snapshot(for: thread(rolloutPath: url.path))

        #expect(snapshot?.latestMessage == "最后进展")
    }

    @Test func presentationCacheDropsThreadsOutsideRecentWindow() {
        var cache = RolloutPresentationCache()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let didApplyInitialSnapshots = cache.apply([
            RolloutPresentationSnapshot(threadID: "keep", latestMessage: "保留", updatedAt: now),
            RolloutPresentationSnapshot(threadID: "drop", latestMessage: "清理", updatedAt: now)
        ])
        #expect(didApplyInitialSnapshots)
        #expect(cache.count == 2)
        let didApplyDuplicateSnapshot = cache.apply([
            RolloutPresentationSnapshot(threadID: "keep", latestMessage: "保留", updatedAt: now)
        ])
        #expect(!didApplyDuplicateSnapshot)

        let didPrune = cache.retain(threadIDs: ["keep"])
        #expect(didPrune)
        #expect(cache.count == 1)
        #expect(cache["keep"] == "保留")
        #expect(cache["drop"] == nil)
        let didPruneAgain = cache.retain(threadIDs: ["keep"])
        #expect(!didPruneAgain)
    }

    private func temporaryRollout(lines: [String]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("rollout.jsonl")
        try lines.joined(separator: "\n").data(using: .utf8)?.write(to: url)
        return url
    }

    private func thread(rolloutPath: String) -> CodexThread {
        CodexThread(
            id: "thread-1",
            title: "不应显示的最初标题",
            cwd: "/tmp/project",
            recencyAtMilliseconds: 1,
            rolloutPath: rolloutPath
        )
    }
}
