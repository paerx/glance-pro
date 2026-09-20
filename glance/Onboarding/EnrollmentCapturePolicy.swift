import Foundation
import CoreGraphics

/// Pure capture rules, independent of camera, UI and model latency.
nonisolated enum EnrollmentCapturePolicy {
    static let minimumInterval: TimeInterval = 0.12
    static let candidatesPerDirection = 4
    static let samplesPerDirection = 2

    static func pose(yaw: Float, pitch: Float) -> EnrollmentPose? {
        guard yaw.isFinite, pitch.isFinite, abs(yaw) < 0.9, abs(pitch) < 0.7 else { return nil }
        if abs(yaw) < 0.16, abs(pitch) < 0.13 { return .center }
        let x = Double(-yaw / 0.25), y = Double(-pitch / 0.20)
        guard hypot(x, y) >= 0.9 else { return nil }
        let degrees = (atan2(x, y) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        let sectors: [EnrollmentPose] = [.top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left, .topLeft]
        return sectors[Int((degrees / 45).rounded()) % 8]
    }

    static func isContinuous(_ box: CGRect, with previous: CGRect) -> Bool {
        let distance = hypot(box.midX - previous.midX, box.midY - previous.midY)
        let ratio = box.width / max(previous.width, 0.001)
        return distance < 0.22 && (0.55...1.8).contains(ratio)
    }

    static func requiredSamples(for pose: EnrollmentPose) -> Int { pose == .center ? 1 : samplesPerDirection }
}
