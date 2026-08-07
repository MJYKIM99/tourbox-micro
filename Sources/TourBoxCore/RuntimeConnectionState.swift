import Foundation

public struct RuntimeConnectionState: Equatable, Sendable {
    public private(set) var tourBoxStatus = "等待 TourBox"
    public private(set) var codexStateError: String?
    public private(set) var hookServerError: String?

    public init() {}

    public var displayText: String {
        codexStateError ?? hookServerError ?? tourBoxStatus
    }

    public mutating func setTourBoxStatus(_ value: String) {
        tourBoxStatus = value
    }

    public mutating func setCodexStateError(_ value: String) {
        codexStateError = value
    }

    @discardableResult
    public mutating func clearCodexStateError() -> Bool {
        guard codexStateError != nil else { return false }
        codexStateError = nil
        return true
    }

    public mutating func setHookServerError(_ value: String?) {
        hookServerError = value
    }
}
