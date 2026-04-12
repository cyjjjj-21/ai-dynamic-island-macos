import Darwin
import Foundation

import AIIslandCore

struct MonitorThreadDiagnostics: Identifiable, Equatable, Sendable {
    let id: String
    let lastSignalAt: Date?
    let stage: MonitorFreshnessStage
    let sourceHits: [String]
}

struct AgentMonitorDiagnostics: Equatable, Sendable {
    let kind: AgentKind
    let refreshedAt: Date?
    let freshnessPolicy: MonitorFreshnessPolicy
    let triggerMode: String
    let threads: [MonitorThreadDiagnostics]

    static func empty(kind: AgentKind, freshnessPolicy: MonitorFreshnessPolicy, triggerMode: String) -> Self {
        AgentMonitorDiagnostics(
            kind: kind,
            refreshedAt: nil,
            freshnessPolicy: freshnessPolicy,
            triggerMode: triggerMode,
            threads: []
        )
    }
}

protocol RealtimeSignalSource: AnyObject {
    var onSignal: (@MainActor () -> Void)? { get set }
    func updateWatchedPaths(_ paths: [String])
    func start()
    func stop()
}

final class VnodeRealtimeSignalSource: RealtimeSignalSource {
    var onSignal: (@MainActor () -> Void)?

    private let queue: DispatchQueue
    private var watchedPaths: [String]
    private var descriptors: [Int32] = []
    private var sources: [DispatchSourceFileSystemObject] = []

    init(paths: [String], queue: DispatchQueue = DispatchQueue(label: "aiisland.monitor.fs", qos: .userInitiated)) {
        self.watchedPaths = paths
        self.queue = queue
    }

    func updateWatchedPaths(_ paths: [String]) {
        let normalized = Self.normalize(paths)
        guard normalized != watchedPaths else {
            return
        }

        watchedPaths = normalized
        restart()
    }

    func start() {
        guard sources.isEmpty, descriptors.isEmpty else {
            return
        }

        for path in watchedPaths {
            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else {
                continue
            }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .extend, .attrib, .delete, .rename, .link],
                queue: queue
            )

            source.setEventHandler { [weak self] in
                self?.emitSignal()
            }

            source.setCancelHandler {
                close(descriptor)
            }

            descriptors.append(descriptor)
            sources.append(source)
            source.resume()
        }
    }

    func stop() {
        for source in sources {
            source.cancel()
        }
        sources.removeAll()
        descriptors.removeAll()
    }

    private func restart() {
        stop()
        start()
    }

    private func emitSignal() {
        let handler = onSignal
        Task { @MainActor in
            handler?()
        }
    }

    private static func normalize(_ paths: [String]) -> [String] {
        var deduplicated: [String] = []
        var seen = Set<String>()
        for path in paths where !path.isEmpty {
            if seen.insert(path).inserted {
                deduplicated.append(path)
            }
        }
        return deduplicated.sorted()
    }
}
