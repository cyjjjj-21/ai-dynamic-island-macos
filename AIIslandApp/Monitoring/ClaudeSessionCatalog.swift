import Foundation

struct ClaudeSessionCandidate: Equatable, Sendable {
    let pid: Int32
    let sessionID: String
    let cwd: String
    let observedAt: Date
    let filePath: String
    let activity: ClaudeCodeSessionActivity?
}

enum ClaudeSessionCatalog {
    static func loadCandidates(
        fileManager: FileManager,
        sessionsDirPath: String
    ) -> [ClaudeSessionCandidate] {
        guard let files = try? fileManager.contentsOfDirectory(atPath: sessionsDirPath) else {
            return []
        }

        var sessions: [ClaudeSessionCandidate] = []
        sessions.reserveCapacity(files.count)

        for file in files where file.hasSuffix(".json") {
            let path = sessionsDirPath + "/" + file
            guard
                let attributes = try? fileManager.attributesOfItem(atPath: path),
                let observedAt = attributes[.modificationDate] as? Date,
                let data = fileManager.contents(atPath: path),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let pid = json["pid"] as? Int,
                let sessionID = json["sessionId"] as? String,
                let cwd = json["cwd"] as? String
            else {
                continue
            }

            sessions.append(
                ClaudeSessionCandidate(
                    pid: Int32(pid),
                    sessionID: sessionID,
                    cwd: cwd,
                    observedAt: observedAt,
                    filePath: path,
                    activity: ClaudeCodeSnapshotParser.parseSessionActivity(from: data)
                )
            )
        }

        return sessions.sorted { lhs, rhs in
            if lhs.observedAt != rhs.observedAt {
                return lhs.observedAt > rhs.observedAt
            }
            return lhs.sessionID < rhs.sessionID
        }
    }
}
