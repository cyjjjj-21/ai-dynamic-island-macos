import Foundation

import AIIslandCore

enum CodexSnapshotTrustLevel: Equatable {
    case eventDerived
    case recentIndexFallback
    case insufficient
}

struct CodexSessionSnapshot: Equatable {
    let sessionID: String
    let taskLabel: String
    let modelLabel: String
    let contextRatio: Double?
    let fiveHourRatio: Double?
    let weeklyRatio: Double?
    let fiveHourResetsAt: Date?
    let weeklyResetsAt: Date?
    let state: AgentGlobalState
    let updatedAt: Date?
    let trustLevel: CodexSnapshotTrustLevel
    let hasStructuredTokenSignal: Bool
    let hasStructuredActivitySignal: Bool
    let promptCandidates: [String]
    let titleHint: String?
    let workspacePath: String?
    let latestAssistantMessage: String?
}

struct CodexSubagentActivity: Equatable, Sendable {
    let parentThreadID: String
    let activeCount: Int
    let latestUpdatedAt: Date?
}

enum CodexSessionSnapshotParser {
    private static let placeholderValues: Set<String> = [
        "undefined",
        "null",
        "nil",
        "none",
        "nan"
    ]

    static func isSubagentSession(_ text: String) -> Bool {
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard
                let lineData = rawLine.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                normalizedString(json["type"]) == "session_meta",
                let payload = json["payload"] as? [String: Any]
            else {
                continue
            }

            let source = payload["source"] as? [String: Any]
            guard let subagent = source?["subagent"] as? [String: Any], !subagent.isEmpty else {
                continue
            }

            let nestedThreadSpawn = subagent["thread_spawn"] as? [String: Any]
            let rootThreadSpawn = payload["thread_spawn"] as? [String: Any]
            let sourceThreadSpawn = source?["thread_spawn"] as? [String: Any]
            let hasParentThreadID = normalizedString(
                subagent["parent_thread_id"]
                    ?? subagent["parentThreadId"]
                    ?? nestedThreadSpawn?["parent_thread_id"]
                    ?? nestedThreadSpawn?["parentThreadId"]
                    ?? rootThreadSpawn?["parent_thread_id"]
                    ?? rootThreadSpawn?["parentThreadId"]
                    ?? sourceThreadSpawn?["parent_thread_id"]
                    ?? sourceThreadSpawn?["parentThreadId"]
                    ?? payload["parent_thread_id"]
                    ?? payload["parentThreadId"]
            ) != nil

            if hasParentThreadID {
                return true
            }
        }

        return false
    }

    static func parse(
        _ text: String,
        sessionID: String,
        fallbackTaskLabel: String
    ) -> CodexSessionSnapshot {
        var dateContext = DateParsingContext()
        var latestTimestamp: Date?
        var latestModelLabel: String?
        var latestUserPrompt: String?
        var latestAssistantMessage: String?
        var fallbackCwdTail: String?
        var workspacePath: String?
        var userPromptByTurnID: [String: String] = [:]
        var promptCandidates: [String] = []

        var activeTurnIDs: Set<String> = []
        var turnActivationOrder: [String] = []
        var activeCallIDs: Set<String> = []

        var contextRatio: Double?
        var fiveHourRatio: Double?
        var weeklyRatio: Double?
        var fiveHourResetsAt: Date?
        var weeklyResetsAt: Date?

        var hasStructuredTokenSignal = false
        var hasStructuredActivitySignal = false

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard
                let lineData = rawLine.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else {
                continue
            }

            if let parsedTimestamp = parseDate(
                json["timestamp"] ?? json["updated_at"] ?? json["updatedAt"] ?? json["ts"],
                context: &dateContext
            ) {
                if let existing = latestTimestamp {
                    latestTimestamp = max(existing, parsedTimestamp)
                } else {
                    latestTimestamp = parsedTimestamp
                }
            }

            let lineType = normalizedString(json["type"]) ?? ""
            switch lineType {
            case "session_meta":
                if let payload = json["payload"] as? [String: Any] {
                    let cwd = normalizedString(payload["cwd"])
                    if let cwd {
                        workspacePath = cwd
                        fallbackCwdTail = lastPathComponent(cwd)
                    }

                    if let model = normalizedString(payload["model"]) {
                        latestModelLabel = model
                    }
                }
            case "turn_context":
                guard let payload = json["payload"] as? [String: Any] else {
                    continue
                }
                if let model = normalizedString(payload["model"]) {
                    latestModelLabel = model
                    hasStructuredActivitySignal = true
                }
            case "response_item":
                guard let payload = json["payload"] as? [String: Any] else {
                    continue
                }
                let role = normalizedString(payload["role"])
                let payloadType = normalizedString(payload["type"])
                guard payloadType == "message", let role else {
                    continue
                }

                let turnID = normalizedString(payload["turn_id"] ?? payload["turnId"])
                let messageText = extractMessageText(from: payload["content"])
                guard let messageText else {
                    continue
                }

                hasStructuredActivitySignal = true
                if role == "user" {
                    guard !isSyntheticUserMessage(messageText) else {
                        continue
                    }
                    latestUserPrompt = messageText
                    if !promptCandidates.contains(messageText) {
                        promptCandidates.append(messageText)
                    }
                    if let turnID {
                        userPromptByTurnID[turnID] = messageText
                    }
                } else if role == "assistant" {
                    latestAssistantMessage = messageText
                }
            case "event_msg":
                guard
                    let payload = json["payload"] as? [String: Any],
                    let eventType = normalizedString(payload["type"])
                else {
                    continue
                }

                switch eventType {
                case "task_started":
                    hasStructuredActivitySignal = true
                    let turnID = normalizedString(payload["turn_id"] ?? payload["turnId"]) ?? "__unknown__"
                    activeTurnIDs.insert(turnID)
                    turnActivationOrder.removeAll(where: { $0 == turnID })
                    turnActivationOrder.append(turnID)
                case "task_complete":
                    hasStructuredActivitySignal = true
                    if let turnID = normalizedString(payload["turn_id"] ?? payload["turnId"]) {
                        activeTurnIDs.remove(turnID)
                    } else {
                        activeTurnIDs.removeAll()
                    }
                case "token_count":
                    hasStructuredTokenSignal = true
                    if let info = payload["info"] as? [String: Any] {
                        let lastTokenUsage = info["last_token_usage"] as? [String: Any]
                        let totalTokenUsage = info["total_token_usage"] as? [String: Any]
                        let totalTokens = number(from: lastTokenUsage?["total_tokens"])
                            ?? number(from: totalTokenUsage?["total_tokens"])
                        let modelContextWindow = number(from: info["model_context_window"])
                        if let totalTokens, let modelContextWindow, modelContextWindow > 0 {
                            contextRatio = clamp(totalTokens / modelContextWindow)
                        }
                    }

                    if let rateLimits = payload["rate_limits"] as? [String: Any] {
                        let primary = rateLimits["primary"] as? [String: Any]
                        let secondary = rateLimits["secondary"] as? [String: Any]
                        fiveHourRatio = number(from: primary?["used_percent"]).map(remainingRatio(fromUsedPercent:))
                        weeklyRatio = number(from: secondary?["used_percent"]).map(remainingRatio(fromUsedPercent:))
                        fiveHourResetsAt = parseDate(primary?["resets_at"], context: &dateContext)
                        weeklyResetsAt = parseDate(secondary?["resets_at"], context: &dateContext)
                    }
                case "agent_message":
                    hasStructuredActivitySignal = true
                    if let message = normalizedString(payload["message"]) {
                        latestAssistantMessage = message
                    }
                default:
                    let isCallBegin = eventType.hasSuffix("_begin")
                    let isCallEnd = eventType.hasSuffix("_end") || eventType.hasSuffix("_complete")
                    if isCallBegin || isCallEnd {
                        hasStructuredActivitySignal = true
                    }

                    let callID = normalizedString(payload["call_id"] ?? payload["callId"])
                    if isCallBegin, let callID {
                        activeCallIDs.insert(callID)
                    } else if isCallEnd, let callID {
                        activeCallIDs.remove(callID)
                    }
                }
            default:
                continue
            }
        }

        let activeTurnID = turnActivationOrder.last(where: { activeTurnIDs.contains($0) })
        let resolvedTaskLabel = resolveTaskLabel(
            activeTurnID: activeTurnID,
            userPromptByTurnID: userPromptByTurnID,
            latestUserPrompt: latestUserPrompt,
            fallbackTaskLabel: fallbackTaskLabel,
            fallbackCwdTail: fallbackCwdTail,
            sessionID: sessionID
        )

        let resolvedState = resolveState(
            activeTurnIDs: activeTurnIDs,
            activeCallIDs: activeCallIDs,
            latestAssistantMessage: latestAssistantMessage
        )

        let trustLevel: CodexSnapshotTrustLevel
        if hasStructuredTokenSignal || hasStructuredActivitySignal || latestModelLabel != nil {
            trustLevel = .eventDerived
        } else {
            trustLevel = .insufficient
        }

        return CodexSessionSnapshot(
            sessionID: sessionID,
            taskLabel: resolvedTaskLabel,
            modelLabel: latestModelLabel ?? "",
            contextRatio: contextRatio,
            fiveHourRatio: fiveHourRatio,
            weeklyRatio: weeklyRatio,
            fiveHourResetsAt: fiveHourResetsAt,
            weeklyResetsAt: weeklyResetsAt,
            state: resolvedState,
            updatedAt: latestTimestamp,
            trustLevel: trustLevel,
            hasStructuredTokenSignal: hasStructuredTokenSignal,
            hasStructuredActivitySignal: hasStructuredActivitySignal,
            promptCandidates: promptCandidates,
            titleHint: normalizedString(fallbackTaskLabel),
            workspacePath: workspacePath,
            latestAssistantMessage: latestAssistantMessage
        )
    }

    static func makeRecentIndexFallback(from indexedThread: CodexIndexedThread) -> CodexSessionSnapshot {
        let label = normalizedString(indexedThread.threadName) ?? indexedThread.threadID
        return CodexSessionSnapshot(
            sessionID: indexedThread.threadID,
            taskLabel: label,
            modelLabel: "",
            contextRatio: nil,
            fiveHourRatio: nil,
            weeklyRatio: nil,
            fiveHourResetsAt: nil,
            weeklyResetsAt: nil,
            state: .idle,
            updatedAt: indexedThread.updatedAt,
            trustLevel: .recentIndexFallback,
            hasStructuredTokenSignal: false,
            hasStructuredActivitySignal: false,
            promptCandidates: [],
            titleHint: normalizedString(indexedThread.threadName),
            workspacePath: nil,
            latestAssistantMessage: nil
        )
    }

    static func replacing(
        _ snapshot: CodexSessionSnapshot,
        updatedAt: Date?
    ) -> CodexSessionSnapshot {
        CodexSessionSnapshot(
            sessionID: snapshot.sessionID,
            taskLabel: snapshot.taskLabel,
            modelLabel: snapshot.modelLabel,
            contextRatio: snapshot.contextRatio,
            fiveHourRatio: snapshot.fiveHourRatio,
            weeklyRatio: snapshot.weeklyRatio,
            fiveHourResetsAt: snapshot.fiveHourResetsAt,
            weeklyResetsAt: snapshot.weeklyResetsAt,
            state: snapshot.state,
            updatedAt: updatedAt ?? snapshot.updatedAt,
            trustLevel: snapshot.trustLevel,
            hasStructuredTokenSignal: snapshot.hasStructuredTokenSignal,
            hasStructuredActivitySignal: snapshot.hasStructuredActivitySignal,
            promptCandidates: snapshot.promptCandidates,
            titleHint: snapshot.titleHint,
            workspacePath: snapshot.workspacePath,
            latestAssistantMessage: snapshot.latestAssistantMessage
        )
    }

    static func parseSubagentActivity(
        from text: String,
        fallbackUpdatedAt: Date?
    ) -> CodexSubagentActivity? {
        var dateContext = DateParsingContext()

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard
                let lineData = rawLine.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                normalizedString(json["type"]) == "session_meta",
                let payload = json["payload"] as? [String: Any]
            else {
                continue
            }

            let source = payload["source"] as? [String: Any]
            let subagent = source?["subagent"] as? [String: Any]
            let rootThreadSpawn = payload["thread_spawn"] as? [String: Any]
            let sourceThreadSpawn = source?["thread_spawn"] as? [String: Any]
            let parentThreadID = normalizedString(
                subagent?["parent_thread_id"]
                    ?? subagent?["parentThreadId"]
                    ?? (subagent?["thread_spawn"] as? [String: Any])?["parent_thread_id"]
                    ?? (subagent?["thread_spawn"] as? [String: Any])?["parentThreadId"]
                    ?? rootThreadSpawn?["parent_thread_id"]
                    ?? rootThreadSpawn?["parentThreadId"]
                    ?? sourceThreadSpawn?["parent_thread_id"]
                    ?? sourceThreadSpawn?["parentThreadId"]
                    ?? payload["parent_thread_id"]
                    ?? payload["parentThreadId"]
            )

            guard let parentThreadID else {
                continue
            }

            let observedAt = parseDate(
                json["timestamp"] ?? json["updated_at"] ?? json["updatedAt"] ?? json["ts"],
                context: &dateContext
            ) ?? fallbackUpdatedAt

            return CodexSubagentActivity(
                parentThreadID: parentThreadID,
                activeCount: 1,
                latestUpdatedAt: observedAt
            )
        }

        return nil
    }

    private static func resolveTaskLabel(
        activeTurnID: String?,
        userPromptByTurnID: [String: String],
        latestUserPrompt: String?,
        fallbackTaskLabel: String,
        fallbackCwdTail: String?,
        sessionID: String
    ) -> String {
        if let activeTurnID,
           let activePrompt = normalizedString(userPromptByTurnID[activeTurnID]) {
            return activePrompt
        }

        if let latestUserPrompt = normalizedString(latestUserPrompt) {
            return latestUserPrompt
        }

        if let fallbackTaskLabel = normalizedString(fallbackTaskLabel) {
            return fallbackTaskLabel
        }

        if let fallbackCwdTail = normalizedString(fallbackCwdTail) {
            return fallbackCwdTail
        }

        return sessionID
    }

    private static func resolveState(
        activeTurnIDs: Set<String>,
        activeCallIDs: Set<String>,
        latestAssistantMessage: String?
    ) -> AgentGlobalState {
        if let message = normalizedString(latestAssistantMessage), isAttentionMessage(message) {
            return .attention
        }

        if !activeTurnIDs.isEmpty {
            return activeCallIDs.isEmpty ? .thinking : .working
        }

        if !activeCallIDs.isEmpty {
            return .working
        }

        return .idle
    }

    private static func isAttentionMessage(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        let signals = [
            "need your approval",
            "waiting for your approval",
            "awaiting your input",
            "need your input",
            "please choose",
            "before i continue",
            "requires your confirmation",
            "please confirm",
            "请选择",
            "请确认",
            "需要你",
            "等待你的输入"
        ]

        return signals.contains { lowercased.contains($0) }
    }

    private static func isSyntheticUserMessage(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        if lowered.contains("<subagent_notification") || lowered.contains("</subagent_notification>") {
            return true
        }

        let looksLikeAgentJSON = trimmed.hasPrefix("{")
            && lowered.contains("\"agent_path\"")
            && lowered.contains("\"status\"")
        if looksLikeAgentJSON {
            return true
        }

        return lowered.contains("\"agent_path\"") && lowered.contains("::code-comment{")
    }

    private static func extractMessageText(from content: Any?) -> String? {
        guard let items = content as? [Any] else {
            return nil
        }

        for item in items {
            guard
                let block = item as? [String: Any],
                let blockType = normalizedString(block["type"])
            else {
                continue
            }

            switch blockType {
            case "input_text", "output_text", "text":
                if let text = normalizedString(block["text"]) {
                    return text
                }
            default:
                continue
            }
        }

        return nil
    }

    private static func lastPathComponent(_ path: String) -> String {
        let normalized = path.hasSuffix("/") ? String(path.dropLast()) : path
        return normalized.split(separator: "/").last.map(String.init) ?? normalized
    }

    private static func normalizedString(_ value: Any?) -> String? {
        guard let value = value as? String else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return placeholderValues.contains(trimmed.lowercased()) ? nil : trimmed
    }

    private static func number(from value: Any?) -> Double? {
        switch value {
        case let value as Double:
            return value
        case let value as Int:
            return Double(value)
        case let value as NSNumber:
            return value.doubleValue
        case let value as String:
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private struct DateParsingContext {
        let fractional: ISO8601DateFormatter
        let base: ISO8601DateFormatter

        init() {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            self.fractional = fractional

            let base = ISO8601DateFormatter()
            base.formatOptions = [.withInternetDateTime]
            self.base = base
        }
    }

    private static func parseDate(_ value: Any?, context: inout DateParsingContext) -> Date? {
        guard let value else {
            return nil
        }

        if let date = value as? Date {
            return date
        }

        if let unix = number(from: value) {
            return unix > 10_000_000_000
                ? Date(timeIntervalSince1970: unix / 1_000.0)
                : Date(timeIntervalSince1970: unix)
        }

        if let raw = normalizedString(value) {
            if let date = context.fractional.date(from: raw) {
                return date
            }

            if let date = context.base.date(from: raw) {
                return date
            }
        }

        return nil
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }

    private static func remainingRatio(fromUsedPercent usedPercent: Double) -> Double {
        clamp(1.0 - (usedPercent / 100.0))
    }

}
