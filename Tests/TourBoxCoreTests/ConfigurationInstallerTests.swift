import Foundation
import Testing
@testable import TourBoxCore

@Test func hookInstallPreservesExistingEntriesAndIsIdempotent() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let url = directory.appendingPathComponent("hooks.json")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let original: [String: Any] = [
        "hooks": [
            "Stop": [["hooks": [["type": "command", "command": "existing-command"]]]],
            "SessionStart": [["hooks": [["type": "command", "command": "keep-me"]]]]
        ]
    ]
    let data = try JSONSerialization.data(withJSONObject: original)
    try data.write(to: url)

    let token = String(repeating: "a", count: 64)
    _ = try ConfigurationInstaller.installHooks(at: url, authenticationToken: token)
    _ = try ConfigurationInstaller.installHooks(at: url, authenticationToken: token)

    let installed = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let hooks = try #require(installed["hooks"] as? [String: Any])
    let stopEntries = try #require(hooks["Stop"] as? [Any])
    #expect(stopEntries.count == 2)
    #expect(String(data: try JSONSerialization.data(withJSONObject: stopEntries), encoding: .utf8)?.contains("existing-command") == true)
    #expect(hooks["SessionStart"] != nil)
    for event in CodexHookEvent.allCases {
        let entries = try #require(hooks[event.rawValue] as? [Any])
        let managedCount = try entries.filter { entry in
            let data = try JSONSerialization.data(
                withJSONObject: entry,
                options: .withoutEscapingSlashes
            )
            return String(data: data, encoding: .utf8)?.contains(
                "127.0.0.1:50501/tourbox-hook/\(event.rawValue)"
            ) == true
        }.count
        #expect(managedCount == 1)
    }
    #expect(ConfigurationInstaller.managedHooksInstalled(at: url, authenticationToken: token))
    #expect(!ConfigurationInstaller.managedHooksInstalled(at: url, authenticationToken: String(repeating: "b", count: 64)))
}

@Test func keybindingInstallPreservesUnrelatedBindings() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let url = directory.appendingPathComponent("keybindings.json")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let original: [[String: String]] = [["command": "hotkeyWindow", "key": "Alt+Space"]]
    try JSONSerialization.data(withJSONObject: original).write(to: url)
    _ = try ConfigurationInstaller.installKeybindings(at: url)

    let installed = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: String]])
    #expect(installed.contains(["command": "hotkeyWindow", "key": "Alt+Space"]))
    #expect(installed.contains(["command": "composer.toggleFastMode", "key": "F13"]))
    #expect(installed.contains(["command": "composer.togglePlanMode", "key": "F14"]))
    #expect(installed.contains(["command": "forkThread", "key": "F15"]))
    #expect(!installed.contains(where: { $0["key"] == "F16" || $0["key"] == "F17" }))
}

@Test func keybindingInstallPreservesManualReasoningBindings() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let url = directory.appendingPathComponent("keybindings.json")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let original: [[String: String]] = [
        ["command": "composer.increaseReasoningEffort", "key": "Ctrl+Alt+="],
        ["command": "composer.decreaseReasoningEffort", "key": "Ctrl+Alt+-"],
        ["command": "composer.increaseReasoningEffort", "key": "F16"],
        ["command": "composer.decreaseReasoningEffort", "key": "F17"]
    ]
    try JSONSerialization.data(withJSONObject: original).write(to: url)
    _ = try ConfigurationInstaller.installKeybindings(at: url)

    let installed = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: String]])
    #expect(installed.contains(["command": "composer.increaseReasoningEffort", "key": "Ctrl+Alt+="]))
    #expect(installed.contains(["command": "composer.decreaseReasoningEffort", "key": "Ctrl+Alt+-"]))
    #expect(installed.contains(["command": "composer.increaseReasoningEffort", "key": "F16"]))
    #expect(installed.contains(["command": "composer.decreaseReasoningEffort", "key": "F17"]))
}

@Test func keybindingDiagnosticsRequireExactCommandAndKeyPairs() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let url = directory.appendingPathComponent("keybindings.json")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let incomplete: [[String: String]] = [
        ["command": "someOtherCommand", "key": "F13"],
        ["command": "composer.increaseReasoningEffort", "key": "F16"],
        ["command": "someOtherCommand", "key": "F17"]
    ]
    try JSONSerialization.data(withJSONObject: incomplete).write(to: url)
    #expect(!ConfigurationInstaller.managedKeybindingsInstalled(at: url))
    #expect(!ConfigurationInstaller.manualReasoningKeybindingsInstalled(at: url))

    let complete: [[String: String]] = [
        ["command": "composer.toggleFastMode", "key": "F13"],
        ["command": "composer.togglePlanMode", "key": "F14"],
        ["command": "forkThread", "key": "F15"],
        ["command": "composer.increaseReasoningEffort", "key": "F16"],
        ["command": "composer.decreaseReasoningEffort", "key": "F17"]
    ]
    try JSONSerialization.data(withJSONObject: complete).write(to: url)
    #expect(ConfigurationInstaller.managedKeybindingsInstalled(at: url))
    #expect(ConfigurationInstaller.manualReasoningKeybindingsInstalled(at: url))
}
