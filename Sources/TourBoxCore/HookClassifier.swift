import Foundation

public enum CodexHookEvent: String, CaseIterable, Sendable {
    case userPromptSubmit = "UserPromptSubmit"
    case permissionRequest = "PermissionRequest"
    case postToolUse = "PostToolUse"
    case stop = "Stop"
}

public struct HookSignal: Equatable, Sendable {
    public let threadID: String?
    public let cwd: String?
    public let state: AgentState
    public let detail: String?

    public init(threadID: String?, cwd: String?, state: AgentState, detail: String?) {
        self.threadID = threadID
        self.cwd = cwd
        self.state = state
        self.detail = detail
    }
}

public enum HookClassifier {
    public static func classify(event: CodexHookEvent, payload: [String: Any]) -> HookSignal {
        let threadID = firstString(in: payload, keys: ["thread_id", "threadId", "session_id", "sessionId"])
        let cwd = firstString(in: payload, keys: ["cwd", "working_directory", "workingDirectory"])
        let state: AgentState

        switch event {
        case .userPromptSubmit, .postToolUse:
            state = .thinking
        case .permissionRequest:
            state = .needsInput
        case .stop:
            state = containsFailure(payload) ? .error : .complete
        }

        let detail = firstString(
            in: payload,
            keys: ["message", "reason", "error", "tool_name", "toolName", "notification_type"]
        )
        return HookSignal(threadID: threadID, cwd: cwd, state: state, detail: detail)
    }

    private static func firstString(in payload: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = payload[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func containsFailure(_ value: Any) -> Bool {
        if value is Bool { return false }
        if let string = value as? String {
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ["error", "failed", "failure", "cancelled", "canceled"].contains(normalized)
                || normalized.hasPrefix("error:")
                || normalized.hasPrefix("failed:")
        }
        if let dictionary = value as? [String: Any] {
            if dictionary["is_error"] as? Bool == true || dictionary["isError"] as? Bool == true {
                return true
            }
            if dictionary["success"] as? Bool == false { return true }
            for key in ["status", "outcome", "result_status", "resultStatus"] {
                if let candidate = dictionary[key], containsFailure(candidate) { return true }
            }
            if let explicitError = dictionary["error"], !(explicitError is NSNull) {
                if let text = explicitError as? String { return !text.isEmpty }
                return true
            }
            return dictionary.values.contains { candidate in
                guard candidate is [String: Any] || candidate is [Any] else { return false }
                return containsFailure(candidate)
            }
        }
        if let array = value as? [Any] {
            return array.contains(where: containsFailure)
        }
        return false
    }
}
