import XCTest

@testable import AIIslandApp

final class CodexSessionCatalogTests: XCTestCase {
    func testCatalogSortsNewestSessionFilesFirst() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionsDayURL = rootURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("04", isDirectory: true)
            .appendingPathComponent("15", isDirectory: true)

        try fileManager.createDirectory(at: sessionsDayURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let olderURL = sessionsDayURL.appendingPathComponent("older.jsonl")
        let newerURL = sessionsDayURL.appendingPathComponent("newer.jsonl")
        try Data("older\n".utf8).write(to: olderURL)
        try Data("newer\n".utf8).write(to: newerURL)

        try fileManager.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: olderURL.path
        )
        try fileManager.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: newerURL.path
        )

        let files = CodexSessionCatalog.discoverSessionFiles(
            fileManager: fileManager,
            sessionsDirectoryURL: rootURL.appendingPathComponent("sessions", isDirectory: true),
            maxFiles: 10
        )

        XCTAssertEqual(files.map(\.url.lastPathComponent), ["newer.jsonl", "older.jsonl"])
    }

    func testCatalogCapsReturnedFilesAtConfiguredMaximum() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionsDayURL = rootURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("04", isDirectory: true)
            .appendingPathComponent("15", isDirectory: true)

        try fileManager.createDirectory(at: sessionsDayURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        for index in 0..<5 {
            let fileURL = sessionsDayURL.appendingPathComponent("session-\(index).jsonl")
            try Data("line-\(index)\n".utf8).write(to: fileURL)
            try fileManager.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: TimeInterval(500 - index))],
                ofItemAtPath: fileURL.path
            )
        }

        let files = CodexSessionCatalog.discoverSessionFiles(
            fileManager: fileManager,
            sessionsDirectoryURL: rootURL.appendingPathComponent("sessions", isDirectory: true),
            maxFiles: 3
        )

        XCTAssertEqual(files.count, 3)
        XCTAssertEqual(files.map(\.url.lastPathComponent), ["session-0.jsonl", "session-1.jsonl", "session-2.jsonl"])
    }

    func testCatalogExtractsThreadIDFromRolloutFilenameWhenUUIDSuffixExists() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionsDayURL = rootURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("04", isDirectory: true)
            .appendingPathComponent("15", isDirectory: true)

        try fileManager.createDirectory(at: sessionsDayURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let threadID = "019d7280-4a37-75a3-859a-29c3389b3832"
        let fileURL = sessionsDayURL.appendingPathComponent("rollout-2026-04-11T15-50-00-\(threadID).jsonl")
        try Data("line\n".utf8).write(to: fileURL)

        let files = CodexSessionCatalog.discoverSessionFiles(
            fileManager: fileManager,
            sessionsDirectoryURL: rootURL.appendingPathComponent("sessions", isDirectory: true),
            maxFiles: 10
        )

        XCTAssertEqual(files.first?.threadID, threadID)
    }
}
