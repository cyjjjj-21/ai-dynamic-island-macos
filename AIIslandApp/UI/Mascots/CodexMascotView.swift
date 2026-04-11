import SwiftUI

public struct CodexMascotView: View {
    private let scale: CGFloat

    public init(scale: CGFloat = 1.0) {
        self.scale = scale
    }

    public var body: some View {
        PixelMascotView(glyph: .codexSoftComputeBlobReference, scale: scale)
    }
}
