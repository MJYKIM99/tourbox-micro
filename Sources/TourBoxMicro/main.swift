import AppKit
import ApplicationServices
import Foundation
import TourBoxCore

private let codexDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
private let arguments = Set(CommandLine.arguments.dropFirst())

if arguments.contains("--install") {
    do {
        let hooks = try ConfigurationInstaller.installHooks(at: codexDirectory.appendingPathComponent("hooks.json"))
        let keys = try ConfigurationInstaller.installKeybindings(at: codexDirectory.appendingPathComponent("keybindings.json"))
        print(hooks.message)
        print(keys.message)
        [hooks.backupPath, keys.backupPath].compactMap { $0 }.forEach { print("Backup: \($0)") }
        exit(EXIT_SUCCESS)
    } catch {
        fputs("Install failed: \(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

if arguments.contains("--uninstall-hooks") {
    do {
        let result = try ConfigurationInstaller.uninstallHooks(at: codexDirectory.appendingPathComponent("hooks.json"))
        print(result.message)
        if let backup = result.backupPath { print("Backup: \(backup)") }
        exit(EXIT_SUCCESS)
    } catch {
        fputs("Uninstall failed: \(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

if arguments.contains("--doctor") {
    let fileManager = FileManager.default
    let hooksURL = codexDirectory.appendingPathComponent("hooks.json")
    let keybindingsURL = codexDirectory.appendingPathComponent("keybindings.json")
    let hooksText = (try? String(contentsOf: hooksURL, encoding: .utf8)) ?? ""
    print("Codex app: \(NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") != nil ? "found" : "missing")")
    print("State database: \(fileManager.fileExists(atPath: codexDirectory.appendingPathComponent("state_5.sqlite").path) ? "found" : "missing")")
    print("Lifecycle hooks: \(hooksText.contains(ConfigurationInstaller.hookMarker) ? "installed" : "not installed")")
    print("Managed shortcuts F13-F15: \(ConfigurationInstaller.managedKeybindingsInstalled(at: keybindingsURL) ? "installed" : "not installed")")
    print("Manual reasoning F16/F17: \(ConfigurationInstaller.manualReasoningKeybindingsInstalled(at: keybindingsURL) ? "assigned" : "not assigned")")
    print("Accessibility: \(AXIsProcessTrusted() ? "granted" : "not granted")")
    exit(EXIT_SUCCESS)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
