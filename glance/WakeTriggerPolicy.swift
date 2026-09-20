import Foundation

nonisolated enum LockEventKind {
    case screenLocked, screenUnlocked, willSleep, wake
}

/// A lock notification arriving just after wake must not replace the user's
/// wake trigger. Unlock/sleep explicitly cancel the pending attempt.
nonisolated struct WakeTriggerPolicy {
    static let settleAttempts = 12
    static let settleInterval: Duration = .milliseconds(250)
    private(set) var pending: LockEventKind?

    mutating func receive(_ event: LockEventKind?) -> Bool {
        switch event {
        case .wake: pending = .wake
        case .screenLocked: if pending != .wake { pending = .screenLocked }
        case .screenUnlocked, .willSleep, nil: pending = nil
        }
        return pending != nil
    }

    mutating func consume() -> LockEventKind? {
        defer { pending = nil }
        return pending
    }
}
