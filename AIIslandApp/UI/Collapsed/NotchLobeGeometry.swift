import CoreGraphics

enum NotchLobeSide {
    case left
    case right
}

enum NotchLobeGeometry {
    private static let quarterCurveKappa: CGFloat = 0.5522847498

    static func makePath(
        side: NotchLobeSide,
        in rect: CGRect,
        overlap: CGFloat,
        shoulderY: CGFloat
    ) -> CGPath {
        let radius = rect.height / 2
        let clampedOverlap = max(0, min(overlap, rect.width))
        let innerTopX = side == .left ? rect.maxX - clampedOverlap : rect.minX + clampedOverlap
        let shoulder = max(rect.minY, min(rect.maxY, rect.minY + shoulderY))
        let curveWidth = abs(rect.maxX - innerTopX)
        let curveHeight = max(0, rect.maxY - shoulder)
        let curveControlX = curveWidth * quarterCurveKappa
        let curveControlY = curveHeight * quarterCurveKappa

        let path = CGMutablePath()

        switch side {
        case .left:
            path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addLine(to: CGPoint(x: innerTopX, y: rect.minY))
            path.addLine(to: CGPoint(x: innerTopX, y: shoulder))
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                control1: CGPoint(x: innerTopX, y: shoulder + curveControlY),
                control2: CGPoint(x: rect.maxX - curveControlX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            path.addArc(
                center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
                radius: radius,
                startAngle: .pi / 2,
                endAngle: .pi,
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addArc(
                center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
                radius: radius,
                startAngle: .pi,
                endAngle: .pi * 1.5,
                clockwise: false
            )
        case .right:
            path.move(to: CGPoint(x: innerTopX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addArc(
                center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                radius: radius,
                startAngle: .pi * 1.5,
                endAngle: 0,
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addArc(
                center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
                radius: radius,
                startAngle: 0,
                endAngle: .pi / 2,
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addCurve(
                to: CGPoint(x: innerTopX, y: shoulder),
                control1: CGPoint(x: rect.minX + curveControlX, y: rect.maxY),
                control2: CGPoint(x: innerTopX, y: shoulder + curveControlY)
            )
            path.addLine(to: CGPoint(x: innerTopX, y: rect.minY))
        }

        path.closeSubpath()
        return path
    }
}
