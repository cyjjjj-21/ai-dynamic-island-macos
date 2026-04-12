import XCTest

@testable import AIIslandApp

@MainActor
final class IslandPanelFocusTests: XCTestCase {
    func testIslandPanelNeverBecomesKeyOrMain() {
        let panel = IslandPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
    }
}
