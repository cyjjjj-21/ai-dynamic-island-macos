import Foundation

import AIIslandCore

@MainActor
final class CodexMonitor: ObservableObject {
    @Published private(set) var codexState: AgentState = AgentState(
        kind: .codex,
        online: false,
        availability: .offline,
        globalState: .offline,
        threads: [],
        quota: nil
    )

    private let fileManager: FileManager
    private let codexHomePath: String
    private var pollTimer: Timer?

    private static let activeStateWindow: TimeInterval = 2 * 60
    private static let coolingIdleWindow: TimeInterval = 8 * 60
    private static let visibleIdleWindow: TimeInterval = 15 * 60
    private static let liveSignalWindow: TimeInterval = 30 * 60
    private static let maxVisibleThreads = 3
    private static let maxSessionFilesToScan = 36
    private static let sessionTailBytes: UInt64 = 524_288
    private static let sessionTailMaxBytes: UInt64 = 8 * 1_024 * 1_024
    private static let minSessionTailLineCount = 180

    init(
        fileManager: FileManager = .default,
        codexHomePath: String = NSHomeDirectory() + "/.codex"
    ) {
        self.fileManager = fileManager
        self.codexHomePath = codexHomePath
    }

    func start() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        refresh()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    nonisolated deinit {
        // Timer invalidation handled by stop() or natural deallocation.
    }

    func refreshNow() {
        refresh()
    }

    private func refresh() {
        let now = Date()
        let indexURL = URL(fileURLWithPath: codexHomePath, isDirectory: true)
            .appendingPathComponent("session_index.jsonl")
        let sessionsURL = URL(fileURLWithPath: codexHomePath, isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)

        var hasReadableCodexArtifacts = false

        let indexedThreads = loadIndexedThreads(from: indexURL, hasReadableArtifacts: &hasReadableCodexArtifacts)
        let indexedThreadByID = Dictionary(uniqueKeysWithValues: indexedThreads.map { ($0.threadID, $0) })
        let sessionFiles = discoverSessionFiles(in: sessionsURL)
        if !sessionFiles.isEmpty {
            hasReadableCodexArtifacts = true
        }

        var parsedSnapshots: [CodexSessionSnapshot] = []
        parsedSnapshots.reserveCapacity(sessionFiles.count)

        for sessionFile in sessionFiles {
            guard let tailText = readSessionTail(atPath: sessionFile.url.path, fileSize: sessionFile.fileSize) else {
                continue
            }

            let sessionID = resolveThreadID(from: sessionFile.url)
            let fallbackTaskLabel = indexedThreadByID[sessionID]?.threadName ?? ""
            var parsedSnapshot = CodexSessionSnapshotParser.parse(
                tailText,
                sessionID: sessionID,
                fallbackTaskLabel: fallbackTaskLabel
            )

            if parsedSnapshot.updatedAt == nil {
                parsedSnapshot = CodexSessionSnapshotParser.replacing(
                    parsedSnapshot,
                    updatedAt: indexedThreadByID[sessionID]?.updatedAt
                )
            }

            if parsedSnapshot.trustLevel != CodexSnapshotTrustLevel.insufficient
                || parsedSnapshot.hasStructuredTokenSignal
                || !parsedSnapshot.taskLabel.isEmpty
            {
                parsedSnapshots.append(parsedSnapshot)
            }
        }

        let liveSignalSnapshots = parsedSnapshots.filter {
            $0.trustLevel == .eventDerived && hasLiveSignal($0, now: now)
        }
        let displaySnapshots = liveSignalSnapshots.compactMap {
            decaySnapshotForDisplay($0, now: now)
        }
        let hasEventDerivedSignals = parsedSnapshots.contains { $0.trustLevel == .eventDerived }
        let effectiveSnapshots: [CodexSessionSnapshot]
        if liveSignalSnapshots.isEmpty {
            if hasEventDerivedSignals {
                effectiveSnapshots = parsedSnapshots
            } else {
                effectiveSnapshots = indexedThreads.map { CodexSessionSnapshotParser.makeRecentIndexFallback(from: $0) }
            }
        } else {
            effectiveSnapshots = parsedSnapshots
        }

        let availability: AgentAvailability
        if hasReadableCodexArtifacts == false {
            availability = .offline
        } else if liveSignalSnapshots.isEmpty {
            availability = .statusUnavailable
        } else {
            availability = .available
        }

        let candidateThreads: [CodexSessionSnapshot]
        if availability == .available {
            candidateThreads = displaySnapshots.filter { snapshot in
                guard snapshot.trustLevel == .eventDerived else {
                    return false
                }

                switch snapshot.state {
                case .attention, .working, .thinking:
                    return true
                case .idle:
                    return true
                case .offline:
                    return false
                }
            }
        } else {
            if hasEventDerivedSignals {
                candidateThreads = []
            } else {
                candidateThreads = effectiveSnapshots.filter { $0.trustLevel == .recentIndexFallback }
            }
        }

        let sortedThreads = candidateThreads.sorted { lhs, rhs in
            if statePriority(lhs.state) != statePriority(rhs.state) {
                return statePriority(lhs.state) > statePriority(rhs.state)
            }

            if lhs.updatedAt != rhs.updatedAt {
                return (lhs.updatedAt ?? .distantPast) > (rhs.updatedAt ?? .distantPast)
            }

            if trustPriority(lhs.trustLevel) != trustPriority(rhs.trustLevel) {
                return trustPriority(lhs.trustLevel) > trustPriority(rhs.trustLevel)
            }

            return lhs.sessionID < rhs.sessionID
        }

        let visibleThreads = Array(sortedThreads.prefix(Self.maxVisibleThreads)).map { snapshot in
            AgentThread(
                id: snapshot.sessionID,
                taskLabel: snapshot.taskLabel,
                modelLabel: snapshot.modelLabel,
                contextRatio: snapshot.contextRatio,
                state: snapshot.state
            )
        }

        let globalState = resolveGlobalState(
            availability: availability,
            snapshots: displaySnapshots
        )

        let latestQuotaSnapshot = liveSignalSnapshots
            .filter { $0.fiveHourRatio != nil || $0.weeklyRatio != nil }
            .sorted { lhs, rhs in
                (lhs.updatedAt ?? .distantPast) > (rhs.updatedAt ?? .distantPast)
            }
            .first

        let quota: AgentQuota? = availability == .offline ? nil : AgentQuota(
            availability: latestQuotaSnapshot == nil ? .unavailable : .available,
            fiveHourRatio: latestQuotaSnapshot?.fiveHourRatio,
            weeklyRatio: latestQuotaSnapshot?.weeklyRatio
        )

        let newState = AgentState(
            kind: .codex,
            online: availability != .offline,
            availability: availability,
            globalState: globalState,
            threads: visibleThreads,
            quota: quota
        )

        if codexState != newState {
            codexState = newState
        }
    }

    private func loadIndexedThreads(
        from indexURL: URL,
        hasReadableArtifacts: inout Bool
    ) -> [CodexIndexedThread] {
        guard let data = fileManager.contents(atPath: indexURL.path),
              let text = String(data: data, encoding: .utf8)
        else {
            return []
        }

        hasReadableArtifacts = true
        return CodexSessionIndexParser.parse(text)
    }

    private struct SessionFileCandidate {
        let url: URL
        let modifiedAt: Date
        let fileSize: UInt64
    }

    private func discoverSessionFiles(in sessionsDirectoryURL: URL) -> [SessionFileCandidate] {
        guard
            let enumerator = fileManager.enumerator(
                at: sessionsDirectoryURL,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }

        var files: [SessionFileCandidate] = []
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

            let fileSize = UInt64(values.fileSize ?? 0)
            files.append(
                SessionFileCandidate(
                    url: url,
                    modifiedAt: values.contentModificationDate ?? .distantPast,
                    fileSize: fileSize
                )
            )
        }

        files.sort { lhs, rhs in
            if lhs.modifiedAt != rhs.modifiedAt {
                return lhs.modifiedAt > rhs.modifiedAt
            }
            return lhs.url.path < rhs.url.path
        }

        return Array(files.prefix(Self.maxSessionFilesToScan))
    }

    private func readSessionTail(atPath path: String, fileSize: UInt64) -> String? {
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

        let maxWindow = min(resolvedFileSize, Self.sessionTailMaxBytes)
        var window = min(Self.sessionTailBytes, maxWindow)
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
            let reachedMaxWindow = window >= maxWindow

            if lineCount >= Self.minSessionTailLineCount || reachedStart || reachedMaxWindow {
                return bestText
            }

            let grownWindow = min(window * 2, maxWindow)
            if grownWindow == window {
                return bestText
            }
            window = grownWindow
        }
    }

    private func resolveThreadID(from sessionFileURL: URL) -> String {
        let filename = sessionFileURL.deletingPathExtension().lastPathComponent
        let pattern = #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#
        if let range = filename.range(of: pattern, options: .regularExpression) {
            return String(filename[range]).lowercased()
        }
        return filename
    }

    private func resolveGlobalState(
        availability: AgentAvailability,
        snapshots: [CodexSessionSnapshot]
    ) -> AgentGlobalState {
        if availability == .offline {
            return .offline
        }

        if availability == .statusUnavailable {
            return .idle
        }

        let eventDerivedStates = snapshots
            .filter { $0.trustLevel == .eventDerived }
            .map(\.state)

        if eventDerivedStates.contains(.attention) {
            return .attention
        }

        if eventDerivedStates.contains(.working) {
            return .working
        }

        if eventDerivedStates.contains(.thinking) {
            return .thinking
        }

        return .idle
    }

    private enum ActivityDecayStage {
        case live
        case cooling
        case recentIdle
        case staleHidden
        case expired
    }

    private func decayStage(
        _ snapshot: CodexSessionSnapshot,
        now: Date
    ) -> ActivityDecayStage {
        guard let updatedAt = snapshot.updatedAt else {
            return .expired
        }

        let age = max(0, now.timeIntervalSince(updatedAt))
        if age <= Self.activeStateWindow {
            return .live
        }
        if age <= Self.coolingIdleWindow {
            return .cooling
        }
        if age <= Self.visibleIdleWindow {
            return .recentIdle
        }
        if age <= Self.liveSignalWindow {
            return .staleHidden
        }
        return .expired
    }

    private func hasLiveSignal(
        _ snapshot: CodexSessionSnapshot,
        now: Date
    ) -> Bool {
        switch decayStage(snapshot, now: now) {
        case .live, .cooling, .recentIdle, .staleHidden:
            return true
        case .expired:
            return false
        }
    }

    private func decaySnapshotForDisplay(
        _ snapshot: CodexSessionSnapshot,
        now: Date
    ) -> CodexSessionSnapshot? {
        switch decayStage(snapshot, now: now) {
        case .live:
            return snapshot
        case .cooling, .recentIdle:
            if snapshot.state == .idle {
                return snapshot
            }
            return CodexSessionSnapshot(
                sessionID: snapshot.sessionID,
                taskLabel: snapshot.taskLabel,
                modelLabel: snapshot.modelLabel,
                contextRatio: snapshot.contextRatio,
                fiveHourRatio: snapshot.fiveHourRatio,
                weeklyRatio: snapshot.weeklyRatio,
                state: .idle,
                updatedAt: snapshot.updatedAt,
                trustLevel: snapshot.trustLevel,
                hasStructuredTokenSignal: snapshot.hasStructuredTokenSignal,
                hasStructuredActivitySignal: snapshot.hasStructuredActivitySignal
            )
        case .staleHidden, .expired:
            return nil
        }
    }

    private func statePriority(_ state: AgentGlobalState) -> Int {
        switch state {
        case .attention:
            return 4
        case .working:
            return 3
        case .thinking:
            return 2
        case .idle:
            return 1
        case .offline:
            return 0
        }
    }

    private func trustPriority(_ trustLevel: CodexSnapshotTrustLevel) -> Int {
        switch trustLevel {
        case .eventDerived:
            return 3
        case .recentIndexFallback:
            return 2
        case .insufficient:
            return 1
        }
    }
}
