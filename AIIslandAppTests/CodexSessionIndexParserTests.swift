import XCTest

@testable import AIIslandApp

final class CodexSessionIndexParserTests: XCTestCase {
    func testParseSessionIndexPrefersNewestEntryPerThreadID() {
        let jsonl = """
        {"id":"thread-1","thread_name":"Old title","updated_at":"2026-04-11T01:00:00Z"}
        {"id":"thread-1","thread_name":"New title","updated_at":"2026-04-11T02:00:00Z"}
        {"id":"thread-2","thread_name":"Other thread","updated_at":"2026-04-11T01:30:00Z"}
        """

        let snapshots = CodexSessionIndexParser.parse(jsonl)

        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots.first?.threadName, "New title")
        XCTAssertEqual(snapshots.first?.threadID, "thread-1")
    }

    func testParseSessionIndexIgnoresMalformedRows() {
        let jsonl = """
        {"id":"thread-1","thread_name":"Valid","updated_at":"2026-04-11T02:00:00Z"}
        not-json
        {"thread_name":"Missing id"}
        """

        let snapshots = CodexSessionIndexParser.parse(jsonl)

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.threadID, "thread-1")
        XCTAssertEqual(snapshots.first?.threadName, "Valid")
    }
}
