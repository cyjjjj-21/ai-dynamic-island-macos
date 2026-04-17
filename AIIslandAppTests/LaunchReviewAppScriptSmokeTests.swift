import Foundation
import XCTest

final class LaunchReviewAppScriptSmokeTests: XCTestCase {
    func testLaunchReviewAppKeepsChildProcessAliveAfterLauncherExits() throws {
        let repoRoot = try XCTUnwrap(
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        )
        let launcherURL = repoRoot.appending(path: "scripts/launch_review_app.sh")
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let bundleURL = tempRoot
            .appending(path: "FakeReview.app")
            .appending(path: "Contents")
            .appending(path: "MacOS")
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let binaryURL = bundleURL.appending(path: "AIIslandApp")
        let startedURL = tempRoot.appending(path: "started.marker")
        let pidURL = tempRoot.appending(path: "pid.txt")
        let hupURL = tempRoot.appending(path: "hup.marker")
        let completedURL = tempRoot.appending(path: "completed.marker")

        let fakeBinary = """
        #!/usr/bin/env bash
        set -euo pipefail
        echo "$$" > "$AIISLAND_LAUNCH_SMOKE_PID"
        touch "$AIISLAND_LAUNCH_SMOKE_STARTED"
        trap 'touch "$AIISLAND_LAUNCH_SMOKE_HUP"; exit 0' HUP
        sleep 5
        touch "$AIISLAND_LAUNCH_SMOKE_COMPLETED"
        """
        try fakeBinary.write(to: binaryURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: binaryURL.path(percentEncoded: false)
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            launcherURL.path(percentEncoded: false),
            "pinnedExpanded",
            "thread-overflow",
            tempRoot.appending(path: "FakeReview.app").path(percentEncoded: false),
        ]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "AIISLAND_LAUNCH_SMOKE_STARTED": startedURL.path(percentEncoded: false),
            "AIISLAND_LAUNCH_SMOKE_PID": pidURL.path(percentEncoded: false),
            "AIISLAND_LAUNCH_SMOKE_HUP": hupURL.path(percentEncoded: false),
            "AIISLAND_LAUNCH_SMOKE_COMPLETED": completedURL.path(percentEncoded: false),
            "AIISLAND_REVIEW_FORCE_BINARY": "1",
        ]) { _, new in new }

        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertTrue(waitForFile(startedURL))
        XCTAssertTrue(waitForFile(pidURL))

        let pidText = try String(contentsOf: pidURL, encoding: .utf8)
        let pid = try XCTUnwrap(Int(pidText.trimmingCharacters(in: .whitespacesAndNewlines)))
        defer {
            kill(pid_t(pid), SIGTERM)
        }

        XCTAssertTrue(isProcessAlive(pid), "fake app child exited after launcher returned")
        XCTAssertFalse(FileManager.default.fileExists(atPath: hupURL.path(percentEncoded: false)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: completedURL.path(percentEncoded: false)))
    }

    private func waitForFile(_ url: URL, timeout: TimeInterval = 2.0) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    private func isProcessAlive(_ pid: Int) -> Bool {
        kill(pid_t(pid), 0) == 0
    }
}
