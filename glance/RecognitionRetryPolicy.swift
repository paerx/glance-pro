import Foundation

nonisolated enum RecognitionRetryPolicy {
    static let defaultCount = 3
    static let delay: Duration = .seconds(2)
    static func shouldRetry(completedRetries: Int, enabled: Bool, limit: Int) -> Bool {
        enabled && completedRetries < max(0, min(10, limit))
    }
}
