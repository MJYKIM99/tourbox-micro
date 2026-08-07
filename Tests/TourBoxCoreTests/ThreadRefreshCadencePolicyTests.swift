import Foundation
import Testing
@testable import TourBoxCore

@Test func refreshCadencePreservesFiveSecondDiscoveryWithoutHooks() {
    let policy = ThreadRefreshCadencePolicy()
    let lastRefresh = Date(timeIntervalSince1970: 1_800_000_000)

    #expect(!policy.refreshIsDue(
        lastRefreshAt: lastRefresh,
        lastHookSignalAt: nil,
        now: lastRefresh.addingTimeInterval(4.9)
    ))
    #expect(policy.refreshIsDue(
        lastRefreshAt: lastRefresh,
        lastHookSignalAt: nil,
        now: lastRefresh.addingTimeInterval(5)
    ))
}

@Test func refreshCadenceUsesFifteenSecondFallbackWhileHooksAreHealthy() {
    let policy = ThreadRefreshCadencePolicy()
    let lastRefresh = Date(timeIntervalSince1970: 1_800_000_000)
    let recentHook = lastRefresh.addingTimeInterval(2)

    #expect(!policy.refreshIsDue(
        lastRefreshAt: lastRefresh,
        lastHookSignalAt: recentHook,
        now: lastRefresh.addingTimeInterval(14.9)
    ))
    #expect(policy.refreshIsDue(
        lastRefreshAt: lastRefresh,
        lastHookSignalAt: recentHook,
        now: lastRefresh.addingTimeInterval(15)
    ))
}

@Test func refreshCadenceFallsBackToFastDiscoveryAfterHooksGoStale() {
    let policy = ThreadRefreshCadencePolicy()
    let lastRefresh = Date(timeIntervalSince1970: 1_800_000_000)
    let oldHook = lastRefresh.addingTimeInterval(-61)

    #expect(policy.refreshIsDue(
        lastRefreshAt: lastRefresh,
        lastHookSignalAt: oldHook,
        now: lastRefresh.addingTimeInterval(5)
    ))
    #expect(policy.refreshIsDue(
        lastRefreshAt: nil,
        lastHookSignalAt: nil,
        now: lastRefresh
    ))
}
