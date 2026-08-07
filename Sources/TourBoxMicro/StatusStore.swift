import Foundation
import TourBoxCore

@MainActor
final class StatusStore {
    private(set) var activities: [AgentActivity]
    private(set) var persistenceAvailable: Bool
    private(set) var persistenceDetail: String

    private let repository: ActivityRepository?

    init(repository: ActivityRepository? = nil) {
        if let repository {
            self.repository = repository
            activities = (try? repository.loadActivities()) ?? []
            persistenceAvailable = true
            persistenceDetail = "SQLite WAL 已启用"
            return
        }

        do {
            let url = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
                .appendingPathComponent("TourBox Micro", isDirectory: true)
                .appendingPathComponent("status.sqlite3")
            let openedRepository = try ActivityRepository(databaseURL: url)
            _ = try openedRepository.expireStaleActiveStates(
                before: Date().addingTimeInterval(-86_400)
            )
            let restoredActivities = try openedRepository.loadActivities()
            self.repository = openedRepository
            activities = restoredActivities
            persistenceAvailable = true
            persistenceDetail = "SQLite WAL · \(activities.count) 条状态"
        } catch {
            self.repository = nil
            activities = []
            persistenceAvailable = false
            persistenceDetail = error.localizedDescription
        }
    }

    func apply(_ signal: HookSignal) {
        apply(
            AgentActivity(
                threadID: signal.threadID,
                cwd: signal.cwd,
                state: signal.state,
                updatedAt: Date(),
                detail: signal.detail
            ),
            persist: true
        )
    }

    func reconcile(_ snapshots: [RolloutLifecycleSnapshot]) {
        for snapshot in snapshots {
            let current = bestActivity(threadID: snapshot.threadID, cwd: snapshot.cwd)
            if let current, snapshot.updatedAt < current.updatedAt { continue }

            switch snapshot.state {
            case .thinking:
                apply(
                    AgentActivity(
                        threadID: snapshot.threadID,
                        cwd: snapshot.cwd,
                        state: .thinking,
                        updatedAt: snapshot.updatedAt,
                        detail: "从任务记录恢复"
                    ),
                    persist: true
                )
            case .complete:
                // Historical completed chats must not all become unread. A
                // completion snapshot closes only a task we were tracking as
                // active or waiting when TourBox Micro went offline.
                guard let current, current.state == .thinking || current.state == .needsInput else {
                    continue
                }
                apply(
                    AgentActivity(
                        threadID: snapshot.threadID,
                        cwd: snapshot.cwd,
                        state: .complete,
                        updatedAt: snapshot.updatedAt,
                        detail: "离线期间已完成"
                    ),
                    persist: true
                )
            default:
                continue
            }
        }
    }

    func acknowledge(_ thread: CodexThread) {
        let acknowledgedAt = Date()
        var changed = false
        activities = activities.map { activity in
            guard matches(activity, thread: thread), activity.state == .complete else {
                return activity
            }
            changed = true
            return AgentActivity(
                threadID: activity.threadID ?? thread.id,
                cwd: activity.cwd ?? thread.cwd,
                state: .idle,
                updatedAt: acknowledgedAt,
                detail: nil
            )
        }
        guard changed else { return }
        sortAndTrim()
        do {
            try repository?.acknowledgeCompletion(for: thread, at: acknowledgedAt)
            persistenceDetail = "SQLite WAL · \(activities.count) 条状态"
        } catch {
            persistenceAvailable = false
            persistenceDetail = error.localizedDescription
        }
    }

    private func apply(_ activity: AgentActivity, persist: Bool) {
        guard activity.threadID != nil || activity.cwd != nil else { return }
        if let current = bestActivity(threadID: activity.threadID, cwd: activity.cwd),
           current.updatedAt > activity.updatedAt {
            return
        }

        activities.removeAll { existing in
            if let threadID = activity.threadID {
                if existing.threadID == threadID { return true }
                if existing.threadID == nil, let cwd = activity.cwd, existing.cwd == cwd { return true }
                return false
            }
            return existing.threadID == nil && existing.cwd == activity.cwd
        }
        activities.append(activity)
        sortAndTrim()

        guard persist else { return }
        do {
            _ = try repository?.upsert(activity)
            persistenceAvailable = repository != nil
            persistenceDetail = repository == nil
                ? "SQLite 不可用，使用内存状态"
                : "SQLite WAL · \(activities.count) 条状态"
        } catch {
            persistenceAvailable = false
            persistenceDetail = error.localizedDescription
        }
    }

    private func bestActivity(threadID: String?, cwd: String?) -> AgentActivity? {
        if let threadID,
           let exact = activities.first(where: { $0.threadID == threadID }) {
            return exact
        }
        guard let cwd else { return nil }
        return activities
            .filter { $0.threadID == nil && $0.cwd == cwd }
            .max { $0.updatedAt < $1.updatedAt }
    }

    private func matches(_ activity: AgentActivity, thread: CodexThread) -> Bool {
        activity.threadID == thread.id || (activity.threadID == nil && activity.cwd == thread.cwd)
    }

    private func sortAndTrim() {
        activities = Array(activities.sorted { $0.updatedAt > $1.updatedAt }.prefix(500))
    }
}
