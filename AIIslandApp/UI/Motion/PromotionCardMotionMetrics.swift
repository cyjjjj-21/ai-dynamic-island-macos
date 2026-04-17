import CoreGraphics

enum PromotionCardMotionMetrics {
    private static let revealStart: CGFloat = 0.34
    private static let opaqueThreshold: CGFloat = 0.40

    static func cardOpacity(for progress: CGFloat) -> CGFloat {
        let normalized = (progress - revealStart) / (opaqueThreshold - revealStart)
        return clamp(normalized)
    }

    static func cardOffset(for opacity: CGFloat) -> CGFloat {
        (1 - clamp(opacity)) * -10
    }

    private static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}
