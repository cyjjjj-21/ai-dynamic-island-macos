import SwiftUI

public struct MascotPixelColor: Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

public struct MascotPixelGlyph: Hashable, Sendable {
    public struct Block: Hashable, Sendable {
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double
        public let fill: MascotPixelColor

        public init(
            x: Double,
            y: Double,
            width: Double,
            height: Double,
            fill: MascotPixelColor
        ) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
            self.fill = fill
        }
    }

    public let canvasWidth: Double
    public let canvasHeight: Double
    public let blocks: [Block]

    public init(canvasWidth: Double, canvasHeight: Double, blocks: [Block]) {
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.blocks = blocks
    }

    public var size: CGSize {
        CGSize(width: canvasWidth, height: canvasHeight)
    }
}

public extension MascotPixelGlyph {
    static let claudeReference = MascotPixelGlyph(
        canvasWidth: 22,
        canvasHeight: 20,
        blocks: [
            .init(x: 4, y: 3, width: 14, height: 9, fill: .init(red: 0.8470588235, green: 0.5372549020, blue: 0.5450980392)),
            .init(x: 3, y: 5, width: 1, height: 2, fill: .init(red: 0.9529411765, green: 0.6705882353, blue: 0.6784313725)),
            .init(x: 18, y: 5, width: 1, height: 2, fill: .init(red: 0.9529411765, green: 0.6705882353, blue: 0.6784313725)),
            .init(x: 7, y: 6, width: 2, height: 3, fill: .init(red: 0.0509803922, green: 0.0352941176, blue: 0.0352941176)),
            .init(x: 13, y: 6, width: 2, height: 3, fill: .init(red: 0.0509803922, green: 0.0352941176, blue: 0.0352941176)),
            .init(x: 6, y: 13, width: 1.6, height: 4, fill: .init(red: 0.9529411765, green: 0.6705882353, blue: 0.6784313725)),
            .init(x: 8.5, y: 13, width: 1.6, height: 4, fill: .init(red: 0.9529411765, green: 0.6705882353, blue: 0.6784313725)),
            .init(x: 12.5, y: 13, width: 1.6, height: 4, fill: .init(red: 0.9529411765, green: 0.6705882353, blue: 0.6784313725)),
            .init(x: 15, y: 13, width: 1.6, height: 4, fill: .init(red: 0.9529411765, green: 0.6705882353, blue: 0.6784313725))
        ]
    )

    static let codexSoftComputeBlobReference = MascotPixelGlyph(
        canvasWidth: 22,
        canvasHeight: 20,
        blocks: [
            .init(x: 6, y: 3, width: 10, height: 2, fill: .init(red: 0.7568627451, green: 0.9843137255, blue: 1.0)),
            .init(x: 4, y: 5, width: 14, height: 7, fill: .init(red: 0.4509803922, green: 0.8941176471, blue: 1.0)),
            .init(x: 5, y: 4, width: 2, height: 1, fill: .init(red: 0.6509803922, green: 0.9568627451, blue: 1.0)),
            .init(x: 15, y: 4, width: 2, height: 1, fill: .init(red: 0.6509803922, green: 0.9568627451, blue: 1.0)),
            .init(x: 8, y: 7, width: 2, height: 2, fill: .init(red: 0.0313725490, green: 0.0745098039, blue: 0.1019607843)),
            .init(x: 12, y: 7, width: 2, height: 2, fill: .init(red: 0.0313725490, green: 0.0745098039, blue: 0.1019607843)),
            .init(x: 5, y: 12, width: 2, height: 2, fill: .init(red: 0.4509803922, green: 0.8941176471, blue: 1.0)),
            .init(x: 8, y: 12, width: 2, height: 4, fill: .init(red: 0.4509803922, green: 0.8941176471, blue: 1.0)),
            .init(x: 12, y: 12, width: 2, height: 4, fill: .init(red: 0.4509803922, green: 0.8941176471, blue: 1.0)),
            .init(x: 15, y: 12, width: 2, height: 2, fill: .init(red: 0.4509803922, green: 0.8941176471, blue: 1.0))
        ]
    )
}
