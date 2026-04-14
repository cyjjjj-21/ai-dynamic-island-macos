import Foundation

struct CodexSessionFileCandidate: Sendable {
    let url: URL
    let modifiedAt: Date
    let fileSize: UInt64
    let threadID: String
}

enum CodexSessionCatalog {
    static let defaultMaxFilesToScan = 36

    static func discoverSessionFiles(
        fileManager: FileManager,
        sessionsDirectoryURL: URL,
        maxFiles: Int
    ) -> [CodexSessionFileCandidate] {
        guard
            let enumerator = fileManager.enumerator(
                at: sessionsDirectoryURL,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }

        var files: [CodexSessionFileCandidate] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else {
                continue
            }

            guard
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                values.isRegularFile == true
            else {
                continue
            }

            files.append(
                CodexSessionFileCandidate(
                    url: url,
                    modifiedAt: values.contentModificationDate ?? .distantPast,
                    fileSize: UInt64(values.fileSize ?? 0),
                    threadID: resolveThreadID(from: url)
                )
            )
        }

        files.sort { lhs, rhs in
            if lhs.modifiedAt != rhs.modifiedAt {
                return lhs.modifiedAt > rhs.modifiedAt
            }
            return lhs.url.path < rhs.url.path
        }

        return Array(files.prefix(maxFiles))
    }

    static func baseWatchedPaths(codexHomePath: String) -> [String] {
        [
            codexHomePath,
            codexHomePath + "/session_index.jsonl",
            codexHomePath + "/sessions",
        ]
    }

    static func watchedPaths(
        codexHomePath: String,
        sessionFiles: [CodexSessionFileCandidate]
    ) -> [String] {
        var paths = baseWatchedPaths(codexHomePath: codexHomePath)
        paths.append(contentsOf: sessionFiles.map { $0.url.deletingLastPathComponent().path })
        return paths
    }

    static func resolveThreadID(from sessionFileURL: URL) -> String {
        let filename = sessionFileURL.deletingPathExtension().lastPathComponent
        let pattern = #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#
        if let range = filename.range(of: pattern, options: .regularExpression) {
            return String(filename[range]).lowercased()
        }
        return filename
    }
}
