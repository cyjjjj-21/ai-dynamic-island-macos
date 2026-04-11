import CoreGraphics
import SwiftUI

enum PhysicalNotchCutoutGeometry {
    static let referenceTopWidth: CGFloat = 193.549
    static let referenceDepth: CGFloat = 32.500

    static func makePath(in rect: CGRect) -> CGPath {
        let scaleX = rect.width / referenceTopWidth
        let scaleY = rect.height / referenceDepth

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: rect.minX + (x * scaleX),
                y: rect.minY + (y * scaleY)
            )
        }

        let path = CGMutablePath()
        path.move(to: point(0.000, 0.000))
        path.addLine(to: point(193.549, 0.000))
        path.addCurve(
            to: point(190.712, 1.740),
            control1: point(192.443, 0.255),
            control2: point(191.430, 0.874)
        )
        path.addCurve(
            to: point(189.622, 4.158),
            control1: point(190.141, 2.430),
            control2: point(189.762, 3.272)
        )
        path.addCurve(
            to: point(189.563, 4.932),
            control1: point(189.583, 4.413),
            control2: point(189.563, 4.676)
        )
        path.addCurve(
            to: point(189.563, 22.476),
            control1: point(189.563, 4.932),
            control2: point(189.563, 22.476)
        )
        path.addCurve(
            to: point(189.551, 22.923),
            control1: point(189.555, 22.616),
            control2: point(189.567, 22.784)
        )
        path.addCurve(
            to: point(184.028, 31.438),
            control1: point(189.415, 26.498),
            control2: point(187.236, 29.862)
        )
        path.addCurve(
            to: point(179.982, 32.492),
            control1: point(182.775, 32.069),
            control2: point(181.383, 32.428)
        )
        path.addCurve(
            to: point(13.985, 32.500),
            control1: point(179.787, 32.603),
            control2: point(14.301, 32.432)
        )
        path.addCurve(
            to: point(13.307, 32.468),
            control1: point(13.770, 32.496),
            control2: point(13.527, 32.488)
        )
        path.addCurve(
            to: point(9.265, 31.259),
            control1: point(11.895, 32.356),
            control2: point(10.506, 31.941)
        )
        path.addCurve(
            to: point(4.214, 24.180),
            control1: point(6.624, 29.826),
            control2: point(4.708, 27.145)
        )
        path.addCurve(
            to: point(3.978, 3.978),
            control1: point(3.823, 22.648),
            control2: point(4.277, 5.694)
        )
        path.addCurve(
            to: point(2.506, 1.289),
            control1: point(3.783, 2.957),
            control2: point(3.260, 2.003)
        )
        path.addCurve(
            to: point(0.000, 0.000),
            control1: point(1.816, 0.634),
            control2: point(0.934, 0.180)
        )
        path.closeSubpath()
        return path
    }
}

struct PhysicalNotchCutoutShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(PhysicalNotchCutoutGeometry.makePath(in: rect))
    }
}

struct ShellBandShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(
            roundedRect: rect,
            cornerRadius: rect.height / 2,
            style: .continuous
        )
        let cutoutRect = CGRect(
            x: rect.midX - (IslandPalette.physicalNotchWidth / 2),
            y: rect.minY,
            width: IslandPalette.physicalNotchWidth,
            height: min(rect.height, IslandPalette.physicalNotchHeight)
        )
        path.addPath(Path(PhysicalNotchCutoutGeometry.makePath(in: cutoutRect)))
        return path
    }
}
