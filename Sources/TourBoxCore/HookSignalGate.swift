import Foundation

public enum HookSignalDisposition: Equatable, Sendable {
    case deferInput(identityKey: String)
    case apply(HookSignal, cancelDeferredIdentityKey: String?)
}

/// Holds permission signals briefly so an immediately following tool-use event
/// can prove that Codex was never actually blocked on the user.
public struct HookSignalGate: Sendable {
    private struct DeferredInput: Sendable {
        let primaryKey: String
        let identityKeys: Set<String>
        let signal: HookSignal
    }

    private var deferredInputs: [String: DeferredInput] = [:]
    private var primaryKeyByIdentity: [String: String] = [:]

    public init() {}

    public mutating func receive(_ signal: HookSignal) -> HookSignalDisposition {
        let identityKeys = Self.identityKeys(for: signal)
        guard let identityKey = identityKeys.first else {
            return .apply(signal, cancelDeferredIdentityKey: nil)
        }

        if signal.state == .needsInput {
            if let replacedKey = identityKeys.compactMap({ primaryKeyByIdentity[$0] }).first {
                removeDeferredInput(for: replacedKey)
            }
            let deferred = DeferredInput(
                primaryKey: identityKey,
                identityKeys: Set(identityKeys),
                signal: signal
            )
            deferredInputs[identityKey] = deferred
            for key in identityKeys { primaryKeyByIdentity[key] = identityKey }
            return .deferInput(identityKey: identityKey)
        }

        let canceledIdentityKey = identityKeys
            .compactMap { primaryKeyByIdentity[$0] }
            .first
        if let canceledIdentityKey { removeDeferredInput(for: canceledIdentityKey) }
        return .apply(signal, cancelDeferredIdentityKey: canceledIdentityKey)
    }

    public mutating func flushDeferredInput(for identityKey: String) -> HookSignal? {
        guard let deferred = deferredInputs[identityKey] else { return nil }
        removeDeferredInput(for: identityKey)
        return deferred.signal
    }

    public mutating func removeAll() {
        deferredInputs.removeAll()
        primaryKeyByIdentity.removeAll()
    }

    private mutating func removeDeferredInput(for primaryKey: String) {
        guard let deferred = deferredInputs.removeValue(forKey: primaryKey) else { return }
        for key in deferred.identityKeys where primaryKeyByIdentity[key] == primaryKey {
            primaryKeyByIdentity.removeValue(forKey: key)
        }
    }

    private static func identityKeys(for signal: HookSignal) -> [String] {
        var keys: [String] = []
        if let threadID = signal.threadID, !threadID.isEmpty { keys.append("thread:\(threadID)") }
        if let cwd = signal.cwd, !cwd.isEmpty { keys.append("cwd:\(cwd)") }
        return keys
    }
}
