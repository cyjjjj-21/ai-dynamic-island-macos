import SwiftUI

struct NotchLobeShape: Shape {
    let side: NotchLobeSide
    let overlap: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(
            NotchLobeGeometry.makePath(
                side: side,
                in: rect,
                overlap: overlap,
                shoulderY: rect.height * 0.43
            )
        )
    }
}
