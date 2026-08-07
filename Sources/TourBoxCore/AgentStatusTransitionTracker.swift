import Foundation

/// Tracks visible task state edges and selects the most important status that
/// deserves a transient HUD notification. The first snapshot only establishes
/// a baseline, preventing old completed tasks from notifying at app launch.
public struct AgentStatusTransitionTracker: Sendable {
    private var previousStates: [String: AgentState] = [:]
    private var didSeedStates = false

    public init() {}

    public mutating func notificationCandidate(in slots: [AgentSlot]) -> AgentSlot? {
        let assigned = slots.filter { $0.thread != nil }
        if !didSeedStates {
            for slot in assigned {
                if let id = slot.thread?.id { previousStates[id] = slot.state }
            }
            didSeedStates = true
            return nil
        }

        var candidates: [AgentSlot] = []
        for slot in assigned {
            guard let id = slot.thread?.id else { continue }
            let previous = previousStates[id]
            previousStates[id] = slot.state
            guard previous != slot.state else { continue }
            if Self.notifiableStates.contains(slot.state) {
                candidates.append(slot)
            }
        }
        return candidates.max {
            Self.priority($0.state) < Self.priority($1.state)
        }
    }

    public static func notificationIsCurrent(
        _ notification: AgentSlot,
        in slots: [AgentSlot]
    ) -> Bool {
        guard let threadID = notification.thread?.id,
              let current = slots.first(where: { $0.thread?.id == threadID }) else {
            return false
        }
        return current.state == notification.state && notifiableStates.contains(current.state)
    }

    private static let notifiableStates: Set<AgentState> = [
        .complete,
        .needsInput,
        .error
    ]

    private static func priority(_ state: AgentState) -> Int {
        switch state {
        case .error: 3
        case .needsInput: 2
        case .complete: 1
        default: 0
        }
    }
}
