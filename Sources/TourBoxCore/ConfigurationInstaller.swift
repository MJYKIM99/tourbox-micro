import Foundation

public struct ConfigurationChange: Equatable, Sendable {
    public let changed: Bool
    public let backupPath: String?
    public let message: String

    public init(changed: Bool, backupPath: String?, message: String) {
        self.changed = changed
        self.backupPath = backupPath
        self.message = message
    }
}

public enum ConfigurationInstallerError: LocalizedError {
    case invalidRoot(URL, expected: String)
    case malformedHooks(URL)

    public var errorDescription: String? {
        switch self {
        case .invalidRoot(let url, let expected):
            "Expected \(expected) in \(url.path)"
        case .malformedHooks(let url):
            "Expected a top-level hooks object in \(url.path)"
        }
    }
}

public enum ConfigurationInstaller {
    public static let hookMarker = "127.0.0.1:50501/tourbox-hook/"

    private static let managedKeybindings: [[String: String]] = [
        ["command": "composer.toggleFastMode", "key": "F13"],
        ["command": "composer.togglePlanMode", "key": "F14"],
        ["command": "forkThread", "key": "F15"]
    ]

    private static let manualReasoningKeybindings: [[String: String]] = [
        ["command": "composer.increaseReasoningEffort", "key": "F16"],
        ["command": "composer.decreaseReasoningEffort", "key": "F17"]
    ]

    @discardableResult
    public static func installHooks(at url: URL) throws -> ConfigurationChange {
        var root = try loadJSONObject(at: url, defaultValue: ["hooks": [String: Any]()])
        guard var rootDictionary = root as? [String: Any] else {
            throw ConfigurationInstallerError.invalidRoot(url, expected: "a JSON object")
        }
        guard var hooks = rootDictionary["hooks"] as? [String: Any] else {
            throw ConfigurationInstallerError.malformedHooks(url)
        }

        var didChange = false
        for event in CodexHookEvent.allCases {
            var entries = hooks[event.rawValue] as? [Any] ?? []
            let originalCount = entries.count
            entries.removeAll(where: containsManagedHook)
            let command = hookCommand(for: event)
            entries.append([
                "hooks": [[
                    "type": "command",
                    "command": command,
                    "timeout": 2
                ]]
            ])
            hooks[event.rawValue] = entries
            didChange = didChange || entries.count != originalCount || !containsCommand(command, in: entries)
        }

        rootDictionary["hooks"] = hooks
        root = rootDictionary
        let backup = try writeJSONObject(root, to: url)
        return ConfigurationChange(
            changed: true,
            backupPath: backup?.path,
            message: didChange ? "Installed TourBox Micro lifecycle hooks." : "Refreshed TourBox Micro lifecycle hooks."
        )
    }

    @discardableResult
    public static func uninstallHooks(at url: URL) throws -> ConfigurationChange {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .init(changed: false, backupPath: nil, message: "No hooks file exists.")
        }
        let root = try loadJSONObject(at: url, defaultValue: [String: Any]())
        guard var rootDictionary = root as? [String: Any],
              var hooks = rootDictionary["hooks"] as? [String: Any] else {
            throw ConfigurationInstallerError.malformedHooks(url)
        }

        var removed = 0
        for event in CodexHookEvent.allCases {
            guard var entries = hooks[event.rawValue] as? [Any] else { continue }
            let oldCount = entries.count
            entries.removeAll(where: containsManagedHook)
            removed += oldCount - entries.count
            hooks[event.rawValue] = entries
        }
        guard removed > 0 else {
            return .init(changed: false, backupPath: nil, message: "No TourBox Micro hooks were installed.")
        }

        rootDictionary["hooks"] = hooks
        let backup = try writeJSONObject(rootDictionary, to: url)
        return .init(
            changed: true,
            backupPath: backup?.path,
            message: "Removed \(removed) TourBox Micro hooks."
        )
    }

    @discardableResult
    public static func installKeybindings(at url: URL) throws -> ConfigurationChange {
        let root = try loadJSONObject(at: url, defaultValue: [Any]())
        guard var bindings = root as? [[String: Any]] else {
            throw ConfigurationInstallerError.invalidRoot(url, expected: "a JSON array")
        }

        var changed = false
        for managed in managedKeybindings {
            let command = managed["command"]!
            let key = managed["key"]!
            bindings.removeAll { binding in
                guard let existingCommand = binding["command"] as? String,
                      let existingKey = binding["key"] as? String else { return false }
                if existingCommand == command && existingKey == key {
                    return true
                }
                return existingCommand == command || existingKey.caseInsensitiveCompare(key) == .orderedSame
            }
            bindings.append(managed)
            changed = true
        }

        let backup = try writeJSONObject(bindings, to: url)
        return .init(
            changed: changed,
            backupPath: backup?.path,
            message: "Installed Fast, Plan, and Fork bindings. Assign reasoning F16/F17 manually in Codex."
        )
    }

    public static func managedKeybindingsInstalled(at url: URL) -> Bool {
        containsKeybindings(managedKeybindings, at: url)
    }

    public static func manualReasoningKeybindingsInstalled(at url: URL) -> Bool {
        containsKeybindings(manualReasoningKeybindings, at: url)
    }

    public static func hookCommand(for event: CodexHookEvent) -> String {
        "curl -s --max-time 1 -X POST http://\(hookMarker)\(event.rawValue) " +
        "-H 'Content-Type: application/json' --data-binary @- >/dev/null 2>&1 || true; printf '{}'"
    }

    private static func containsManagedHook(_ value: Any) -> Bool {
        if let string = value as? String {
            return string.contains(hookMarker)
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.values.contains(where: containsManagedHook)
        }
        if let array = value as? [Any] {
            return array.contains(where: containsManagedHook)
        }
        return false
    }

    private static func containsCommand(_ command: String, in value: Any) -> Bool {
        if let string = value as? String {
            return string == command
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.values.contains { containsCommand(command, in: $0) }
        }
        if let array = value as? [Any] {
            return array.contains { containsCommand(command, in: $0) }
        }
        return false
    }

    private static func containsKeybindings(_ expected: [[String: String]], at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data),
              let bindings = root as? [[String: Any]] else {
            return false
        }

        return expected.allSatisfy { expectedBinding in
            guard let expectedCommand = expectedBinding["command"],
                  let expectedKey = expectedBinding["key"] else {
                return false
            }
            return bindings.contains { binding in
                guard let command = binding["command"] as? String,
                      let key = binding["key"] as? String else {
                    return false
                }
                return command == expectedCommand
                    && key.caseInsensitiveCompare(expectedKey) == .orderedSame
            }
        }
    }

    private static func loadJSONObject(at url: URL, defaultValue: Any) throws -> Any {
        guard FileManager.default.fileExists(atPath: url.path) else { return defaultValue }
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }

    @discardableResult
    private static func writeJSONObject(_ object: Any, to url: URL) throws -> URL? {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var backupURL: URL?
        if fileManager.fileExists(atPath: url.path) {
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let nonce = UUID().uuidString.prefix(8)
            let candidate = url.deletingPathExtension()
                .appendingPathExtension("backup-\(stamp)-\(nonce).json")
            try fileManager.copyItem(at: url, to: candidate)
            backupURL = candidate
        }

        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
        return backupURL
    }
}
