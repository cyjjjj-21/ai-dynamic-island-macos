import Foundation
import XCTest

@testable import AIIslandApp

final class ReadBlockCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

final class BlockingFileManager: FileManager {
    private final class PendingRead {
        let semaphore = DispatchSemaphore(value: 0)
    }

    private let lock = NSLock()
    private var blockedReads: [String: [PendingRead]] = [:]
    private var activeBlockedReads: [PendingRead] = []
    private let didBlockCallback: @Sendable (String) -> Void

    init(didBlock: @escaping @Sendable (String) -> Void = { _ in }) {
        didBlockCallback = didBlock
        super.init()
    }

    func blockNextRead(atPath path: String) {
        lock.lock()
        blockedReads[path, default: []].append(PendingRead())
        lock.unlock()
    }

    func releaseBlockedRead() {
        let pendingRead: PendingRead? = {
            lock.lock()
            defer { lock.unlock() }
            guard !activeBlockedReads.isEmpty else {
                return nil
            }
            return activeBlockedReads.removeFirst()
        }()

        pendingRead?.semaphore.signal()
    }

    override func contents(atPath path: String) -> Data? {
        let pendingRead: PendingRead? = {
            lock.lock()
            defer { lock.unlock() }
            guard var reads = blockedReads[path], !reads.isEmpty else {
                return nil
            }
            let pendingRead = reads.removeFirst()
            blockedReads[path] = reads.isEmpty ? nil : reads
            activeBlockedReads.append(pendingRead)
            return pendingRead
        }()

        if let pendingRead {
            didBlockCallback(path)
            pendingRead.semaphore.wait()
        }

        return super.contents(atPath: path)
    }
}

final class TestRealtimeSignalSource: RealtimeSignalSource {
    var onSignal: (@MainActor () -> Void)?

    func updateWatchedPaths(_ paths: [String]) {}
    func start() {}
    func stop() {}

    func emit() {
        let handler = onSignal
        Task { @MainActor in
            handler?()
        }
    }
}

@MainActor
func assertEventually(
    timeout: TimeInterval = 1.0,
    interval: TimeInterval = 0.01,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: @escaping @MainActor () -> Bool
) {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() {
            return
        }

        RunLoop.main.run(until: Date().addingTimeInterval(interval))
    }

    XCTFail("Condition was not satisfied before timeout.", file: file, line: line)
}
