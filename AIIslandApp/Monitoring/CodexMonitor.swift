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
    private var lastKnownModels: [String: CodexCachedModel] = [:]
    private var refreshInFlight = false
    private var refreshDirty = false
    private var coalescedTrigger = "event"
    private var refreshGeneration: UInt64 = 0
    private var activeRefreshGeneration: UInt64 = 0
    private var isRunning = false
    private let workerQueue = DispatchQueue(label: "com.aiisland.monitor.codex.worker", qos: .utility)

    private struct FileManagerHandle: @unchecked Sendable {
        let value: FileManager
    }

    private struct RefreshComputation: Sendable {
        let state: AgentState
        let diagnostics: AgentMonitorDiagnostics
        let watchedPaths: [String]
        let updatedModels: [String: CodexCachedModel]
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
            paths: CodexSessionCatalog.baseWatchedPaths(codexHomePath: codexHomePath)
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
        cachedModels: [String: CodexCachedModel],
        trigger: String
    ) -> RefreshComputation {
        let now = Date()
        let indexURL = URL(fileURLWithPath: codexHomePath, isDirectory: true)
            .appendingPathComponent("session_index.jsonl")
        let sessionsURL = URL(fileURLWithPath: codexHomePath, isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)

        var hasReadableCodexArtifacts = false
        let indexedThreads = loadIndexedThreads(
            fileManager: fileManager,
            from: indexURL,
            hasReadableArtifacts: &hasReadableCodexArtifacts
        )
        let indexedThreadByID = Dictionary(uniqueKeysWithValues: indexedThreads.map { ($0.threadID, $0) })

        let sessionFiles = CodexSessionCatalog.discoverSessionFiles(
            fileManager: fileManager,
            sessionsDirectoryURL: sessionsURL,
            maxFiles: CodexSessionCatalog.defaultMaxFilesToScan
        )
        if !sessionFiles.isEmpty {
            hasReadableCodexArtifacts = true
        }

        var parsedSnapshots: [CodexSessionSnapshot] = []
        parsedSnapshots.reserveCapacity(sessionFiles.count)

        for sessionFile in sessionFiles {
            guard let tailText = CodexSessionTailReader.readTail(
                atPath: sessionFile.url.path,
                fileSize: sessionFile.fileSize,
                initialWindow: CodexSessionTailReader.defaultInitialWindow,
                maxWindow: CodexSessionTailReader.defaultMaxWindow,
                minimumLineCount: CodexSessionTailReader.defaultMinimumLineCount
            ) else {
                continue
            }

            let fallbackTaskLabel = indexedThreadByID[sessionFile.threadID]?.threadName ?? ""
            var snapshot = CodexSessionSnapshotParser.parse(
                tailText,
                sessionID: sessionFile.threadID,
                fallbackTaskLabel: fallbackTaskLabel
            )

            if snapshot.updatedAt == nil {
                snapshot = CodexSessionSnapshotParser.replacing(
                    snapshot,
                    updatedAt: indexedThreadByID[sessionFile.threadID]?.updatedAt
                )
            }

            if snapshot.trustLevel != .insufficient
                || snapshot.hasStructuredTokenSignal
                || !snapshot.taskLabel.isEmpty
            {
                parsedSnapshots.append(snapshot)
            }
        }

        let arbitration = CodexMonitorArbitrator.compute(
            indexedThreads: indexedThreads,
            parsedSnapshots: parsedSnapshots,
            hasReadableArtifacts: hasReadableCodexArtifacts,
            cachedModels: cachedModels,
            freshnessPolicy: freshnessPolicy,
            now: now,
            trigger: trigger
        )

        return RefreshComputation(
            state: arbitration.state,
            diagnostics: arbitration.diagnostics,
            watchedPaths: CodexSessionCatalog.watchedPaths(
                codexHomePath: codexHomePath,
                sessionFiles: sessionFiles
            ),
            updatedModels: arbitration.updatedModels
        )
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
}
