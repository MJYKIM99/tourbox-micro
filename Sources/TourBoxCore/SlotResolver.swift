import Foundation

/// Selects six useful threads while preserving their physical button positions
/// whenever the selected set remains the same.
public struct SlotResolver: Sendable {
    private var assignedThreadIDs: [String?]

    public init(slotCount: Int = 6) {
        assignedThreadIDs = Array(repeating: nil, count: max(1, slotCount))
    }

    public mutating func resolve(
        threads: [CodexThread],
        activities: [AgentActivity],
        mode: SlotMode = .priority
    ) -> [AgentSlot] {
        let activityByThreadID = Dictionary(
            activities.compactMap { activity in
                activity.threadID.map { ($0, activity) }
            },
            uniquingKeysWith: { current, candidate in
                candidate.updatedAt > current.updatedAt ? candidate : current
            }
        )

        let candidates = mode == .pinned ? threads.filter(\.isPinned) : threads
        let ranked = candidates.sorted { lhs, rhs in
            compare(lhs, rhs, activities: activities, activityByThreadID: activityByThreadID, mode: mode)
        }
        let selected = Array(ranked.prefix(assignedThreadIDs.count))
        let selectedIDs = Set(selected.map(\.id))

        for index in assignedThreadIDs.indices where !selectedIDs.contains(assignedThreadIDs[index] ?? "") {
            assignedThreadIDs[index] = nil
        }

        let alreadyAssigned = Set(assignedThreadIDs.compactMap { $0 })
        var unassigned = selected.filter { !alreadyAssigned.contains($0.id) }
        for index in assignedThreadIDs.indices where assignedThreadIDs[index] == nil {
            if !unassigned.isEmpty {
                assignedThreadIDs[index] = unassigned.removeFirst().id
            }
        }

        let threadByID = Dictionary(uniqueKeysWithValues: selected.map { ($0.id, $0) })
        return assignedThreadIDs.enumerated().map { offset, threadID in
            guard let threadID, let thread = threadByID[threadID] else {
                return AgentSlot(index: offset + 1, thread: nil, state: .off)
            }
            let activity = bestActivity(for: thread, activities: activities, activityByThreadID: activityByThreadID)
            return AgentSlot(
                index: offset + 1,
                thread: thread,
                state: activity?.state ?? .idle,
                detail: activity?.detail
            )
        }
    }

    private func compare(
        _ lhs: CodexThread,
        _ rhs: CodexThread,
        activities: [AgentActivity],
        activityByThreadID: [String: AgentActivity],
        mode: SlotMode
    ) -> Bool {
        if mode == .priority {
            let leftState = bestActivity(for: lhs, activities: activities, activityByThreadID: activityByThreadID)?.state ?? .idle
            let rightState = bestActivity(for: rhs, activities: activities, activityByThreadID: activityByThreadID)?.state ?? .idle
            if stateRank(leftState) != stateRank(rightState) {
                return stateRank(leftState) < stateRank(rightState)
            }
        }
        return lhs.recencyAtMilliseconds > rhs.recencyAtMilliseconds
    }

    private func bestActivity(
        for thread: CodexThread,
        activities: [AgentActivity],
        activityByThreadID: [String: AgentActivity]
    ) -> AgentActivity? {
        if let exact = activityByThreadID[thread.id] {
            return exact
        }
        return activities
            .filter { $0.threadID == nil && $0.cwd == thread.cwd }
            .max { $0.updatedAt < $1.updatedAt }
    }

    private func stateRank(_ state: AgentState) -> Int {
        switch state {
        case .needsInput: 0
        case .error: 1
        case .complete: 2
        case .thinking: 3
        case .idle: 4
        case .off: 5
        }
    }
}
