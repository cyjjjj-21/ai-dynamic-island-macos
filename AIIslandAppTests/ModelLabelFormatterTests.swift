import XCTest

@testable import AIIslandApp

final class ModelLabelFormatterTests: XCTestCase {
    func testCodexModelBuildSuffixTruncatesToPrimaryIdentity() {
        XCTAssertEqual(
            ModelLabelFormatter.displayName(
                for: "gpt-5.4-internal-preview-long-build-string"
            ),
            "GPT-5.4"
        )
    }

    func testThirdPartyModelPreservesProviderIdentity() {
        XCTAssertEqual(
            ModelLabelFormatter.displayName(
                for: "kimi-k2.5-long-provider-build-2026-04-experimental"
            ),
            "Kimi K2.5"
        )
    }

    func testCanonicalMiniVariantKeepsApprovedSuffix() {
        XCTAssertEqual(
            ModelLabelFormatter.displayName(for: "gpt-5.4-mini"),
            "GPT-5.4-mini"
        )
    }

    func testRepeatedSeparatorsAreNormalizedBeforeTruncation() {
        XCTAssertEqual(
            ModelLabelFormatter.displayName(for: "  glm___5.1---internal___preview  "),
            "GLM-5.1"
        )
    }

    func testLongUnknownLabelFallsBackToSingleLineTailTruncation() {
        let label = ModelLabelFormatter.displayName(
            for: "experimental-provider-super-long-build-string-with-many-extra-parts"
        )

        XCTAssertTrue(label.hasSuffix("…"))
        XCTAssertLessThanOrEqual(label.count, 18)
    }
}
