import Foundation
@main struct WakePolicySelfTest {
    static func main() {
        var policy = WakeTriggerPolicy()
        precondition(policy.receive(.wake))
        precondition(policy.receive(.screenLocked))
        precondition(policy.consume() == .wake) // Lock lag cannot drop wake.
        precondition(policy.consume() == nil) // Consumed only once.
        precondition(policy.receive(.screenLocked))
        precondition(policy.consume() == .screenLocked)
        precondition(policy.receive(.wake))
        precondition(policy.receive(.wake))
        precondition(policy.consume() == .wake) // Duplicate wake coalesces.
        precondition(policy.receive(.wake))
        precondition(!policy.receive(.willSleep))
        precondition(policy.consume() == nil)
        precondition(policy.receive(.wake))
        precondition(!policy.receive(.screenUnlocked))
        precondition(policy.consume() == nil)
        precondition(WakeTriggerPolicy.settleAttempts == 12)
        precondition(WakeTriggerPolicy.settleInterval == .milliseconds(250))
        print("PASS: 17 wake-policy checks; no screen lock or camera access")
    }
}
