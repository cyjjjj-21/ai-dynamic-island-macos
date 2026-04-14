import XCTest

@testable import AIIslandApp

final class CodexSessionTailReaderTests: XCTestCase {
    func testTailReaderTrimsPartialFirstLineWhenReadingFromMiddleOfFile() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appendingPathComponent("tail.jsonl")
        let longPrefix = String(repeating: "a", count: 120)
        let content = longPrefix + "\nline-2\nline-3\n"
        try Data(content.utf8).write(to: fileURL)

        let text = try XCTUnwrap(
            CodexSessionTailReader.readTail(
                atPath: fileURL.path,
                fileSize: UInt64(content.utf8.count),
                initialWindow: 24,
                maxWindow: 24,
                minimumLineCount: 1
            )
        )

        XCTAssertEqual(text, "line-2\nline-3\n")
    }

    func testTailReaderExpandsWindowUntilMinimumLineCountIsReached() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appendingPathComponent("expand.jsonl")
        let content = (1...12).map { "line-\($0)" }.joined(separator: "\n") + "\n"
        try Data(content.utf8).write(to: fileURL)

        let text = try XCTUnwrap(
            CodexSessionTailReader.readTail(
                atPath: fileURL.path,
                fileSize: UInt64(content.utf8.count),
                initialWindow: 12,
                maxWindow: 128,
                minimumLineCount: 6
            )
        )

        XCTAssertGreaterThanOrEqual(
            text.split(separator: "\n", omittingEmptySubsequences: true).count,
            6
        )
        XCTAssertTrue(text.contains("line-12"))
    }

    func testTailReaderStopsGrowingAtMaxWindowForLargeFiles() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let fileURL = rootURL.appendingPathComponent("large.jsonl")
        let line = String(repeating: "x", count: 96)
        let content = Array(repeating: line, count: 40).joined(separator: "\n") + "\n"
        try Data(content.utf8).write(to: fileURL)

        let text = try XCTUnwrap(
            CodexSessionTailReader.readTail(
                atPath: fileURL.path,
                fileSize: UInt64(content.utf8.count),
                initialWindow: 64,
                maxWindow: 256,
                minimumLineCount: 1000
            )
        )

        XCTAssertLessThanOrEqual(text.utf8.count, 256)
        XCTAssertFalse(text.isEmpty)
    }
}
