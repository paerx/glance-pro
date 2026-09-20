import Foundation

/// Coverage bins for a continuous head turn; center provides an automatically selected reference frame.
nonisolated enum EnrollmentPose: Int, CaseIterable, Sendable {
    case center, left, topLeft, top, topRight, right, bottomRight, bottom, bottomLeft

    enum YawBand { case left, none, right }
    enum PitchBand { case up, none, down }

    var yawBand: YawBand {
        switch self {
        case .left, .topLeft, .bottomLeft: return .left
        case .right, .topRight, .bottomRight: return .right
        case .center, .top, .bottom: return .none
        }
    }

    var pitchBand: PitchBand {
        switch self {
        case .top, .topLeft, .topRight: return .up
        case .bottom, .bottomLeft, .bottomRight: return .down
        case .center, .left, .right: return .none
        }
    }

    /// Compass angle (0 = up, clockwise) this pose's ring sector is centered
    /// on. `nil` for center, which pulses the whole ring instead of
    /// claiming a sector.
    var compassAngle: Double? {
        switch self {
        case .center: return nil
        case .left: return 270
        case .topLeft: return 315
        case .top: return 0
        case .topRight: return 45
        case .right: return 90
        case .bottomRight: return 135
        case .bottom: return 180
        case .bottomLeft: return 225
        }
    }

    var instruction: String {
        switch self {
        case .center: return "Look straight at the camera"
        case .left: return "Turn your head slightly left"
        case .topLeft: return "Turn your head to the top left"
        case .top: return "Turn your head slightly up"
        case .topRight: return "Turn your head to the top right"
        case .right: return "Turn your head slightly right"
        case .bottomRight: return "Turn your head to the bottom right"
        case .bottom: return "Turn your head slightly down"
        case .bottomLeft: return "Turn your head to the bottom left"
        }
    }

    /// Relaxes this pose's yaw/pitch bands — same knob as `stallWidenFactor`, so >1 is easier.
    var matchLeniency: Float {
        switch self {
        case .bottomLeft, .bottomRight: return 1.5
        case .bottom: return 1.2
        default: return 1
        }
    }

    /// Persisted alongside each sample so a saved identity records which
    /// pose each embedding came from.
    var name: String {
        switch self {
        case .center: return "center"
        case .left: return "left"
        case .topLeft: return "top_left"
        case .top: return "top"
        case .topRight: return "top_right"
        case .right: return "right"
        case .bottomRight: return "bottom_right"
        case .bottom: return "bottom"
        case .bottomLeft: return "bottom_left"
        }
    }
}

