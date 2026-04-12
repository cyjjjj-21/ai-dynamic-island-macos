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

    private var pollTimer: Timer?
    private var cachedSessionId: String?
    private var cachedJsonlPath: String?
    private let fileManager: FileManager
    private let sessionsDirPath: String
    private let projectsDirPath: String
    private let temporaryDirectoryPath: String
    private let processAliveChecker: (Int32) -> Bool
    private let freshnessPolicy: MonitorFreshnessPolicy
    private let keepAlivePollInterval: TimeInterval
    private let eventDebounceInterval: TimeInterval
    private let injectedSignalSource: RealtimeSignalSource?

    private var signalSource: RealtimeSignalSource?
    private var pendingRefreshWorkItem: DispatchWorkItem?
    private var lastRefreshAt: Date = .distantPast
    private var lastKnownModels: [String: CachedModel] = [:]

    private static let claudeDir: String = {
        NSHomeDirectory() + "/.claude"
    }()

    private static let transcriptTailBytes: UInt64 = 262_144

    private struct CachedModel {
        let label: String
        let updatedAt: Date
    }

    init(
        fileManager: FileManager = .default,
        claudeDirPath: String = ClaudeCodeMonitor.claudeDir,
        temporaryDirectoryPath: String = NSTemporaryDirectory(),
        processAliveChecker: @escaping (Int32) -> Bool = { kill($0, 0) == 0 },
        freshnessPolicy: MonitorFreshnessPolicy = .v02Smooth,
        keepAlivePollInterval: TimeInterval = 2.0,
        eventDebounceInterval: TimeInterval = 0.15,
        signalSource: RealtimeSignalSource? = nil
    ) {
        self.fileManager = fileManager
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
        configureSignalSourceIfNeeded()

        pollTimer = Timer.scheduledTimer(withTimeInterval: keepAlivePollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleRefresh(trigger: "poll")
            }
        }
        scheduleRefresh(trigger: "startup")
    }

    func stop() {
        pendingRefreshWorkItem?.cancel()
        pendingRefreshWorkItem = nil

        pollTimer?.invalidate()
        pollTimer = nil

        signalSource?.stop()
        signalSource = nil
    }

    nonisolated deinit {
        // Timer and signal source are cleaned up from stop().
    }

    func refreshNow() {
        refresh(trigger: "manual")
    }

    private func scheduleRefresh(trigger: String) {
        let now = Date()
        let age = now.timeIntervalSince(lastRefreshAt)
        if age >= eventDebounceInterval {
            refresh(trigger: trigger)
            return
        }

        pendingRefreshWorkItem?.cancel()
        let delay = max(0.01, eventDebounceInterval - age)
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.refresh(trigger: trigger)
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

    private func refresh(trigger: String) {
        pendingRefreshWorkItem?.cancel()
        pendingRefreshWorkItem = nil
        lastRefreshAt = Date()
        let now = Date()

        guard let session = findActiveSession() else {
            transitionToOffline(now: now, trigger: trigger)
            return
        }

        guard isProcessAlive(pid: session.pid) else {
            transitionToOffline(now: now, trigger: trigger)
            return
        }

        let jsonlPath = resolveJsonlPath(sessionId: session.sessionId, cwd: session.cwd)
        let transcript = parseTranscriptTail(path: jsonlPath)
        let transcriptUpdatedAt = fileModificationDate(atPath: jsonlPath)
        let taskLabel = ClaudeCodeSnapshotParser.resolveTaskLabel(
            activity: session.activity,
            transcript: transcript,
            cwd: session.cwd
        )

        let bridge = readBridgeFile(sessionId: session.sessionId)
        let rawState = ClaudeCodeSnapshotParser.resolveGlobalState(
            activity: session.activity,
            transcript: transcript
        )

        let lastSignalAt = [session.observedAt, transcriptUpdatedAt, bridge?.observedAt]
            .compactMap { $0 }
            .max()
        let stage = freshnessPolicy.stage(lastSignalAt: lastSignalAt, now: now)
        let availability: AgentAvailability = stage == .expired ? .statusUnavailable : .available
        let state = decayState(rawState, stage: stage)
        let contextRatio = bridge?.contextRatio

        signalSource?.updateWatchedPaths(
            watchedPaths(
                sessionPath: session.filePath,
                transcriptPath: jsonlPath,
                bridgePath: bridge?.filePath
            )
        )

        let resolvedModelLabel = resolveModelLabel(
            sessionId: session.sessionId,
            rawModel: ClaudeCodeSnapshotParser.resolveModelLabel(transcript: transcript),
            lastSignalAt: lastSignalAt,
            now: now
        )

        let shouldRenderThread = ClaudeCodeSnapshotParser.shouldRenderThread(
            activity: session.activity,
            transcript: transcript,
            state: state
        ) && shouldRenderThread(for: stage)

        let newState = AgentState(
            kind: .claude,
            online: true,
            availability: availability,
            globalState: state,
            threads: shouldRenderThread ? [
                AgentThread(
                    id: session.sessionId,
                    taskLabel: taskLabel,
                    modelLabel: resolvedModelLabel,
                    contextRatio: contextRatio,
                    state: state
                )
            ] : [],
            quota: nil
        )

        if newState != claudeState {
            claudeState = newState
        }

        diagnostics = AgentMonitorDiagnostics(
            kind: .claude,
            refreshedAt: now,
            freshnessPolicy: freshnessPolicy,
            triggerMode: "event+poll/\(trigger)",
            threads: [
                MonitorThreadDiagnostics(
                    id: session.sessionId,
                    lastSignalAt: lastSignalAt,
                    stage: stage,
                    sourceHits: sourceHits(
                        hasSessionMeta: true,
                        hasTranscript: transcriptUpdatedAt != nil,
                        hasBridge: bridge != nil,
                        hasModel: !resolvedModelLabel.isEmpty
                    )
                )
            ]
        )
    }

    private func transitionToOffline(now: Date, trigger: String) {
        let offlineState = AgentState(
            kind: .claude,
            online: false,
            availability: .offline,
            globalState: .offline,
            threads: [],
            quota: nil
        )
        if offlineState != claudeState {
            claudeState = offlineState
            cachedSessionId = nil
            cachedJsonlPath = nil
        }
        diagnostics = AgentMonitorDiagnostics(
            kind: .claude,
            refreshedAt: now,
            freshnessPolicy: freshnessPolicy,
            triggerMode: "event+poll/\(trigger)",
            threads: []
        )
    }

    private struct SessionInfo {
        let pid: Int32
        let sessionId: String
        let cwd: String
        let activity: ClaudeCodeSessionActivity?
        let observedAt: Date
        let filePath: String
    }

    private func findActiveSession() -> SessionInfo? {
        guard let files = try? fileManager.contentsOfDirectory(atPath: sessionsDirPath) else {
            return nil
        }

        let jsonFiles = files.filter { $0.hasSuffix(".json") }
        guard !jsonFiles.isEmpty else {
            return nil
        }

        var bestFile: String?
        var bestModDate: Date = .distantPast

        for file in jsonFiles {
            let path = sessionsDirPath + "/" + file
            if let attrs = try? fileManager.attributesOfItem(atPath: path),
               let modDate = attrs[.modificationDate] as? Date,
               modDate > bestModDate
            {
                bestModDate = modDate
                bestFile = path
            }
        }

        guard let filePath = bestFile,
              let data = fileManager.contents(atPath: filePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = json["pid"] as? Int,
              let sessionId = json["sessionId"] as? String,
              let cwd = json["cwd"] as? String
        else {
            return nil
        }

        return SessionInfo(
            pid: Int32(pid),
            sessionId: sessionId,
            cwd: cwd,
            activity: ClaudeCodeSnapshotParser.parseSessionActivity(from: data),
            observedAt: bestModDate,
            filePath: filePath
        )
    }

    private func isProcessAlive(pid: Int32) -> Bool {
        processAliveChecker(pid)
    }

    private func resolveJsonlPath(sessionId: String, cwd: String) -> String? {
        if let cached = cachedJsonlPath, cachedSessionId == sessionId {
            return cached
        }

        let encodedCwd = encodeCwd(cwd)
        let directPath = projectsDirPath + "/" + encodedCwd + "/" + sessionId + ".jsonl"
        if fileManager.fileExists(atPath: directPath) {
            cachedSessionId = sessionId
            cachedJsonlPath = directPath
            return directPath
        }

        guard let projectDirs = try? fileManager.contentsOfDirectory(atPath: projectsDirPath) else {
            return nil
        }

        for dir in projectDirs {
            let candidate = projectsDirPath + "/" + dir + "/" + sessionId + ".jsonl"
            if fileManager.fileExists(atPath: candidate) {
                cachedSessionId = sessionId
                cachedJsonlPath = candidate
                return candidate
            }
        }

        return nil
    }

    /// Encode a cwd path the same way Claude Code does:
    /// "/Users/foo/bar" -> "-Users-foo-bar"
    private func encodeCwd(_ cwd: String) -> String {
        cwd.replacingOccurrences(of: "/", with: "-")
    }

    private func parseTranscriptTail(path: String?) -> ClaudeCodeTranscriptSnapshot {
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

    private struct BridgeData {
        let contextRatio: Double?
        let observedAt: Date?
        let filePath: String
    }

    private func readBridgeFile(sessionId: String) -> BridgeData? {
        let bridgePath = URL(fileURLWithPath: temporaryDirectoryPath, isDirectory: true)
            .appendingPathComponent("claude-ctx-" + sessionId + ".json")
            .path

        guard let data = fileManager.contents(atPath: bridgePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let observedAt = fileModificationDate(atPath: bridgePath)
        let contextRatio: Double? = (json["used_pct"] as? Int)
            .map { min(Double($0) / 100.0, 1.0) }

        return BridgeData(contextRatio: contextRatio, observedAt: observedAt, filePath: bridgePath)
    }

    private func decayState(_ rawState: AgentGlobalState, stage: MonitorFreshnessStage) -> AgentGlobalState {
        switch stage {
        case .live:
            return rawState
        case .cooling, .recentIdle, .staleHidden, .expired:
            return .idle
        }
    }

    private func shouldRenderThread(for stage: MonitorFreshnessStage) -> Bool {
        switch stage {
        case .live, .cooling, .recentIdle:
            return true
        case .staleHidden, .expired:
            return false
        }
    }

    private func resolveModelLabel(
        sessionId: String,
        rawModel: String,
        lastSignalAt: Date?,
        now: Date
    ) -> String {
        let cacheWindow = freshnessPolicy.visibleIdleWindow
        if !rawModel.isEmpty {
            lastKnownModels[sessionId] = CachedModel(label: rawModel, updatedAt: lastSignalAt ?? now)
            return rawModel
        }

        guard let cached = lastKnownModels[sessionId] else {
            return rawModel
        }

        if now.timeIntervalSince(cached.updatedAt) > cacheWindow {
            lastKnownModels.removeValue(forKey: sessionId)
            return rawModel
        }

        return cached.label
    }

    private func baseWatchedPaths() -> [String] {
        [
            sessionsDirPath,
            projectsDirPath,
            temporaryDirectoryPath,
        ]
    }

    private func watchedPaths(
        sessionPath: String,
        transcriptPath: String?,
        bridgePath: String?
    ) -> [String] {
        var paths = baseWatchedPaths()
        paths.append(sessionPath)
        if let transcriptPath {
            paths.append(transcriptPath)
            paths.append((transcriptPath as NSString).deletingLastPathComponent)
        }
        if let bridgePath {
            paths.append(bridgePath)
        }
        return paths
    }

    private func sourceHits(
        hasSessionMeta: Bool,
        hasTranscript: Bool,
        hasBridge: Bool,
        hasModel: Bool
    ) -> [String] {
        var hits: [String] = []
        if hasSessionMeta { hits.append("session") }
        if hasTranscript { hits.append("transcript") }
        if hasBridge { hits.append("bridge") }
        if hasModel { hits.append("model") }
        if hits.isEmpty { hits.append("none") }
        return hits
    }

    private func fileModificationDate(atPath path: String?) -> Date? {
        guard let path,
              let attrs = try? fileManager.attributesOfItem(atPath: path)
        else {
            return nil
        }
        return attrs[.modificationDate] as? Date
    }
}
