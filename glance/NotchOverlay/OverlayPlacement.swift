import CoreGraphics

nonisolated enum OverlayPlacement {
    static func needsCorrection(actual: CGRect, expected: CGRect) -> Bool {
        abs(actual.minX - expected.minX) > 0.5 || abs(actual.minY - expected.minY) > 0.5
            || abs(actual.width - expected.width) > 0.5 || abs(actual.height - expected.height) > 0.5
    }

    static func origin(screen: CGRect, window: CGSize) -> CGPoint {
        CGPoint(x: screen.midX - window.width / 2, y: screen.maxY - window.height)
    }
}
