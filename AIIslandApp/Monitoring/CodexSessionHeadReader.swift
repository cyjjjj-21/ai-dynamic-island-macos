import Foundation

enum CodexSessionHeadReader {
    static let defaultByteCount = 8 * 1_024

    static func readHead(
        atPath path: String,
        byteCount: Int = defaultByteCount,
        maxByteCount: Int? = nil
    ) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return nil
        }
        defer { try? handle.close() }

        let initialByteCount = max(1, byteCount)
        let maximumByteCount = maxByteCount.map { max(initialByteCount, $0) }
        var buffer = Data()

        while buffer.count < initialByteCount || buffer.lastIndex(of: 0x0A) == nil {
            if let maximumByteCount, buffer.count >= maximumByteCount {
                break
            }

            let chunkSize: Int
            if let maximumByteCount {
                chunkSize = min(initialByteCount, maximumByteCount - buffer.count)
            } else {
                chunkSize = initialByteCount
            }
            guard chunkSize > 0 else {
                break
            }

            guard let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty else {
                break
            }

            buffer.append(chunk)
            if chunk.count < chunkSize {
                break
            }
        }

        guard !buffer.isEmpty else {
            return nil
        }

        let endIndex = buffer.lastIndex(of: 0x0A).map { buffer.index(after: $0) } ?? buffer.endIndex
        let completeData = buffer.prefix(upTo: endIndex)
        return String(decoding: completeData, as: UTF8.self)
    }
}
