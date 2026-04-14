import Foundation

import AIIslandCore

struct ClaudeBridgeSnapshot: Equatable, Sendable {
    let contextRatio: Double?
    let observedAt: Date?
    let filePath: String
}

struct ClaudeMonitorSessionSnapshot: Equatable, Sendable {
    let candidate: ClaudeSessionCandidate
    let transcript: ClaudeCodeTranscriptSnapshot
    let transcriptUpdatedAt: Date?
    let transcriptPath: String?
    let bridge: ClaudeBridgeSnapshot?
}

struct ClaudeMonitorArbitrationResult: Equatable, Sendable {
    let state: AgentState
    let diagnostics: AgentMonitorDiagnostics
    let watchedPaths: [String]
    let updatedModels: [String: ClaudeCachedModel]
}

enum ClaudeMonitorArbitrator {
    static let maxVisibleThreads = 3
    static let maxWatchSessions = 6
    private static let maxDiagnosticThreads = 4

    static func compute(
        snapshots: [ClaudeMonitorSessionSnapshot],
        baseWatchedPaths: [String],
        cachedModels: [String: ClaudeCachedModel],
        freshnessPolicy: MonitorFreshnessPolicy,
        now: Date,
        trigger: String
    ) -> ClaudeMonitorArbitrationResult {
        var mutableModels = cachedModels

        let evaluations = snapshots.map { snapshot in
            evaluate(
                snapshot: snapshot,
                now: now,
                freshnessPolicy: freshnessPolicy,
                cachedModels: &mutableModels
            )
        }

        let availability: AgentAvailability
        if snapshots.isEmpty {
            availability = .offline
        } else if evaluations.contains(where: { $0.stage != .expired }) {
            availability = .available
        } else {
            availability = .statusUnavailable
        }

        let sortedVisibleEvaluations = evaluations
            .filter(\.shouldRenderThread)
            .sorted { lhs, rhs in
                comparePriority(lhs, rhs, freshnessPolicy: freshnessPolicy, now: now)
            }
        let visibleEvaluations = Array(sortedVisibleEvaluations.prefix(maxVisibleThreads))

        let threads = visibleEvaluations.map { evaluation in
            AgentThread(
                id: evaluation.sessionID,
                taskLabel: evaluation.taskLabel,
                modelLabel: evaluation.modelLabel,
                contextRatio: evaluation.contextRatio,
                state: evaluation.state
            )
        }

        let state = AgentState(
            kind: .claude,
            online: availability != .offline,
            availability: availability,
            globalState: resolveGlobalState(
                availability: availability,
                visibleEvaluations: visibleEvaluations
            ),
            threads: threads,
            quota: nil
        )

        let diagnostics = AgentMonitorDiagnostics(
            kind: .claude,
            refreshedAt: now,
            freshnessPolicy: freshnessPolicy,
            triggerMode: "event+poll/\(trigger)",
            threads: evaluations
                .sorted { ($0.lastSignalAt ?? .distantPast) > ($1.lastSignalAt ?? .distantPast) }
                .prefix(maxDiagnosticThreads)
                .map { evaluation in
                    MonitorThreadDiagnostics(
                        id: evaluation.sessionID,
                        lastSignalAt: evaluation.lastSignalAt,
                        stage: evaluation.stage,
                        sourceHits: evaluation.sourceHits
                    )
                }
        )

        return ClaudeMonitorArbitrationResult(
            state: state,
            diagnostics: diagnostics,
            watchedPaths: watchedPaths(
                baseWatchedPaths: baseWatchedPaths,
                evaluations: evaluations,
                visibleSessionIDs: Set(visibleEvaluations.map(\.sessionID)),
                freshnessPolicy: freshnessPolicy,
                now: now
            ),
            updatedModels: mutableModels
        )
    }

    private struct SessionEvaluation: Equatable, Sendable {
        let sessionID: String
        let taskLabel: String
        let modelLabel: String
        let contextRatio: Double?
        let state: AgentGlobalState
        let stage: MonitorFreshnessStage
        let lastSignalAt: Date?
        let sessionPath: String
        let transcriptPath: String?
        let bridgePath: String?
        let sourceHits: [String]
        let shouldRenderThread: Bool
    }

    private static func evaluate(
        snapshot: ClaudeMonitorSessionSnapshot,
        now: Date,
        freshnessPolicy: MonitorFreshnessPolicy,
        cachedModels: inout [String: ClaudeCachedModel]
    ) -> SessionEvaluation {
        let rawState = ClaudeCodeSnapshotParser.resolveGlobalState(
            activity: snapshot.candidate.activity,
            transcript: snapshot.transcript
        )
        let lastSignalAt = [snapshot.candidate.observedAt, snapshot.transcriptUpdatedAt, snapshot.bridge?.observedAt]
            .compactMap { $0 }
            .max()
        let stage = freshnessPolicy.stage(lastSignalAt: lastSignalAt, now: now)
        let state = decayState(rawState, stage: stage)
        let taskLabel = ClaudeCodeSnapshotParser.resolveTaskLabel(
            activity: snapshot.candidate.activity,
            transcript: snapshot.transcript,
            cwd: snapshot.candidate.cwd
        )
        let rawModel = ClaudeCodeSnapshotParser.resolveModelLabel(transcript: snapshot.transcript)
        let modelLabel = resolveModelLabel(
            sessionID: snapshot.candidate.sessionID,
            rawModel: rawModel,
            lastSignalAt: lastSignalAt,
            now: now,
            freshnessPolicy: freshnessPolicy,
            cachedModels: &cachedModels
        )
        let shouldRenderThread = ClaudeCodeSnapshotParser.shouldRenderThread(
            activity: snapshot.candidate.activity,
            transcript: snapshot.transcript,
            state: state
        ) && shouldRenderThread(for: stage)

        return SessionEvaluation(
            sessionID: snapshot.candidate.sessionID,
            taskLabel: taskLabel,
            modelLabel: modelLabel,
            contextRatio: snapshot.bridge?.contextRatio,
            state: state,
            stage: stage,
            lastSignalAt: lastSignalAt,
            sessionPath: snapshot.candidate.filePath,
            transcriptPath: snapshot.transcriptPath,
            bridgePath: snapshot.bridge?.filePath,
            sourceHits: sourceHits(
                hasSessionMeta: true,
                hasTranscript: snapshot.transcriptUpdatedAt != nil,
                hasBridge: snapshot.bridge != nil,
                hasModel: !modelLabel.isEmpty
            ),
            shouldRenderThread: shouldRenderThread
        )
    }

    private static func watchedPaths(
        baseWatchedPaths: [String],
        evaluations: [SessionEvaluation],
        visibleSessionIDs: Set<String>,
        freshnessPolicy: MonitorFreshnessPolicy,
        now: Date
    ) -> [String] {
        var paths = baseWatchedPaths

        let watchedEvaluations = evaluations
            .filter { $0.stage != .expired }
            .sorted { lhs, rhs in
                let lhsVisible = visibleSessionIDs.contains(lhs.sessionID)
                let rhsVisible = visibleSessionIDs.contains(rhs.sessionID)
                if lhsVisible != rhsVisible {
                    return lhsVisible && !rhsVisible
                }
                return comparePriority(lhs, rhs, freshnessPolicy: freshnessPolicy, now: now)
            }
            .prefix(maxWatchSessions)

        for evaluation in watchedEvaluations {
            paths.append(evaluation.sessionPath)
            if let transcriptPath = evaluation.transcriptPath {
                paths.append(transcriptPath)
                paths.append((transcriptPath as NSString).deletingLastPathComponent)
            }
            if let bridgePath = evaluation.bridgePath {
                paths.append(bridgePath)
            }
        }

        return normalize(paths)
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

    private static func resolveGlobalState(
        availability: AgentAvailability,
        visibleEvaluations: [SessionEvaluation]
    ) -> AgentGlobalState {
        if availability == .offline {
            return .offline
        }
        if availability == .statusUnavailable {
            return .idle
        }

        guard let primaryLiveSession = visibleEvaluations.first(where: { $0.stage == .live }) else {
            return .idle
        }
        return primaryLiveSession.state
    }

    private static func decayState(
        _ rawState: AgentGlobalState,
        stage: MonitorFreshnessStage
    ) -> AgentGlobalState {
        switch stage {
        case .live:
            return rawState
        case .cooling, .recentIdle, .staleHidden, .expired:
            return .idle
        }
    }

    private static func shouldRenderThread(for stage: MonitorFreshnessStage) -> Bool {
        switch stage {
        case .live, .cooling, .recentIdle:
            return true
        case .staleHidden, .expired:
            return false
        }
    }

    private static func resolveModelLabel(
        sessionID: String,
        rawModel: String,
        lastSignalAt: Date?,
        now: Date,
        freshnessPolicy: MonitorFreshnessPolicy,
        cachedModels: inout [String: ClaudeCachedModel]
    ) -> String {
        let cacheWindow = freshnessPolicy.visibleIdleWindow
        if !rawModel.isEmpty {
            cachedModels[sessionID] = ClaudeCachedModel(
                label: rawModel,
                updatedAt: lastSignalAt ?? now
            )
            return rawModel
        }

        guard let cached = cachedModels[sessionID] else {
            return rawModel
        }

        if now.timeIntervalSince(cached.updatedAt) > cacheWindow {
            cachedModels.removeValue(forKey: sessionID)
            return rawModel
        }

        return cached.label
    }

    private static func sourceHits(
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

    private static func comparePriority(
        _ lhs: SessionEvaluation,
        _ rhs: SessionEvaluation,
        freshnessPolicy: MonitorFreshnessPolicy,
        now: Date
    ) -> Bool {
        if statePriority(lhs.state) != statePriority(rhs.state) {
            return statePriority(lhs.state) > statePriority(rhs.state)
        }

        let lhsScore = freshnessPolicy.freshnessScore(lastSignalAt: lhs.lastSignalAt, now: now)
        let rhsScore = freshnessPolicy.freshnessScore(lastSignalAt: rhs.lastSignalAt, now: now)
        if lhsScore != rhsScore {
            return lhsScore > rhsScore
        }

        if lhs.lastSignalAt != rhs.lastSignalAt {
            return (lhs.lastSignalAt ?? .distantPast) > (rhs.lastSignalAt ?? .distantPast)
        }

        return lhs.sessionID < rhs.sessionID
    }

    private static func statePriority(_ state: AgentGlobalState) -> Int {
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
}
