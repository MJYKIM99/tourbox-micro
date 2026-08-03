import Testing
@testable import TourBoxCore

@Test func extractsUsefulTitleFromDelegationMetadata() {
    let raw = """
    <codex_delegation>
      <source_thread_id>thread-123</source_thread_id>
      <input>Investigate the iOS Build 58 confirmation-card regression. Trace the exact rendering path and report evidence.</input>
    </codex_delegation>
    """

    #expect(ThreadDisplayText.title(rawTitle: raw, preview: raw)
        == "Investigate the iOS Build 58 confirmation-card regression.")
}

@Test func preservesNormalUserTaskTitles() {
    let title = "把 TourBox HUD 改成带状态动画的玻璃灯阵"
    #expect(ThreadDisplayText.title(rawTitle: title, preview: title) == title)
}

@Test func boundsDelegatedTitlesWithoutLeakingMarkup() {
    let request = String(repeating: "研究任务需要整理证据并输出报告", count: 12)
    let raw = "<codex_delegation><input>\(request)</input></codex_delegation>"
    let title = ThreadDisplayText.title(rawTitle: raw, preview: raw)

    #expect(title.count <= 109)
    #expect(title.hasSuffix("…"))
    #expect(!title.contains("codex_delegation"))
}
