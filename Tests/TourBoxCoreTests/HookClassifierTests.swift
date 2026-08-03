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
