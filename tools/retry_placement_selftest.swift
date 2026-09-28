import Foundation
import CoreGraphics
@main struct RetryPlacementTests {
    static func main() {
        var count = 0
        while RecognitionRetryPolicy.shouldRetry(completedRetries: count, enabled: true, limit: RecognitionRetryPolicy.defaultCount) { count += 1 }
        precondition(count == 3)
        precondition(RecognitionRetryPolicy.delay == .seconds(2))
        precondition(!RecognitionRetryPolicy.shouldRetry(completedRetries: 0, enabled: false, limit: 3))
        precondition(!RecognitionRetryPolicy.shouldRetry(completedRetries: 0, enabled: true, limit: -1))
        precondition(!RecognitionRetryPolicy.shouldRetry(completedRetries: 10, enabled: true, limit: 100))
        precondition(RecognitionRetryPolicy.shouldRetry(completedRetries: 0, enabled: true, limit: 3))
        for screen in [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1920, y: -600, width: 1920, height: 1080), CGRect(x: 0, y: 900, width: 1280, height: 720)] {
            for window in [CGSize(width: 838, height: 801), CGSize(width: 360, height: 250)] {
                let origin = OverlayPlacement.origin(screen: screen, window: window)
                precondition(origin.y + window.height == screen.maxY)
                precondition(origin.x + window.width / 2 == screen.midX)
            }
        }
        let expected = CGRect(x: 300, y: 100, width: 838, height: 801)
        precondition(!OverlayPlacement.needsCorrection(actual: expected, expected: expected))
        precondition(OverlayPlacement.needsCorrection(actual: expected.offsetBy(dx: 0, dy: -38), expected: expected))
        precondition(OverlayPlacement.needsCorrection(actual: CGRect(x: 300, y: 100, width: 838, height: 763), expected: expected))
        precondition(!OverlayPlacement.needsCorrection(actual: expected.offsetBy(dx: 0.1, dy: 0.1), expected: expected))
        print("PASS: retry budget/delay and top-edge placement across 3 display layouts (22 assertions)")
    }
}
