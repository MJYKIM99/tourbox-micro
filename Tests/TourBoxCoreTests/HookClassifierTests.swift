import Testing
@testable import TourBoxCore

@Test func mapsHookLifecycleToAgentStates() {
    let payload: [String: Any] = ["thread_id": "thread-1", "cwd": "/tmp/project"]
    #expect(HookClassifier.classify(event: .userPromptSubmit, payload: payload).state == .thinking)
    #expect(HookClassifier.classify(event: .permissionRequest, payload: payload).state == .needsInput)
    #expect(HookClassifier.classify(event: .postToolUse, payload: payload).state == .thinking)
    #expect(HookClassifier.classify(event: .stop, payload: payload).state == .complete)
}

@Test func detectsNestedStopFailure() {
    let payload: [String: Any] = [
        "session_id": "session-1",
        "result": ["is_error": true, "message": "tool failed"]
    ]
    let signal = HookClassifier.classify(event: .stop, payload: payload)
    #expect(signal.state == .error)
    #expect(signal.threadID == "session-1")
}

@Test func permissionSignalIsCanceledWhenToolUseProvesWorkContinued() {
    var gate = HookSignalGate()
    let permission = HookSignal(
        threadID: "thread-1",
        cwd: "/project",
        state: .needsInput,
        detail: "tool"
    )
    #expect(gate.receive(permission) == .deferInput(identityKey: "thread:thread-1"))

    let continued = HookSignal(
        threadID: nil,
        cwd: "/project",
        state: .thinking,
        detail: nil
    )
    #expect(gate.receive(continued) == .apply(
        continued,
        cancelDeferredIdentityKey: "thread:thread-1"
    ))
    #expect(gate.flushDeferredInput(for: "thread:thread-1") == nil)
}

@Test func permissionSignalCommitsWhenNoNewerLifecycleEventArrives() {
    var gate = HookSignalGate()
    let permission = HookSignal(
        threadID: "thread-2",
        cwd: "/project",
        state: .needsInput,
        detail: "approval"
    )
    #expect(gate.receive(permission) == .deferInput(identityKey: "thread:thread-2"))
    #expect(gate.flushDeferredInput(for: "thread:thread-2") == permission)
    #expect(gate.flushDeferredInput(for: "thread:thread-2") == nil)
}
