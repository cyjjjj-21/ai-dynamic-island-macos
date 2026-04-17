import Foundation

import AIIslandCore

struct CodexMonitorArbitrationResult: Equatable, Sendable {
    let state: AgentState
    let diagnostics: AgentMonitorDiagnostics
    let updatedModels: [String: CodexCachedModel]
}

enum CodexMonitorArbitrator {
    private static let maxVisibleThreads = 3
    private static let maxDiagnosticThreads = 4

    static func compute(
        indexedThreads: [CodexIndexedThread],
        parsedSnapshots: [CodexSessionSnapshot],
        subagentActivityByParentID: [String: CodexSubagentActivity] = [:],
        hasReadableArtifacts: Bool,
        cachedModels: [String: CodexCachedModel],
        freshnessPolicy: MonitorFreshnessPolicy,
        now: Date,
        trigger: String
    ) -> CodexMonitorArbitrationResult {
        var mutableModels = cachedModels
        let snapshots = parsedSnapshots.map {
            applyModelCache(
                to: $0,
                now: now,
                freshnessPolicy: freshnessPolicy,
                knownModels: &mutableModels
            )
        }

        let liveSignalSnapshots = snapshots.filter {
            freshnessPolicy.stage(lastSignalAt: $0.updatedAt, now: now) != .expired
                && $0.trustLevel == .eventDerived
        }

        let displaySnapshots = liveSignalSnapshots.compactMap {
            decaySnapshotForDisplay($0, now: now, freshnessPolicy: freshnessPolicy)
        }

        let hasEventDerivedSignals = snapshots.contains { $0.trustLevel == .eventDerived }
        let effectiveSnapshots: [CodexSessionSnapshot]
        if liveSignalSnapshots.isEmpty {
            if hasEventDerivedSignals {
                effectiveSnapshots = snapshots
            } else {
                effectiveSnapshots = indexedThreads.map { CodexSessionSnapshotParser.makeRecentIndexFallback(from: $0) }
            }
        } else {
            effectiveSnapshots = snapshots
        }

        let availability: AgentAvailability
        if !hasReadableArtifacts {
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

        let visibleThreads = Array(sortedThreads.prefix(maxVisibleThreads)).map { snapshot in
            let resolved = ThreadTitleResolver.resolveCodexTitle(
                prompts: snapshot.promptCandidates,
                sessionIndexTitle: snapshot.titleHint,
                workspacePath: snapshot.workspacePath,
                latestAssistantMessage: snapshot.latestAssistantMessage
            )
            return AgentThread(
                id: snapshot.sessionID,
                title: resolved.title,
                detail: mergedDetail(
                    primary: resolved.detail,
                    subagentActivity: subagentActivityByParentID[snapshot.sessionID],
                    freshnessPolicy: freshnessPolicy,
                    now: now
                ),
                workspaceLabel: resolved.workspaceLabel,
                modelLabel: snapshot.modelLabel,
                contextRatio: snapshot.contextRatio,
                state: snapshot.state,
                lastUpdatedAt: snapshot.updatedAt,
                titleSource: resolved.source
            )
        }

        let latestQuotaSnapshot = liveSignalSnapshots
            .filter { $0.fiveHourRatio != nil || $0.weeklyRatio != nil }
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            .first

        let state = AgentState(
            kind: .codex,
            online: availability != .offline,
            availability: availability,
            globalState: resolveGlobalState(
                availability: availability,
                snapshots: displaySnapshots
            ),
            threads: visibleThreads,
            quota: availability == .offline ? nil : AgentQuota(
                availability: latestQuotaSnapshot == nil ? .unavailable : .available,
                fiveHourRatio: latestQuotaSnapshot?.fiveHourRatio,
                weeklyRatio: latestQuotaSnapshot?.weeklyRatio,
                fiveHourResetsAt: latestQuotaSnapshot?.fiveHourResetsAt,
                weeklyResetsAt: latestQuotaSnapshot?.weeklyResetsAt
            )
        )

        let diagnostics = AgentMonitorDiagnostics(
            kind: .codex,
            refreshedAt: now,
            freshnessPolicy: freshnessPolicy,
            triggerMode: "event+poll/\(trigger)",
            threads: snapshots
                .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
                .prefix(maxDiagnosticThreads)
                .map { snapshot in
                    MonitorThreadDiagnostics(
                        id: snapshot.sessionID,
                        lastSignalAt: snapshot.updatedAt,
                        stage: freshnessPolicy.stage(lastSignalAt: snapshot.updatedAt, now: now),
                        sourceHits: sourceHits(for: snapshot)
                    )
                }
        )

        return CodexMonitorArbitrationResult(
            state: state,
            diagnostics: diagnostics,
            updatedModels: mutableModels
        )
    }

    private static func resolveGlobalState(
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

    private static func decaySnapshotForDisplay(
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
                fiveHourResetsAt: snapshot.fiveHourResetsAt,
                weeklyResetsAt: snapshot.weeklyResetsAt,
                state: .idle,
                updatedAt: snapshot.updatedAt,
                trustLevel: snapshot.trustLevel,
                hasStructuredTokenSignal: snapshot.hasStructuredTokenSignal,
                hasStructuredActivitySignal: snapshot.hasStructuredActivitySignal,
                promptCandidates: snapshot.promptCandidates,
                titleHint: snapshot.titleHint,
                workspacePath: snapshot.workspacePath,
                latestAssistantMessage: snapshot.latestAssistantMessage
            )
        case .staleHidden, .expired:
            return nil
        }
    }

    private static func applyModelCache(
        to snapshot: CodexSessionSnapshot,
        now: Date,
        freshnessPolicy: MonitorFreshnessPolicy,
        knownModels: inout [String: CodexCachedModel]
    ) -> CodexSessionSnapshot {
        let cacheWindow = freshnessPolicy.visibleIdleWindow

        if !snapshot.modelLabel.isEmpty {
            knownModels[snapshot.sessionID] = CodexCachedModel(
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
            fiveHourResetsAt: snapshot.fiveHourResetsAt,
            weeklyResetsAt: snapshot.weeklyResetsAt,
            state: snapshot.state,
            updatedAt: snapshot.updatedAt,
            trustLevel: snapshot.trustLevel,
            hasStructuredTokenSignal: snapshot.hasStructuredTokenSignal,
            hasStructuredActivitySignal: snapshot.hasStructuredActivitySignal,
            promptCandidates: snapshot.promptCandidates,
            titleHint: snapshot.titleHint,
            workspacePath: snapshot.workspacePath,
            latestAssistantMessage: snapshot.latestAssistantMessage
        )
    }

    private static func mergedDetail(
        primary: String?,
        subagentActivity: CodexSubagentActivity?,
        freshnessPolicy: MonitorFreshnessPolicy,
        now: Date
    ) -> String? {
        let base = primary?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let subagentActivity else {
            return emptyToNil(base)
        }

        guard freshnessPolicy.stage(lastSignalAt: subagentActivity.latestUpdatedAt, now: now) != .expired else {
            return emptyToNil(base)
        }

        let subagentCopy = "\(subagentActivity.activeCount) 个子任务有更新"
        guard let base = emptyToNil(base) else {
            return subagentCopy
        }

        guard shouldAppendSubagentSummary(to: base) else {
            return base
        }

        let merged = "\(base) · \(subagentActivity.activeCount) 子任务更新"
        return merged.count <= 18 ? merged : base
    }

    private static func emptyToNil(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func shouldAppendSubagentSummary(to base: String) -> Bool {
        let lowercased = base.lowercased()
        if lowercased.contains("确认") || lowercased.contains("批准") || lowercased.contains("approve") {
            return false
        }
        return base.count <= 10
    }

    private static func sourceHits(for snapshot: CodexSessionSnapshot) -> [String] {
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

    private static func trustPriority(_ trustLevel: CodexSnapshotTrustLevel) -> Int {
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
