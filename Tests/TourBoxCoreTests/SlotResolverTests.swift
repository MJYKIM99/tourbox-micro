import Foundation
import Testing
@testable import TourBoxCore

@Test func priorityModeSurfacesAttentionBeforeRecentThreads() {
    let recent = CodexThread(id: "recent", title: "Recent", cwd: "/recent", recencyAtMilliseconds: 200)
    let waiting = CodexThread(id: "waiting", title: "Waiting", cwd: "/waiting", recencyAtMilliseconds: 100)
    let activity = AgentActivity(threadID: "waiting", state: .needsInput)
    var resolver = SlotResolver(slotCount: 1)

    let slots = resolver.resolve(threads: [recent, waiting], activities: [activity], mode: .priority)
    #expect(slots.first?.thread?.id == "waiting")
    #expect(slots.first?.state == .needsInput)
}

@Test func preservesPhysicalPositionsWhenRankingOrderChangesWithinSelectedSet() {
    let a = CodexThread(id: "a", title: "A", cwd: "/a", recencyAtMilliseconds: 200)
    let b = CodexThread(id: "b", title: "B", cwd: "/b", recencyAtMilliseconds: 100)
    var resolver = SlotResolver(slotCount: 2)
    let initial = resolver.resolve(threads: [a, b], activities: [], mode: .recent)
    #expect(initial.map { $0.thread?.id } == ["a", "b"])

    let updatedA = CodexThread(id: "a", title: "A", cwd: "/a", recencyAtMilliseconds: 200)
    let updatedB = CodexThread(id: "b", title: "B", cwd: "/b", recencyAtMilliseconds: 300)
    let stable = resolver.resolve(threads: [updatedA, updatedB], activities: [], mode: .recent)
    #expect(stable.map { $0.thread?.id } == ["a", "b"])
}

@Test func priorityModeRanksUnreadCompletionBeforeThinking() {
    let thinking = CodexThread(id: "thinking", title: "Thinking", cwd: "/thinking", recencyAtMilliseconds: 300)
    let unread = CodexThread(id: "unread", title: "Unread", cwd: "/unread", recencyAtMilliseconds: 100)
    let activities = [
        AgentActivity(threadID: "thinking", state: .thinking),
        AgentActivity(threadID: "unread", state: .complete)
    ]
    var resolver = SlotResolver(slotCount: 1)
    let slots = resolver.resolve(threads: [thinking, unread], activities: activities, mode: .priority)
    #expect(slots.first?.thread?.id == "unread")
}

@Test func pinnedModeLeavesUnusedSlotsEmpty() {
    let pinned = CodexThread(
        id: "pinned",
        title: "Pinned",
        cwd: "/pinned",
        recencyAtMilliseconds: 100,
        isPinned: true
    )
    let recent = CodexThread(id: "recent", title: "Recent", cwd: "/recent", recencyAtMilliseconds: 200)
    var resolver = SlotResolver(slotCount: 2)
    let slots = resolver.resolve(threads: [recent, pinned], activities: [], mode: .pinned)
    #expect(slots.map { $0.thread?.id } == ["pinned", nil])
}

@Test func cwdFallbackDoesNotLeakThreadSpecificStateToSiblingChat() {
    let first = CodexThread(id: "first", title: "First", cwd: "/shared", recencyAtMilliseconds: 200)
    let second = CodexThread(id: "second", title: "Second", cwd: "/shared", recencyAtMilliseconds: 100)
    let activity = AgentActivity(threadID: "first", cwd: "/shared", state: .thinking)
    var resolver = SlotResolver(slotCount: 2)
    let slots = resolver.resolve(threads: [first, second], activities: [activity], mode: .recent)
    #expect(slots.first(where: { $0.thread?.id == "first" })?.state == .thinking)
    #expect(slots.first(where: { $0.thread?.id == "second" })?.state == .idle)
}
