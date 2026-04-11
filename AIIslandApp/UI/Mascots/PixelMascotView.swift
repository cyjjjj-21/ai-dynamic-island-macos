import SwiftUI

public struct PixelMascotView: View {
    public let glyph: MascotPixelGlyph
    public let scale: CGFloat

    public init(glyph: MascotPixelGlyph, scale: CGFloat = 1.0) {
        self.glyph = glyph
        self.scale = scale
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(glyph.blocks.enumerated()), id: \.offset) { _, block in
                Rectangle()
                    .fill(block.fill.color)
                    .frame(
                        width: CGFloat(block.width) * scale,
                        height: CGFloat(block.height) * scale
                    )
                    .offset(
                        x: CGFloat(block.x) * scale,
                        y: CGFloat(block.y) * scale
                    )
            }
        }
        .frame(
            width: CGFloat(glyph.canvasWidth) * scale,
            height: CGFloat(glyph.canvasHeight) * scale,
            alignment: .topLeading
        )
        .accessibilityHidden(true)
    }
}
