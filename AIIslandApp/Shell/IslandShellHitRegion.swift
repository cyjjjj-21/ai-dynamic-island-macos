import AppKit

struct IslandShellHitRegion {
    let shellSize: CGSize
    let notchAvoidanceWidth: CGFloat
    let notchAvoidanceHeight: CGFloat

    func containsInteractivePoint(_ point: CGPoint) -> Bool {
        let shellBounds = CGRect(origin: .zero, size: shellSize)
        guard shellBounds.contains(point) else {
            return false
        }

        let outerPath = CGPath(
            roundedRect: shellBounds,
            cornerWidth: shellBounds.height / 2,
            cornerHeight: shellBounds.height / 2,
            transform: nil
        )
        let cutoutRect = CGRect(
            x: shellBounds.midX - (notchAvoidanceWidth / 2),
            y: shellBounds.minY,
            width: notchAvoidanceWidth,
            height: min(shellBounds.height, notchAvoidanceHeight)
        )
        let cutoutPath = PhysicalNotchCutoutGeometry.makePath(in: cutoutRect)

        return outerPath.contains(point) && !cutoutPath.contains(point)
    }
}
