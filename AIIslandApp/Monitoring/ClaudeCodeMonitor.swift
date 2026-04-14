import Foundation

import AIIslandCore

@MainActor
final class ClaudeCodeMonitor: ObservableObject {
    @Published private(set) var claudeState: AgentState = AgentState(
        kind: .claude,
        online: false,
        availability: .offline,
        globalState: .offline,
        threads: [],
        quota: nil
    )
    @Published private(set) var diagnostics: AgentMonitorDiagnostics

    private let fileManagerHandle: FileManagerHandle
    private let sessionsDirPath: String
    private let projectsDirPath: String
    private let temporaryDirectoryPath: String
    private let processAliveChecker: @Sendable (Int32) -> Bool
    private let freshnessPolicy: MonitorFreshnessPolicy
    private let keepAlivePollInterval: TimeInterval
    private let eventDebounceInterval: TimeInterval
    private let injectedSignalSource: RealtimeSignalSource?

    private var pollTimer: Timer?
    private var signalSource: RealtimeSignalSource?
    private var pendingRefreshWorkItem: DispatchWorkItem?
    private var lastRefreshAt: Date = .distantPast
    private var lastKnownModels: [String: ClaudeCachedModel] = [:]
    private var refreshInFlight = false
    private var refreshDirty = false
    private var coalescedTrigger = "event"
    private var refreshGeneration: UInt64 = 0
    private var activeRefreshGeneration: UInt64 = 0
    private var isRunning = false
    private let workerQueue = DispatchQueue(label: "com.aiisland.monitor.claude.worker", qos: .utility)

    private nonisolated static let claudeDir: String = {
        NSHomeDirectory() + "/.claude"
    }()

    private nonisolated static let transcriptTailBytes: UInt64 = 262_144

    private struct FileManagerHandle: @unchecked Sendable {
        let value: FileManager
    }

    private struct RefreshComputation: Sendable {
        let state: AgentState
        let diagnostics: AgentMonitorDiagnostics
        let watchedPaths: [String]
        let updatedModels: [String: ClaudeCachedModel]
    }

    init(
        fileManager: FileManager = .default,
        claudeDirPath: String = ClaudeCodeMonitor.claudeDir,
        temporaryDirectoryPath: String = NSTemporaryDirectory(),
        processAliveChecker: @escaping @Sendable (Int32) -> Bool = { kill($0, 0) == 0 },
        freshnessPolicy: MonitorFreshnessPolicy = .v02Smooth,
        keepAlivePollInterval: TimeInterval = 2.0,
        eventDebounceInterval: TimeInterval = 0.15,
        signalSource: RealtimeSignalSource? = nil
    ) {
        fileManagerHandle = FileManagerHandle(value: fileManager)
        sessionsDirPath = claudeDirPath + "/sessions"
        projectsDirPath = claudeDirPath + "/projects"
        self.temporaryDirectoryPath = temporaryDirectoryPath
        self.processAliveChecker = processAliveChecker
        self.freshnessPolicy = freshnessPolicy
        self.keepAlivePollInterval = keepAlivePollInterval
        self.eventDebounceInterval = eventDebounceInterval
        injectedSignalSource = signalSource
        diagnostics = .empty(
            kind: .claude,
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
            sessionsDirPath: sessionsDirPath,
            projectsDirPath: projectsDirPath,
            temporaryDirectoryPath: temporaryDirectoryPath,
            processAliveChecker: processAliveChecker,
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

        let source = injectedSignalSource ?? VnodeRealtimeSignalSource(paths: baseWatchedPaths())
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
        let sessionsDirPath = self.sessionsDirPath
        let projectsDirPath = self.projectsDirPath
        let temporaryDirectoryPath = self.temporaryDirectoryPath
        let processAliveChecker = self.processAliveChecker
        let freshnessPolicy = self.freshnessPolicy
        let cachedModels = self.lastKnownModels

        workerQueue.async { [weak self] in
            let result = Self.computeRefresh(
                fileManager: fileManagerHandle.value,
                sessionsDirPath: sessionsDirPath,
                projectsDirPath: projectsDirPath,
                temporaryDirectoryPath: temporaryDirectoryPath,
                processAliveChecker: processAliveChecker,
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
        if claudeState != result.state {
            claudeState = result.state
        }
        diagnostics = result.diagnostics
        lastKnownModels = result.updatedModels
        signalSource?.updateWatchedPaths(result.watchedPaths)
    }

    private func baseWatchedPaths() -> [String] {
        [
            sessionsDirPath,
            projectsDirPath,
            temporaryDirectoryPath,
        ]
    }

    private nonisolated static func computeRefresh(
        fileManager: FileManager,
        sessionsDirPath: String,
        projectsDirPath: String,
        temporaryDirectoryPath: String,
        processAliveChecker: @Sendable (Int32) -> Bool,
        freshnessPolicy: MonitorFreshnessPolicy,
        cachedModels: [String: ClaudeCachedModel],
        trigger: String
    ) -> RefreshComputation {
        let candidates = ClaudeSessionCatalog.loadCandidates(
            fileManager: fileManager,
            sessionsDirPath: sessionsDirPath
        )
        let liveCandidates = candidates.filter { processAliveChecker($0.pid) }

        let snapshots = liveCandidates.map { candidate in
            let transcriptPath = resolveJsonlPath(
                fileManager: fileManager,
                sessionID: candidate.sessionID,
                cwd: candidate.cwd,
                projectsDirPath: projectsDirPath
            )

            return ClaudeMonitorSessionSnapshot(
                candidate: candidate,
                transcript: parseTranscriptTail(path: transcriptPath),
                transcriptUpdatedAt: fileModificationDate(
                    fileManager: fileManager,
                    atPath: transcriptPath
                ),
                transcriptPath: transcriptPath,
                bridge: readBridgeFile(
                    fileManager: fileManager,
                    sessionID: candidate.sessionID,
                    temporaryDirectoryPath: temporaryDirectoryPath
                )
            )
        }

        let result = ClaudeMonitorArbitrator.compute(
            snapshots: snapshots,
            baseWatchedPaths: [
                sessionsDirPath,
                projectsDirPath,
                temporaryDirectoryPath,
            ],
            cachedModels: cachedModels,
            freshnessPolicy: freshnessPolicy,
            now: Date(),
            trigger: trigger
        )

        return RefreshComputation(
            state: result.state,
            diagnostics: result.diagnostics,
            watchedPaths: result.watchedPaths,
            updatedModels: result.updatedModels
        )
    }

    private nonisolated static func resolveJsonlPath(
        fileManager: FileManager,
        sessionID: String,
        cwd: String,
        projectsDirPath: String
    ) -> String? {
        let encodedCwd = encodeCwd(cwd)
        let directPath = projectsDirPath + "/" + encodedCwd + "/" + sessionID + ".jsonl"
        if fileManager.fileExists(atPath: directPath) {
            return directPath
        }

        guard let projectDirs = try? fileManager.contentsOfDirectory(atPath: projectsDirPath) else {
            return nil
        }

        for dir in projectDirs {
            let candidate = projectsDirPath + "/" + dir + "/" + sessionID + ".jsonl"
            if fileManager.fileExists(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    /// Encode a cwd path the same way Claude Code does:
    /// "/Users/foo/bar" -> "-Users-foo-bar"
    private nonisolated static func encodeCwd(_ cwd: String) -> String {
        cwd.replacingOccurrences(of: "/", with: "-")
    }

    private nonisolated static func parseTranscriptTail(path: String?) -> ClaudeCodeTranscriptSnapshot {
        guard let path,
              let handle = FileHandle(forReadingAtPath: path)
        else {
            return ClaudeCodeTranscriptSnapshot(
                fallbackState: .idle,
                modelLabel: nil,
                taskSummary: nil,
                hasInProgressToolUse: false
            )
        }
        defer { try? handle.close() }

        guard let fileSize = try? handle.seekToEnd(), fileSize > 0 else {
            return ClaudeCodeTranscriptSnapshot(
                fallbackState: .idle,
                modelLabel: nil,
                taskSummary: nil,
                hasInProgressToolUse: false
            )
        }

        let offset = fileSize > Self.transcriptTailBytes ? fileSize - Self.transcriptTailBytes : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8)
        else {
            return ClaudeCodeTranscriptSnapshot(
                fallbackState: .idle,
                modelLabel: nil,
                taskSummary: nil,
                hasInProgressToolUse: false
            )
        }

        let normalizedTail: String
        if offset > 0, let newline = text.firstIndex(of: "\n") {
            normalizedTail = String(text[text.index(after: newline)...])
        } else {
            normalizedTail = text
        }

        return ClaudeCodeSnapshotParser.parseTranscriptTail(normalizedTail)
    }

    private nonisolated static func readBridgeFile(
        fileManager: FileManager,
        sessionID: String,
        temporaryDirectoryPath: String
    ) -> ClaudeBridgeSnapshot? {
        let bridgePath = URL(fileURLWithPath: temporaryDirectoryPath, isDirectory: true)
            .appendingPathComponent("claude-ctx-" + sessionID + ".json")
            .path

        guard let data = fileManager.contents(atPath: bridgePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let observedAt = fileModificationDate(fileManager: fileManager, atPath: bridgePath)
        let contextRatio: Double? = (json["used_pct"] as? Int)
            .map { min(Double($0) / 100.0, 1.0) }

        return ClaudeBridgeSnapshot(
            contextRatio: contextRatio,
            observedAt: observedAt,
            filePath: bridgePath
        )
    }

    private nonisolated static func fileModificationDate(
        fileManager: FileManager,
        atPath path: String?
    ) -> Date? {
        guard let path,
              let attrs = try? fileManager.attributesOfItem(atPath: path)
        else {
            return nil
        }
        return attrs[.modificationDate] as? Date
    }
}
