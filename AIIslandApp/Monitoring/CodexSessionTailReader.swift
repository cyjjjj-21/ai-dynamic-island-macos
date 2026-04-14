import Foundation

enum CodexSessionTailReader {
    static let defaultInitialWindow: UInt64 = 524_288
    static let defaultMaxWindow: UInt64 = 8 * 1_024 * 1_024
    static let defaultMinimumLineCount = 180

    static func readTail(
        atPath path: String,
        fileSize: UInt64,
        initialWindow: UInt64,
        maxWindow: UInt64,
        minimumLineCount: Int
    ) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return nil
        }
        defer { try? handle.close() }

        let resolvedFileSize: UInt64
        if fileSize > 0 {
            resolvedFileSize = fileSize
        } else if let measuredFileSize = try? handle.seekToEnd(), measuredFileSize > 0 {
            resolvedFileSize = measuredFileSize
        } else {
            return nil
        }

        let boundedMaxWindow = min(resolvedFileSize, maxWindow)
        var window = min(initialWindow, boundedMaxWindow)
        var bestText: String?

        while true {
            let offset = resolvedFileSize > window ? resolvedFileSize - window : 0
            try? handle.seek(toOffset: offset)
            guard let data = try? handle.read(upToCount: Int(window)),
                  let rawText = String(data: data, encoding: .utf8)
            else {
                return bestText
            }

            let normalizedText: String
            if offset > 0, let firstNewline = rawText.firstIndex(of: "\n") {
                normalizedText = String(rawText[rawText.index(after: firstNewline)...])
            } else {
                normalizedText = rawText
            }

            bestText = normalizedText
            let lineCount = normalizedText.split(separator: "\n", omittingEmptySubsequences: true).count
            let reachedStart = offset == 0
            let reachedMaxWindow = window >= boundedMaxWindow

            if lineCount >= minimumLineCount || reachedStart || reachedMaxWindow {
                return bestText
            }

            let grownWindow = min(window * 2, boundedMaxWindow)
            if grownWindow == window {
                return bestText
            }
            window = grownWindow
        }
    }
}
