import XCTest

@testable import AIIslandApp

final class ClaudeSessionCatalogTests: XCTestCase {
    func testCatalogSortsSessionsByObservedAtDescending() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionsDirURL = rootURL.appendingPathComponent("sessions", isDirectory: true)

        try fileManager.createDirectory(at: sessionsDirURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let olderPath = sessionsDirURL.appendingPathComponent("older.json")
        let newerPath = sessionsDirURL.appendingPathComponent("newer.json")

        try """
        {"pid": 1001, "sessionId": "older", "cwd": "/workspace/older", "status": "idle"}
        """.data(using: .utf8)?.write(to: olderPath)

        try """
        {"pid": 1002, "sessionId": "newer", "cwd": "/workspace/newer", "status": "busy"}
        """.data(using: .utf8)?.write(to: newerPath)

        try fileManager.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: olderPath.path
        )
        try fileManager.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: newerPath.path
        )

        let sessions = ClaudeSessionCatalog.loadCandidates(
            fileManager: fileManager,
            sessionsDirPath: sessionsDirURL.path
        )

        XCTAssertEqual(sessions.map(\.sessionID), ["newer", "older"])
    }

    func testCatalogSkipsMalformedSessionFiles() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionsDirURL = rootURL.appendingPathComponent("sessions", isDirectory: true)

        try fileManager.createDirectory(at: sessionsDirURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        try """
        {"pid": 1001, "sessionId": "valid", "cwd": "/workspace/valid", "status": "waiting", "waitingFor": "approve Read"}
        """.data(using: .utf8)?.write(to: sessionsDirURL.appendingPathComponent("valid.json"))

        try "not-json".data(using: .utf8)?.write(
            to: sessionsDirURL.appendingPathComponent("broken.json")
        )

        try """
        {"pid": 1002, "cwd": "/workspace/missing", "status": "busy"}
        """.data(using: .utf8)?.write(
            to: sessionsDirURL.appendingPathComponent("missing-session-id.json")
        )

        let sessions = ClaudeSessionCatalog.loadCandidates(
            fileManager: fileManager,
            sessionsDirPath: sessionsDirURL.path
        )

        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.sessionID, "valid")
        XCTAssertEqual(sessions.first?.activity?.status, .waiting)
    }

    func testCatalogKeepsMultipleReadableSessionsInsteadOfOnlyNewestOne() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionsDirURL = rootURL.appendingPathComponent("sessions", isDirectory: true)

        try fileManager.createDirectory(at: sessionsDirURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        for index in 0..<3 {
            let path = sessionsDirURL.appendingPathComponent("session-\(index).json")
            try """
            {"pid": \(2000 + index), "sessionId": "session-\(index)", "cwd": "/workspace/\(index)", "status": "busy"}
            """.data(using: .utf8)?.write(to: path)
            try fileManager.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: TimeInterval(300 + index))],
                ofItemAtPath: path.path
            )
        }

        let sessions = ClaudeSessionCatalog.loadCandidates(
            fileManager: fileManager,
            sessionsDirPath: sessionsDirURL.path
        )

        XCTAssertEqual(sessions.count, 3)
        XCTAssertEqual(Set(sessions.map(\.sessionID)), ["session-0", "session-1", "session-2"])
    }
}
