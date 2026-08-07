import Foundation

/// Preserves fast thread discovery when lifecycle hooks are unavailable while
/// allowing a quieter fallback cadence when hooks are actively delivering
/// state changes.
public struct ThreadRefreshCadencePolicy: Equatable, Sendable {
    public let unhookedInterval: TimeInterval
    public let hookedInterval: TimeInterval
    public let hookFreshness: TimeInterval

    public init(
        unhookedInterval: TimeInterval = 5,
        hookedInterval: TimeInterval = 15,
        hookFreshness: TimeInterval = 60
    ) {
        self.unhookedInterval = max(unhookedInterval, 1)
        self.hookedInterval = max(hookedInterval, self.unhookedInterval)
        self.hookFreshness = max(hookFreshness, self.hookedInterval)
    }

    public func interval(lastHookSignalAt: Date?, now: Date) -> TimeInterval {
        guard let lastHookSignalAt,
              now.timeIntervalSince(lastHookSignalAt) <= hookFreshness else {
            return unhookedInterval
        }
        return hookedInterval
    }

    public func refreshIsDue(
        lastRefreshAt: Date?,
        lastHookSignalAt: Date?,
        now: Date
    ) -> Bool {
        guard let lastRefreshAt else { return true }
        return now.timeIntervalSince(lastRefreshAt) >= interval(
            lastHookSignalAt: lastHookSignalAt,
            now: now
        )
    }
}
