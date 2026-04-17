import AppKit
import SwiftUI
import XCTest

@testable import AIIslandApp
@testable import AIIslandCore

@MainActor
final class VisualSnapshotSmokeTests: XCTestCase {
    func testRenderReferenceSnapshots() throws {
        let bundle = try FixtureBundleLoader.load(from: try fixtureURL)
        let outputDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aiisland-visual-smoke", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let busyFixture = try fixture(named: .bothBusy, in: bundle)
        let overflowFixture = ReviewFixtureResolver.normalizeForReview(
            try fixture(named: .threadOverflow, in: bundle),
            now: Date(timeIntervalSince1970: 1_776_256_800)
        )
        let longModelFixture = try fixture(named: .longModelNames, in: bundle)

        try render(
            view: snapshotCanvas {
                CollapsedIslandView(codex: busyFixture.codex, claude: busyFixture.claude)
            },
            size: CGSize(
                width: IslandPalette.shellWidth + 44,
                height: IslandPalette.shellHeight + 34
            ),
            to: outputDirectory.appendingPathComponent("collapsed-both-busy.png")
        )

        try render(
            view: snapshotCanvas {
                ExpandedIslandCardView(
                    codex: overflowFixture.codex,
                    claude: overflowFixture.claude,
                    codexDiagnostics: .empty(
                        kind: .codex,
                        freshnessPolicy: .v02Smooth,
                        triggerMode: "snapshot"
                    ),
                    claudeDiagnostics: .empty(
                        kind: .claude,
                        freshnessPolicy: .v02Smooth,
                        triggerMode: "snapshot"
                    )
                )
            },
            size: CGSize(
                width: IslandPalette.expandedCardWidth + 36,
                height: IslandPalette.canvasHeight
            ),
            to: outputDirectory.appendingPathComponent("expanded-thread-overflow.png")
        )

        try render(
            view: snapshotCanvas {
                ExpandedIslandCardView(
                    codex: longModelFixture.codex,
                    claude: longModelFixture.claude,
                    codexDiagnostics: .empty(
                        kind: .codex,
                        freshnessPolicy: .v02Smooth,
                        triggerMode: "snapshot"
                    ),
                    claudeDiagnostics: .empty(
                        kind: .claude,
                        freshnessPolicy: .v02Smooth,
                        triggerMode: "snapshot"
                    )
                )
            },
            size: CGSize(
                width: IslandPalette.expandedCardWidth + 36,
                height: IslandPalette.canvasHeight
            ),
            to: outputDirectory.appendingPathComponent("expanded-long-models.png")
        )

        print("Visual snapshots exported to \(outputDirectory.path)")
    }

    private var fixtureURL: URL {
        get throws {
            try XCTUnwrap(
                FixtureBundleMarker.bundle.url(
                    forResource: "phase1-fixtures",
                    withExtension: "json"
                )
            )
        }
    }

    private func fixture(named scenario: FixtureScenario, in bundle: FixtureBundle) throws -> FixtureAgents {
        try XCTUnwrap(bundle.fixtures[scenario.rawValue])
    }

    private func render<V: View>(view: V, size: CGSize, to url: URL) throws {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.updateConstraintsForSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            XCTFail("Unable to create bitmap for snapshot.")
            return
        }

        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let imageData = try XCTUnwrap(
            bitmap.representation(using: .png, properties: [:])
        )
        try imageData.write(to: url)
    }

    private func snapshotCanvas<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.17, green: 0.13, blue: 0.07),
                    Color(red: 0.10, green: 0.08, blue: 0.05)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            content()
        }
    }
}
