import Foundation

struct CodexIndexedThread: Equatable {
    let threadID: String
    let threadName: String
    let updatedAt: Date
}

enum CodexSessionIndexParser {
    static func parse(_ text: String) -> [CodexIndexedThread] {
        var dateContext = DateParsingContext()
        var newestByThreadID: [String: CodexIndexedThread] = [:]

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard
                let lineData = rawLine.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                let threadID = normalizedString(json["id"]),
                let updatedAt = parseDate(
                    json["updated_at"] ?? json["updatedAt"] ?? json["timestamp"],
                    context: &dateContext
                )
            else {
                continue
            }

            let threadName = normalizedString(json["thread_name"])
                ?? normalizedString(json["title"])
                ?? ""
            let candidate = CodexIndexedThread(
                threadID: threadID,
                threadName: threadName,
                updatedAt: updatedAt
            )

            if let existing = newestByThreadID[threadID], existing.updatedAt >= candidate.updatedAt {
                continue
            }
            newestByThreadID[threadID] = candidate
        }

        return newestByThreadID.values.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.threadID < rhs.threadID
        }
    }

    private static func normalizedString(_ value: Any?) -> String? {
        guard let value = value as? String else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private struct DateParsingContext {
        let fractional: ISO8601DateFormatter
        let base: ISO8601DateFormatter

        init() {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            self.fractional = fractional

            let base = ISO8601DateFormatter()
            base.formatOptions = [.withInternetDateTime]
            self.base = base
        }
    }

    private static func parseDate(_ value: Any?, context: inout DateParsingContext) -> Date? {
        guard let value else {
            return nil
        }

        if let date = value as? Date {
            return date
        }

        if let unix = value as? Double {
            return unix > 10_000_000_000
                ? Date(timeIntervalSince1970: unix / 1_000.0)
                : Date(timeIntervalSince1970: unix)
        }

        if let unix = value as? Int {
            let time = Double(unix)
            return time > 10_000_000_000
                ? Date(timeIntervalSince1970: time / 1_000.0)
                : Date(timeIntervalSince1970: time)
        }

        if let raw = value as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return nil
            }

            if let unix = Double(trimmed) {
                return unix > 10_000_000_000
                    ? Date(timeIntervalSince1970: unix / 1_000.0)
                    : Date(timeIntervalSince1970: unix)
            }

            if let date = context.fractional.date(from: trimmed) {
                return date
            }

            if let date = context.base.date(from: trimmed) {
                return date
            }
        }

        return nil
    }
}
