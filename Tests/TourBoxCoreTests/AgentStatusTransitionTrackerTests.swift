import Foundation
import Testing
@testable import TourBoxCore

@Test func statusTransitionTrackerSuppressesLaunchHistoryAndReportsCompletionOnce() {
    let thread = CodexThread(
        id: "task-1",
        title: "实现悬浮详情",
        cwd: "/tmp/tourbox-micro",
        recencyAtMilliseconds: 1
    )
    var tracker = AgentStatusTransitionTracker()

    #expect(tracker.notificationCandidate(in: [
        AgentSlot(index: 1, thread: thread, state: .thinking)
    ]) == nil)

    let completion = tracker.notificationCandidate(in: [
        AgentSlot(index: 1, thread: thread, state: .complete)
    ])
    #expect(completion?.thread?.id == "task-1")
    #expect(completion?.state == .complete)

    #expect(tracker.notificationCandidate(in: [
        AgentSlot(index: 1, thread: thread, state: .complete)
    ]) == nil)
}

@Test func statusTransitionTrackerChoosesErrorWhenSeveralTasksChangeTogether() {
    let inputThread = CodexThread(
        id: "task-input",
        title: "等待确认",
        cwd: "/tmp/project-a",
        recencyAtMilliseconds: 2
    )
    let errorThread = CodexThread(
        id: "task-error",
        title: "构建失败",
        cwd: "/tmp/project-b",
        recencyAtMilliseconds: 1
    )
    var tracker = AgentStatusTransitionTracker()
    let running = [
        AgentSlot(index: 1, thread: inputThread, state: .thinking),
        AgentSlot(index: 2, thread: errorThread, state: .thinking)
    ]
    #expect(tracker.notificationCandidate(in: running) == nil)

    let candidate = tracker.notificationCandidate(in: [
        AgentSlot(index: 1, thread: inputThread, state: .needsInput),
        AgentSlot(index: 2, thread: errorThread, state: .error)
    ])
    #expect(candidate?.thread?.id == "task-error")
    #expect(candidate?.state == .error)
}

@Test func transientNotificationExpiresWhenTaskReturnsToRunning() {
    let thread = CodexThread(
        id: "task-input",
        title: "等待确认",
        cwd: "/tmp/project",
        recencyAtMilliseconds: 1
    )
    let notification = AgentSlot(index: 1, thread: thread, state: .needsInput)

    #expect(AgentStatusTransitionTracker.notificationIsCurrent(
        notification,
        in: [notification]
    ))
    #expect(!AgentStatusTransitionTracker.notificationIsCurrent(
        notification,
        in: [AgentSlot(index: 1, thread: thread, state: .thinking)]
    ))
    #expect(!AgentStatusTransitionTracker.notificationIsCurrent(notification, in: []))
}
