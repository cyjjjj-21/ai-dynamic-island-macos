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
    @Published private(set) var diagnostics: AgentMonitorDiagnostics

    private let fileManagerHandle: FileManagerHandle
    private let codexHomePath: String
    private let freshnessPolicy: MonitorFreshnessPolicy
    private let keepAlivePollInterval: TimeInterval
    private let eventDebounceInterval: TimeInterval
    private let injectedSignalSource: RealtimeSignalSource?

    private var pollTimer: Timer?
    private var signalSource: RealtimeSignalSource?
    private var pendingRefreshWorkItem: DispatchWorkItem?
    private var lastRefreshAt: Date = .distantPast
    private var lastKnownModels: [String: CachedModel] = [:]
    private var refreshInFlight = false
    private var refreshDirty = false
    private var coalescedTrigger = "event"
    private var refreshGeneration: UInt64 = 0
    private var activeRefreshGeneration: UInt64 = 0
    private var isRunning = false
    private let workerQueue = DispatchQueue(label: "com.aiisland.monitor.codex.worker", qos: .utility)

    private nonisolated static let maxVisibleThreads = 3
    private nonisolated static let maxSessionFilesToScan = 36
    private nonisolated static let sessionTailBytes: UInt64 = 524_288
    private nonisolated static let sessionTailMaxBytes: UInt64 = 8 * 1_024 * 1_024
    private nonisolated static let minSessionTailLineCount = 180

    private struct CachedModel: Sendable {
        let label: String
        let updatedAt: Date
    }

    private struct FileManagerHandle: @unchecked Sendable {
        let value: FileManager
    }

    private struct RefreshComputation: Sendable {
        let state: AgentState
        let diagnostics: AgentMonitorDiagnostics
        let watchedPaths: [String]
        let updatedModels: [String: CachedModel]
    }

    init(
        fileManager: FileManager = .default,
        codexHomePath: String = NSHomeDirectory() + "/.codex",
        freshnessPolicy: MonitorFreshnessPolicy = .v02Smooth,
        keepAlivePollInterval: TimeInterval = 2.0,
        eventDebounceInterval: TimeInterval = 0.15,
        signalSource: RealtimeSignalSource? = nil
    ) {
        fileManagerHandle = FileManagerHandle(value: fileManager)
        self.codexHomePath = codexHomePath
        self.freshnessPolicy = freshnessPolicy
        self.keepAlivePollInterval = keepAlivePollInterval
        self.eventDebounceInterval = eventDebounceInterval
        injectedSignalSource = signalSource
        diagnostics = .empty(
            kind: .codex,
            freshnessPolicy: freshnessPolicy,
            triggerMode: "event+poll"
        )
    }

    func start() {
        isRunning = true
        configureSignalSourceIfNeeded()

        let timer = Timer(timeInterval: keepAlivePollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleRefresh(trigger: "poll")
            }
        }
        timer.tolerance = keepAlivePollInterval * 0.25
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        scheduleRefresh(trigger: "startup")
    }

    func stop() {
        isRunning = false
        pendingRefreshWorkItem?.cancel()
        pendingRefreshWorkItem = nil
        refreshDirty = false
        refreshInFlight = false
        refreshGeneration &+= 1
        activeRefreshGeneration = refreshGeneration

        pollTimer?.invalidate()
        pollTimer = nil

        signalSource?.stop()
        signalSource = nil
    }

    nonisolated deinit {
        // Timer and signal source are cleaned up from stop().
    }

    func refreshNow() {
        refreshGeneration &+= 1
        activeRefreshGeneration = refreshGeneration
        let result = Self.computeRefresh(
            fileManager: fileManagerHandle.value,
            codexHomePath: codexHomePath,
            freshnessPolicy: freshnessPolicy,
            cachedModels: lastKnownModels,
            trigger: "manual"
        )
        applyComputation(result)
    }

    private func scheduleRefresh(trigger: String) {
        guard isRunning else {
            return
        }

        let now = Date()
        let age = now.timeIntervalSince(lastRefreshAt)
        if age >= eventDebounceInterval {
            requestRefresh(trigger: trigger)
            return
        }

        pendingRefreshWorkItem?.cancel()
        let delay = max(0.01, eventDebounceInterval - age)
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.requestRefresh(trigger: trigger)
            }
        }
        pendingRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func configureSignalSourceIfNeeded() {
        if signalSource != nil {
            return
        }

        let source = injectedSignalSource ?? VnodeRealtimeSignalSource(
            paths: Self.baseWatchedPaths(codexHomePath: codexHomePath)
        )
        source.onSignal = { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleRefresh(trigger: "event")
            }
        }
        source.start()
        signalSource = source
    }

    private func requestRefresh(trigger: String) {
        guard isRunning else {
            return
        }

        if refreshInFlight {
            refreshDirty = true
            coalescedTrigger = trigger
            return
        }

        launchRefresh(trigger: trigger)
    }

    private func launchRefresh(trigger: String) {
        guard isRunning else {
            return
        }

        pendingRefreshWorkItem?.cancel()
        pendingRefreshWorkItem = nil
        lastRefreshAt = Date()
        refreshGeneration &+= 1
        let generation = refreshGeneration
        activeRefreshGeneration = generation
        refreshInFlight = true
        refreshDirty = false

        let fileManagerHandle = self.fileManagerHandle
        let codexHomePath = self.codexHomePath
        let freshnessPolicy = self.freshnessPolicy
        let cachedModels = self.lastKnownModels

        workerQueue.async { [weak self] in
            let result = Self.computeRefresh(
                fileManager: fileManagerHandle.value,
                codexHomePath: codexHomePath,
                freshnessPolicy: freshnessPolicy,
                cachedModels: cachedModels,
                trigger: trigger
            )
            Task { @MainActor [weak self] in
                self?.finishRefresh(result: result, generation: generation)
            }
        }
    }

    private func finishRefresh(result: RefreshComputation, generation: UInt64) {
        guard isRunning else {
            return
        }
        guard generation == activeRefreshGeneration else {
            return
        }

        applyComputation(result)
        refreshInFlight = false

        if refreshDirty {
            refreshDirty = false
            launchRefresh(trigger: coalescedTrigger)
        }
    }

    private func applyComputation(_ result: RefreshComputation) {
        if codexState != result.state {
            codexState = result.state
        }
        diagnostics = result.diagnostics
        lastKnownModels = result.updatedModels
        signalSource?.updateWatchedPaths(result.watchedPaths)
    }

    private nonisolated static func computeRefresh(
        fileManager: FileManager,
        codexHomePath: String,
        freshnessPolicy: MonitorFreshnessPolicy,
        cachedModels: [String: CachedModel],
        trigger: String
    ) -> RefreshComputation {
        let now = Date()
        let indexURL = URL(fileURLWithPath: codexHomePath, isDirectory: true)
            .appendingPathComponent("session_index.jsonl")
        let sessionsURL = URL(fileURLWithPath: codexHomePath, isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)

        var mutableModels = cachedModels
        var hasReadableCodexArtifacts = false
        let indexedThreads = loadIndexedThreads(
            fileManager: fileManager,
            from: indexURL,
            hasReadableArtifacts: &hasReadableCodexArtifacts
        )
        let indexedThreadByID = Dictionary(uniqueKeysWithValues: indexedThreads.map { ($0.threadID, $0) })
        let sessionFiles = discoverSessionFiles(fileManager: fileManager, in: sessionsURL)
        if !sessionFiles.isEmpty {
            hasReadableCodexArtifacts = true
        }
        let watchedPaths = watchedPaths(codexHomePath: codexHomePath, sessionFiles: sessionFiles)

        var parsedSnapshots: [CodexSessionSnapshot] = []
        parsedSnapshots.reserveCapacity(sessionFiles.count)

        for sessionFile in sessionFiles {
            guard let tailText = readSessionTail(atPath: sessionFile.url.path, fileSize: sessionFile.fileSize) else {
                continue
            }

            let sessionID = resolveThreadID(from: sessionFile.url)
            let fallbackTaskLabel = indexedThreadByID[sessionID]?.threadName ?? ""
            var snapshot = CodexSessionSnapshotParser.parse(
                tailText,
                sessionID: sessionID,
                fallbackTaskLabel: fallbackTaskLabel
            )

            if snapshot.updatedAt == nil {
                snapshot = CodexSessionSnapshotParser.replacing(
                    snapshot,
                    updatedAt: indexedThreadByID[sessionID]?.updatedAt
                )
            }

            snapshot = applyModelCache(
                to: snapshot,
                now: now,
                freshnessPolicy: freshnessPolicy,
                knownModels: &mutableModels
            )

            if snapshot.trustLevel != .insufficient
                || snapshot.hasStructuredTokenSignal
                || !snapshot.taskLabel.isEmpty
            {
                parsedSnapshots.append(snapshot)
            }
        }

        let liveSignalSnapshots = parsedSnapshots.filter {
            freshnessPolicy.stage(lastSignalAt: $0.updatedAt, now: now) != .expired
                && $0.trustLevel == .eventDerived
        }

        let displaySnapshots = liveSignalSnapshots.compactMap {
            decaySnapshotForDisplay($0, now: now, freshnessPolicy: freshnessPolicy)
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
        if !hasReadableCodexArtifacts {
            availability = .offline
        } else if liveSignalSnapshots.isEmpty {
            availability = .statusUnavailable
        } else {
            availability = .available
        }

        let candidateThreads: [CodexSessionSnapshot]
        if availability == .available {
            candidateThreads = displaySnapshots.filter { $0.trustLevel == .eventDerived }
        } else if hasEventDerivedSignals {
            candidateThreads = []
        } else {
            candidateThreads = effectiveSnapshots.filter { $0.trustLevel == .recentIndexFallback }
        }

        let sortedThreads = candidateThreads.sorted { lhs, rhs in
            if statePriority(lhs.state) != statePriority(rhs.state) {
                return statePriority(lhs.state) > statePriority(rhs.state)
            }

            let lhsScore = freshnessPolicy.freshnessScore(lastSignalAt: lhs.updatedAt, now: now)
            let rhsScore = freshnessPolicy.freshnessScore(lastSignalAt: rhs.updatedAt, now: now)
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
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
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
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

        let newDiagnostics = AgentMonitorDiagnostics(
            kind: .codex,
            refreshedAt: now,
            freshnessPolicy: freshnessPolicy,
            triggerMode: "event+poll/\(trigger)",
            threads: parsedSnapshots
                .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
                .prefix(4)
                .map { snapshot in
                    MonitorThreadDiagnostics(
                        id: snapshot.sessionID,
                        lastSignalAt: snapshot.updatedAt,
                        stage: freshnessPolicy.stage(lastSignalAt: snapshot.updatedAt, now: now),
                        sourceHits: sourceHits(for: snapshot)
                    )
                }
        )

        return RefreshComputation(
            state: newState,
            diagnostics: newDiagnostics,
            watchedPaths: watchedPaths,
            updatedModels: mutableModels
        )
    }

    private nonisolated static func baseWatchedPaths(codexHomePath: String) -> [String] {
        [
            codexHomePath,
            codexHomePath + "/session_index.jsonl",
            codexHomePath + "/sessions",
        ]
    }

    private nonisolated static func watchedPaths(
        codexHomePath: String,
        sessionFiles: [SessionFileCandidate]
    ) -> [String] {
        var paths = baseWatchedPaths(codexHomePath: codexHomePath)
        let parentDirs = sessionFiles.map { $0.url.deletingLastPathComponent().path }
        paths.append(contentsOf: parentDirs)
        return paths
    }

    private nonisolated static func loadIndexedThreads(
        fileManager: FileManager,
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

    private struct SessionFileCandidate: Sendable {
        let url: URL
        let modifiedAt: Date
        let fileSize: UInt64
    }

    private nonisolated static func discoverSessionFiles(
        fileManager: FileManager,
        in sessionsDirectoryURL: URL
    ) -> [SessionFileCandidate] {
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

    private nonisolated static func readSessionTail(atPath path: String, fileSize: UInt64) -> String? {
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

    private nonisolated static func resolveThreadID(from sessionFileURL: URL) -> String {
        let filename = sessionFileURL.deletingPathExtension().lastPathComponent
        let pattern = #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#
        if let range = filename.range(of: pattern, options: .regularExpression) {
            return String(filename[range]).lowercased()
        }
        return filename
    }

    private nonisolated static func resolveGlobalState(
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

    private nonisolated static func decaySnapshotForDisplay(
        _ snapshot: CodexSessionSnapshot,
        now: Date,
        freshnessPolicy: MonitorFreshnessPolicy
    ) -> CodexSessionSnapshot? {
        switch freshnessPolicy.stage(lastSignalAt: snapshot.updatedAt, now: now) {
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

    private nonisolated static func applyModelCache(
        to snapshot: CodexSessionSnapshot,
        now: Date,
        freshnessPolicy: MonitorFreshnessPolicy,
        knownModels: inout [String: CachedModel]
    ) -> CodexSessionSnapshot {
        let cacheWindow = freshnessPolicy.visibleIdleWindow

        if !snapshot.modelLabel.isEmpty {
            knownModels[snapshot.sessionID] = CachedModel(
                label: snapshot.modelLabel,
                updatedAt: snapshot.updatedAt ?? now
            )
            return snapshot
        }

        guard let cached = knownModels[snapshot.sessionID] else {
            return snapshot
        }

        if now.timeIntervalSince(cached.updatedAt) > cacheWindow {
            knownModels.removeValue(forKey: snapshot.sessionID)
            return snapshot
        }

        return CodexSessionSnapshot(
            sessionID: snapshot.sessionID,
            taskLabel: snapshot.taskLabel,
            modelLabel: cached.label,
            contextRatio: snapshot.contextRatio,
            fiveHourRatio: snapshot.fiveHourRatio,
            weeklyRatio: snapshot.weeklyRatio,
            state: snapshot.state,
            updatedAt: snapshot.updatedAt,
            trustLevel: snapshot.trustLevel,
            hasStructuredTokenSignal: snapshot.hasStructuredTokenSignal,
            hasStructuredActivitySignal: snapshot.hasStructuredActivitySignal
        )
    }

    private nonisolated static func sourceHits(for snapshot: CodexSessionSnapshot) -> [String] {
        var hits: [String] = []
        if snapshot.trustLevel == .recentIndexFallback {
            hits.append("index")
        }
        if snapshot.hasStructuredActivitySignal {
            hits.append("activity")
        }
        if snapshot.hasStructuredTokenSignal {
            hits.append("token")
        }
        if !snapshot.modelLabel.isEmpty {
            hits.append("model")
        }
        if hits.isEmpty {
            hits.append("none")
        }
        return hits
    }

    private nonisolated static func statePriority(_ state: AgentGlobalState) -> Int {
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

    private nonisolated static func trustPriority(_ trustLevel: CodexSnapshotTrustLevel) -> Int {
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
