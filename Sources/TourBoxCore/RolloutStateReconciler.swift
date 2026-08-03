import Foundation

public struct RolloutLifecycleSnapshot: Equatable, Sendable {
    public let threadID: String
    public let cwd: String
    public let state: AgentState
    public let updatedAt: Date

    public init(threadID: String, cwd: String, state: AgentState, updatedAt: Date) {
        self.threadID = threadID
        self.cwd = cwd
        self.state = state
        self.updatedAt = updatedAt
    }
}

public struct RolloutPresentationSnapshot: Equatable, Sendable {
    public let threadID: String
    public let latestMessage: String
    public let updatedAt: Date

    public init(threadID: String, latestMessage: String, updatedAt: Date) {
        self.threadID = threadID
        self.latestMessage = latestMessage
        self.updatedAt = updatedAt
    }
}

/// Reads the most recent user-visible assistant update from a rollout tail.
/// Internal reasoning, user input and the original task title are deliberately ignored.
public struct RolloutPresentationReader: Sendable {
    public let maximumThreads: Int
    public let maximumBytesPerRollout: UInt64

    public init(maximumThreads: Int = 120, maximumBytesPerRollout: UInt64 = 524_288) {
        self.maximumThreads = min(max(maximumThreads, 1), 500)
        self.maximumBytesPerRollout = min(max(maximumBytesPerRollout, 65_536), 2_097_152)
    }

    public func snapshot(for thread: CodexThread) -> RolloutPresentationSnapshot? {
        guard let rolloutPath = thread.rolloutPath, !rolloutPath.isEmpty else { return nil }
        let url = URL(fileURLWithPath: rolloutPath)
        guard let data = try? tailData(from: url), !data.isEmpty else { return nil }

        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        if data.first != 0x7B, !lines.isEmpty { lines.removeFirst() }
        let fallbackDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? Date()
        var latestTaskStart: Date?
        var latestAssistantMessage: (text: String, date: Date)?

        for line in lines.reversed() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let payload = object["payload"] as? [String: Any] else { continue }
            let date = timestamp(from: object) ?? fallbackDate

            if object["type"] as? String == "event_msg" {
                switch payload["type"] as? String {
                case "task_started":
                    if latestTaskStart == nil { latestTaskStart = date }
                case "task_complete":
                    if latestAssistantMessage == nil,
                       let text = payload["last_agent_message"] as? String {
                        latestAssistantMessage = (text, date)
                    }
                case "agent_message":
                    if latestAssistantMessage == nil,
                       let text = payload["message"] as? String {
                        latestAssistantMessage = (text, date)
                    }
                default:
                    break
                }
            } else if object["type"] as? String == "response_item",
                      payload["type"] as? String == "message",
                      payload["role"] as? String == "assistant",
                      latestAssistantMessage == nil,
                      let content = payload["content"] as? [[String: Any]] {
                let text = content.compactMap { item -> String? in
                    guard item["type"] as? String == "output_text" else { return nil }
                    return item["text"] as? String
                }.joined(separator: "\n")
                if !text.isEmpty { latestAssistantMessage = (text, date) }
            }

            if latestTaskStart != nil, latestAssistantMessage != nil { break }
        }

        if let taskStart = latestTaskStart,
           latestAssistantMessage.map({ $0.date < taskStart }) ?? true {
            return RolloutPresentationSnapshot(
                threadID: thread.id,
                latestMessage: "正在处理，等待新的进展…",
                updatedAt: taskStart
            )
        }
        guard let assistantMessage = latestAssistantMessage,
              let concise = conciseLastSentence(from: assistantMessage.text) else { return nil }
        return RolloutPresentationSnapshot(
            threadID: thread.id,
            latestMessage: concise,
            updatedAt: assistantMessage.date
        )
    }

    private func conciseLastSentence(from value: String) -> String? {
        var text = value
        text = text.replacingOccurrences(
            of: #"<codex_delegation>[\s\S]*?</codex_delegation>"#,
            with: " ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: #"!\[[^\]]*\]\([^\)]*\)"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]*\)"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[`*_>#]"#, with: "", options: .regularExpression)

        let lines = text.components(separatedBy: .newlines)
            .map { line in
                line.replacingOccurrences(
                    of: #"^\s*(?:[-+•]|\d+[.)])\s*"#,
                    with: "",
                    options: .regularExpression
                ).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        guard var candidate = lines.last else { return nil }

        let endings = CharacterSet(charactersIn: "。！？!?")
        let sentences = candidate.components(separatedBy: endings)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let last = sentences.last { candidate = last }
        candidate = candidate.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard !candidate.isEmpty else { return nil }
        if candidate.count > 180 {
            return String(candidate.prefix(179)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        return candidate
    }

    private func tailData(from url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        let byteCount = min(size, maximumBytesPerRollout)
        try handle.seek(toOffset: size - byteCount)
        return try handle.read(upToCount: Int(byteCount)) ?? Data()
    }

    private func timestamp(from object: [String: Any]) -> Date? {
        if let milliseconds = object["timestamp_ms"] as? NSNumber {
            return Date(timeIntervalSince1970: milliseconds.doubleValue / 1_000)
        }
        guard let rawValue = object["timestamp"] as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: rawValue) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: rawValue)
    }
}

/// Recovers the last start/complete lifecycle edge from recent rollout files.
/// Only a bounded tail is read, so startup work stays proportional and no chat
/// content is retained by TourBox Micro.
public struct RolloutStateReconciler: Sendable {
    public let maximumThreads: Int
    public let maximumBytesPerRollout: UInt64
    public let maximumRecoverableActiveAge: TimeInterval

    public init(
        maximumThreads: Int = 120,
        maximumBytesPerRollout: UInt64 = 2_097_152,
        maximumRecoverableActiveAge: TimeInterval = 86_400
    ) {
        self.maximumThreads = min(max(maximumThreads, 1), 500)
        self.maximumBytesPerRollout = min(max(maximumBytesPerRollout, 65_536), 8_388_608)
        self.maximumRecoverableActiveAge = max(maximumRecoverableActiveAge, 60)
    }

    public func snapshots(for threads: [CodexThread]) -> [RolloutLifecycleSnapshot] {
        threads.prefix(maximumThreads).compactMap(snapshot)
    }

    public func snapshot(for thread: CodexThread) -> RolloutLifecycleSnapshot? {
        guard let rolloutPath = thread.rolloutPath, !rolloutPath.isEmpty else { return nil }
        let url = URL(fileURLWithPath: rolloutPath)
        guard let data = try? tailData(from: url), !data.isEmpty else { return nil }

        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        if data.first != 0x7B, !lines.isEmpty {
            // The bounded read may begin halfway through a JSON line.
            lines.removeFirst()
        }

        let fallbackDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? Date()
        for line in lines.reversed() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  object["type"] as? String == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  let eventType = payload["type"] as? String else { continue }

            let state: AgentState
            switch eventType {
            case "task_started": state = .thinking
            case "task_complete": state = .complete
            default: continue
            }
            let lifecycleDate = timestamp(from: object) ?? fallbackDate
            let eventDate = state == .thinking
                ? max(lifecycleDate, fallbackDate)
                : lifecycleDate
            if state == .thinking,
               Date().timeIntervalSince(eventDate) > maximumRecoverableActiveAge {
                return nil
            }
            return RolloutLifecycleSnapshot(
                threadID: thread.id,
                cwd: thread.cwd,
                state: state,
                updatedAt: eventDate
            )
        }
        return nil
    }

    private func tailData(from url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        let byteCount = min(size, maximumBytesPerRollout)
        try handle.seek(toOffset: size - byteCount)
        return try handle.read(upToCount: Int(byteCount)) ?? Data()
    }

    private func timestamp(from object: [String: Any]) -> Date? {
        if let milliseconds = object["timestamp_ms"] as? NSNumber {
            return Date(timeIntervalSince1970: milliseconds.doubleValue / 1_000)
        }
        guard let rawValue = object["timestamp"] as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: rawValue) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: rawValue)
    }
}

public final class RolloutActivityMonitor: @unchecked Sendable {
    private struct Fingerprint: Equatable {
        let modificationDate: Date?
        let fileSize: Int?
    }

    private let reconciler: RolloutStateReconciler
    private var fingerprints: [String: Fingerprint] = [:]
    private let lock = NSLock()

    public init(reconciler: RolloutStateReconciler = .init()) {
        self.reconciler = reconciler
    }

    public func changedSnapshots(
        for threads: [CodexThread],
        force: Bool = false
    ) -> [RolloutLifecycleSnapshot] {
        lock.lock()
        defer { lock.unlock() }

        var changed: [CodexThread] = []
        for thread in threads.prefix(reconciler.maximumThreads) {
            guard let path = thread.rolloutPath, !path.isEmpty else { continue }
            let url = URL(fileURLWithPath: path)
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let fingerprint = Fingerprint(
                modificationDate: values?.contentModificationDate,
                fileSize: values?.fileSize
            )
            if force || fingerprints[path] != fingerprint {
                fingerprints[path] = fingerprint
                changed.append(thread)
            }
        }
        return changed.compactMap(reconciler.snapshot)
    }
}

public final class RolloutPresentationMonitor: @unchecked Sendable {
    private struct Fingerprint: Equatable {
        let modificationDate: Date?
        let fileSize: Int?
    }

    private let reader: RolloutPresentationReader
    private var fingerprints: [String: Fingerprint] = [:]
    private let lock = NSLock()

    public init(reader: RolloutPresentationReader = .init()) {
        self.reader = reader
    }

    public func changedSnapshots(
        for threads: [CodexThread],
        force: Bool = false
    ) -> [RolloutPresentationSnapshot] {
        lock.lock()
        defer { lock.unlock() }

        var changed: [CodexThread] = []
        for thread in threads.prefix(reader.maximumThreads) {
            guard let path = thread.rolloutPath, !path.isEmpty else { continue }
            let url = URL(fileURLWithPath: path)
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let fingerprint = Fingerprint(
                modificationDate: values?.contentModificationDate,
                fileSize: values?.fileSize
            )
            if force || fingerprints[path] != fingerprint {
                fingerprints[path] = fingerprint
                changed.append(thread)
            }
        }
        return changed.compactMap(reader.snapshot)
    }
}
