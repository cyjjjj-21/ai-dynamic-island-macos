import Foundation
import XCTest

final class ReviewCaptureScriptSmokeTests: XCTestCase {
    func testCaptureReviewBundleWritesExpectedArtifactsInTestMode() throws {
        let repoRoot = try XCTUnwrap(
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .path(percentEncoded: false)
                .isEmpty == false
                ? URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                : nil
        )
        let scriptURL = repoRoot.appending(path: "scripts/capture_review_bundle.py")
        let outputDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            scriptURL.path(percentEncoded: false),
            "--app", "AIIslandApp",
            "--output-dir", outputDirectory.path(percentEncoded: false)
        ]
        process.environment = [
            "AIISLAND_CAPTURE_TEST_MODE": "1"
        ]

        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDirectory.appending(path: "window.png").path(percentEncoded: false)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDirectory.appending(path: "desktop.png").path(percentEncoded: false)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDirectory.appending(path: "metadata.json").path(percentEncoded: false)))

        let metadataData = try Data(contentsOf: outputDirectory.appending(path: "metadata.json"))
        let metadata = try JSONSerialization.jsonObject(with: metadataData) as? [String: Any]
        let selectedWindow = metadata?["selectedWindow"] as? [String: Any]
        let bounds = selectedWindow?["bounds"] as? [String: Any]

        XCTAssertEqual(metadata?["app"] as? String, "AIIslandApp")
        XCTAssertEqual(selectedWindow?["id"] as? Int, 999)
        XCTAssertEqual(bounds?["width"] as? Int, 449)
        XCTAssertEqual(bounds?["height"] as? Int, 340)
    }
}
