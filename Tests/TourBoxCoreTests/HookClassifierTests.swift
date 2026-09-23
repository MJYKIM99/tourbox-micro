import Testing
@testable import TourBoxCore

@Test func mapsHookLifecycleToAgentStates() {
    let payload: [String: Any] = ["thread_id": "thread-1", "cwd": "/tmp/project"]
    #expect(HookClassifier.classify(event: .userPromptSubmit, payload: payload).state == .thinking)
    #expect(HookClassifier.classify(event: .permissionRequest, payload: payload).state == .needsInput)
    #expect(HookClassifier.classify(event: .postToolUse, payload: payload).state == .thinking)
    #expect(HookClassifier.classify(event: .stop, payload: payload).state == .complete)
    #expect(HookClassifier.classify(event: .interrupt, payload: payload).state == .idle)
}

@Test func interruptSignalReturnsTheTaskToIdle() {
    let payload: [String: Any] = [
        "session_id": "session-9",
        "cwd": "/tmp/project",
        "hook_event_name": "Interrupt",
        "turn_id": "turn-1",
        "permission_mode": "default"
    ]
    let signal = HookClassifier.classify(event: .interrupt, payload: payload)
    #expect(signal.state == .idle)
    #expect(signal.threadID == "session-9")
    #expect(signal.cwd == "/tmp/project")
    #expect(signal.assistantMessage == nil)
}

@Test func stopSignalCarriesSanitizedFinalMessage() {
    let payload: [String: Any] = [
        "session_id": "session-2",
        "cwd": "/tmp/project",
        "stop_hook_active": false,
        "last_assistant_message": "Fixed the parser.\n\nSee [the diff](https://example.com) for **details**."
    ]
    let signal = HookClassifier.classify(event: .stop, payload: payload)
    #expect(signal.state == .complete)
    #expect(signal.assistantMessage == "See the diff for details.")
}

@Test func onlyStopCarriesAnAssistantMessage() {
    let payload: [String: Any] = [
        "session_id": "session-3",
        "last_assistant_message": "Should be ignored here."
    ]
    for event in CodexHookEvent.allCases where event != .stop {
        #expect(HookClassifier.classify(event: event, payload: payload).assistantMessage == nil)
    }
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
