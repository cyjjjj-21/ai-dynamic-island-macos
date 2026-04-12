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
    let state: AgentGlobalState
    let updatedAt: Date?
    let trustLevel: CodexSnapshotTrustLevel
    let hasStructuredTokenSignal: Bool
    let hasStructuredActivitySignal: Bool
}

enum CodexSessionSnapshotParser {
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
        var userPromptByTurnID: [String: String] = [:]

        var activeTurnIDs: Set<String> = []
        var turnActivationOrder: [String] = []
        var activeCallIDs: Set<String> = []

        var contextRatio: Double?
        var fiveHourRatio: Double?
        var weeklyRatio: Double?

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
                    latestUserPrompt = messageText
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
                        let primary = (rateLimits["primary"] as? [String: Any])?["used_percent"]
                        let secondary = (rateLimits["secondary"] as? [String: Any])?["used_percent"]
                        fiveHourRatio = number(from: primary).map(remainingRatio(fromUsedPercent:))
                        weeklyRatio = number(from: secondary).map(remainingRatio(fromUsedPercent:))
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
            state: resolvedState,
            updatedAt: latestTimestamp,
            trustLevel: trustLevel,
            hasStructuredTokenSignal: hasStructuredTokenSignal,
            hasStructuredActivitySignal: hasStructuredActivitySignal
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
            state: .idle,
            updatedAt: indexedThread.updatedAt,
            trustLevel: .recentIndexFallback,
            hasStructuredTokenSignal: false,
            hasStructuredActivitySignal: false
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
            state: snapshot.state,
            updatedAt: updatedAt ?? snapshot.updatedAt,
            trustLevel: snapshot.trustLevel,
            hasStructuredTokenSignal: snapshot.hasStructuredTokenSignal,
            hasStructuredActivitySignal: snapshot.hasStructuredActivitySignal
        )
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
        return trimmed.isEmpty ? nil : trimmed
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
