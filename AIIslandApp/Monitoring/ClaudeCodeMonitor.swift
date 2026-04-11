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

    private var pollTimer: Timer?
    private var cachedSessionId: String?
    private var cachedJsonlPath: String?
    private let fileManager: FileManager
    private let sessionsDirPath: String
    private let projectsDirPath: String
    private let temporaryDirectoryPath: String
    private let processAliveChecker: (Int32) -> Bool
    private static let activeStateWindow: TimeInterval = 2 * 60
    private static let coolingIdleWindow: TimeInterval = 8 * 60
    private static let visibleIdleWindow: TimeInterval = 15 * 60
    private static let liveSignalWindow: TimeInterval = 30 * 60

    private static let claudeDir: String = {
        NSHomeDirectory() + "/.claude"
    }()

    private static let sessionsDir: String = {
        claudeDir + "/sessions"
    }()

    private static let projectsDir: String = {
        claudeDir + "/projects"
    }()

    private static let transcriptTailBytes: UInt64 = 262144

    init(
        fileManager: FileManager = .default,
        claudeDirPath: String = ClaudeCodeMonitor.claudeDir,
        temporaryDirectoryPath: String = NSTemporaryDirectory(),
        processAliveChecker: @escaping (Int32) -> Bool = { kill($0, 0) == 0 }
    ) {
        self.fileManager = fileManager
        sessionsDirPath = claudeDirPath + "/sessions"
        projectsDirPath = claudeDirPath + "/projects"
        self.temporaryDirectoryPath = temporaryDirectoryPath
        self.processAliveChecker = processAliveChecker
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
        // Timer invalidation handled by stop() or natural deallocation
    }

    func refreshNow() {
        refresh()
    }

    private func refresh() {
        guard let session = findActiveSession() else {
            transitionTo(offline: true)
            return
        }

        guard isProcessAlive(pid: session.pid) else {
            transitionTo(offline: true)
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

        // Read context ratio from the statusline bridge file. Live activity
        // state should follow Claude's session metadata instead of custom
        // statusline bridge inference.
        let bridge = readBridgeFile(sessionId: session.sessionId)
        let rawState = ClaudeCodeSnapshotParser.resolveGlobalState(
            activity: session.activity,
            transcript: transcript
        )
        let now = Date()
        let lastSignalAt = [session.observedAt, transcriptUpdatedAt, bridge?.observedAt]
            .compactMap { $0 }
            .max()
        let stage = decayStage(lastSignalAt: lastSignalAt, now: now)
        let availability: AgentAvailability = stage == .expired ? .statusUnavailable : .available
        let state = decayState(rawState, stage: stage)
        let contextRatio = bridge?.contextRatio
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
                    modelLabel: ClaudeCodeSnapshotParser.resolveModelLabel(transcript: transcript),
                    contextRatio: contextRatio,
                    state: state
                )
            ] : [],
            quota: nil
        )

        if newState != claudeState {
            claudeState = newState
        }
    }

    private func transitionTo(offline: Bool) {
        guard offline else { return }
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
    }

    // MARK: - Session Discovery

    private struct SessionInfo {
        let pid: Int32
        let sessionId: String
        let cwd: String
        let activity: ClaudeCodeSessionActivity?
        let observedAt: Date
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
            observedAt: bestModDate
        )
    }

    // MARK: - Process Check

    private func isProcessAlive(pid: Int32) -> Bool {
        processAliveChecker(pid)
    }

    // MARK: - JSONL Path Resolution

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

        // Fallback: search all project directories
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
    /// "/Users/foo/bar" → "-Users-foo-bar"
    private func encodeCwd(_ cwd: String) -> String {
        cwd.replacingOccurrences(of: "/", with: "-")
    }

    // MARK: - JSONL Parsing

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

        guard let fileSize = try? handle.seekToEnd(),
              fileSize > 0
        else {
            return ClaudeCodeTranscriptSnapshot(
                fallbackState: .idle,
                modelLabel: nil,
                taskSummary: nil,
                hasInProgressToolUse: false
            )
        }

        let offset = fileSize > Self.transcriptTailBytes ? fileSize - Self.transcriptTailBytes : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd() else {
            return ClaudeCodeTranscriptSnapshot(
                fallbackState: .idle,
                modelLabel: nil,
                taskSummary: nil,
                hasInProgressToolUse: false
            )
        }

        guard let text = String(data: data, encoding: .utf8) else {
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

    // MARK: - Bridge File

    private struct BridgeData {
        let contextRatio: Double?
        let observedAt: Date?
    }

    /// Read context ratio from the bridge file written by the statusline
    /// command. We intentionally ignore custom `agent_state` fields there,
    /// because Claude's live activity should come from session metadata.
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
        return BridgeData(contextRatio: contextRatio, observedAt: observedAt)
    }

    private enum ActivityDecayStage {
        case live
        case cooling
        case recentIdle
        case staleHidden
        case expired
    }

    private func decayStage(lastSignalAt: Date?, now: Date) -> ActivityDecayStage {
        guard let lastSignalAt else {
            return .expired
        }

        let age = max(0, now.timeIntervalSince(lastSignalAt))
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

    private func decayState(
        _ rawState: AgentGlobalState,
        stage: ActivityDecayStage
    ) -> AgentGlobalState {
        switch stage {
        case .live:
            return rawState
        case .cooling, .recentIdle, .staleHidden, .expired:
            return .idle
        }
    }

    private func shouldRenderThread(for stage: ActivityDecayStage) -> Bool {
        switch stage {
        case .live, .cooling, .recentIdle:
            return true
        case .staleHidden, .expired:
            return false
        }
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
