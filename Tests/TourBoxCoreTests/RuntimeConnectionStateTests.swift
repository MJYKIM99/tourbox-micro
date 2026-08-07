import Testing
@testable import TourBoxCore

@Test func recoveredCodexDatabaseErrorRestoresUnderlyingConnectionStatus() {
    var state = RuntimeConnectionState()
    state.setTourBoxStatus("TourBox 已连接")
    state.setCodexStateError("Codex state: unable to open database file")
    #expect(state.displayText == "Codex state: unable to open database file")

    let didClear = state.clearCodexStateError()
    #expect(didClear)
    #expect(state.displayText == "TourBox 已连接")
    let didClearAgain = state.clearCodexStateError()
    #expect(!didClearAgain)
}

@Test func codexDatabaseErrorHasPriorityOverHookAndDeviceStatus() {
    var state = RuntimeConnectionState()
    state.setTourBoxStatus("等待 TourBox")
    state.setHookServerError("Hook server: unavailable")
    #expect(state.displayText == "Hook server: unavailable")

    state.setCodexStateError("Codex state: busy")
    #expect(state.displayText == "Codex state: busy")
}
