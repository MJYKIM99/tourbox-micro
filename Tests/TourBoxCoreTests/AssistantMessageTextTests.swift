import Testing
@testable import TourBoxCore

@Test func conciseKeepsOnlyTheLastLine() {
    let message = "First I checked the schema.\nThen I fixed the parser.\nThe build is green."
    #expect(AssistantMessageText.concise(message) == "The build is green.")
}

@Test func conciseKeepsOnlyTheLastSentenceAfterSentencePunctuation() {
    #expect(AssistantMessageText.concise("Checked the schema! The build is green!") == "The build is green")
}

@Test func conciseStripsMarkdownAndListMarkers() {
    let message = """
    Done:
    - Removed the **stale** binding.
    - See [the audit](https://example.com/audit) for context.
    """
    #expect(AssistantMessageText.concise(message) == "See the audit for context.")
}

@Test func conciseDropsImagesAndDelegationBlocks() {
    let message = """
    <codex_delegation>internal routing</codex_delegation>
    ![hud](/tmp/hud.png)
    Updated the glass lights.
    """
    #expect(AssistantMessageText.concise(message) == "Updated the glass lights.")
}

@Test func conciseRejectsEmptyInput() {
    #expect(AssistantMessageText.concise(nil) == nil)
    #expect(AssistantMessageText.concise("") == nil)
    #expect(AssistantMessageText.concise("   \n\n  ") == nil)
}

@Test func conciseBoundsLongMessages() {
    let message = String(repeating: "word ", count: 200)
    let concise = try? #require(AssistantMessageText.concise(message))
    #expect((concise?.count ?? 0) <= AssistantMessageText.maximumLength)
    #expect(concise?.hasSuffix("…") == true)
}

@Test func conciseCollapsesWhitespace() {
    #expect(AssistantMessageText.concise("Done.\n\n  All    checks pass.") == "All checks pass.")
}
