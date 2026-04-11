import Foundation

import AIIslandCore

enum ClaudeCodeSessionStatus: String, Equatable {
    case busy
    case idle
    case waiting
}

struct ClaudeCodeSessionActivity: Equatable {
    let status: ClaudeCodeSessionStatus
    let waitingFor: String?
}

struct ClaudeCodeTranscriptSnapshot: Equatable {
    let fallbackState: AgentGlobalState
    let modelLabel: String?
    let taskSummary: String?
    let hasInProgressToolUse: Bool
}

enum ClaudeCodeSnapshotParser {
    static func parseSessionActivity(from data: Data) -> ClaudeCodeSessionActivity? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawStatus = json["status"] as? String,
              let status = ClaudeCodeSessionStatus(rawValue: rawStatus)
        else {
            return nil
        }

        let waitingFor = (json["waitingFor"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ClaudeCodeSessionActivity(
            status: status,
            waitingFor: waitingFor?.isEmpty == false ? waitingFor : nil
        )
    }

    static func parseTranscriptTail(_ text: String) -> ClaudeCodeTranscriptSnapshot {
        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }

        var fallbackState: AgentGlobalState = .idle
        var modelLabel: String?
        var taskSummary: String?
        var inProgressToolUseIDs = Set<String>()

        for line in lines {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                continue
            }

            if !isNoiseEntry(object) {
                fallbackState = mapJsonlEntryToState(object)
            }

            let type = object["type"] as? String ?? ""

            if type == "assistant",
               let message = object["message"] as? [String: Any],
               !isStreamingPlaceholder(message)
            {
                if let model = message["model"] as? String {
                    modelLabel = model
                }
            }

            if type == "task-summary",
               let summary = object["summary"] as? String
            {
                let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    taskSummary = trimmed
                }
            }

            if type == "assistant" {
                for block in contentBlocks(in: object["message"] as? [String: Any]) where block["type"] as? String == "tool_use" {
                    if let id = block["id"] as? String {
                        inProgressToolUseIDs.insert(id)
                    }
                }
            } else if type == "user" {
                for block in contentBlocks(in: object["message"] as? [String: Any]) where block["type"] as? String == "tool_result" {
                    if let toolUseID = block["tool_use_id"] as? String {
                        inProgressToolUseIDs.remove(toolUseID)
                    }
                }
            }
        }

        return ClaudeCodeTranscriptSnapshot(
            fallbackState: fallbackState,
            modelLabel: modelLabel,
            taskSummary: taskSummary,
            hasInProgressToolUse: !inProgressToolUseIDs.isEmpty
        )
    }

    static func resolveGlobalState(
        activity: ClaudeCodeSessionActivity?,
        transcript: ClaudeCodeTranscriptSnapshot
    ) -> AgentGlobalState {
        guard let activity else {
            return transcript.fallbackState
        }

        switch activity.status {
        case .waiting:
            return .attention
        case .idle:
            return .idle
        case .busy:
            return transcript.hasInProgressToolUse ? .working : .thinking
        }
    }

    static func resolveTaskLabel(
        activity: ClaudeCodeSessionActivity?,
        transcript: ClaudeCodeTranscriptSnapshot,
        cwd: String
    ) -> String {
        if let waitingFor = activity?.waitingFor, !waitingFor.isEmpty {
            return waitingFor
        }

        if let taskSummary = transcript.taskSummary, !taskSummary.isEmpty {
            return taskSummary
        }

        let trimmed = cwd.hasSuffix("/") ? String(cwd.dropLast()) : cwd
        return trimmed.components(separatedBy: "/").last ?? trimmed
    }

    static func resolveModelLabel(transcript: ClaudeCodeTranscriptSnapshot) -> String {
        transcript.modelLabel ?? ""
    }

    static func shouldRenderThread(
        activity: ClaudeCodeSessionActivity?,
        transcript: ClaudeCodeTranscriptSnapshot,
        state: AgentGlobalState
    ) -> Bool {
        if let waitingFor = activity?.waitingFor, !waitingFor.isEmpty {
            return true
        }

        if let taskSummary = transcript.taskSummary, !taskSummary.isEmpty {
            return true
        }

        if let modelLabel = transcript.modelLabel, !modelLabel.isEmpty {
            return true
        }

        return state != .idle && state != .offline
    }

    static func isStreamingPlaceholder(_ message: [String: Any]) -> Bool {
        guard let usage = message["usage"] as? [String: Any],
              let inputTokens = usage["input_tokens"] as? Int
        else {
            return false
        }

        return inputTokens == 0
    }

    static func isNoiseEntry(_ object: [String: Any]) -> Bool {
        let type = object["type"] as? String ?? ""
        return type == "file-history-snapshot"
            || type == "last-prompt"
            || type == "attachment"
            || type == "task-summary"
    }

    static func mapJsonlEntryToState(_ object: [String: Any]) -> AgentGlobalState {
        let type = object["type"] as? String ?? ""

        switch type {
        case "assistant":
            let message = object["message"] as? [String: Any]
            if let message, isStreamingPlaceholder(message) {
                return .thinking
            }

            let stopReason = message?["stop_reason"] as? String
            switch stopReason {
            case "end_turn":
                return .idle
            case "tool_use":
                return .working
            case nil, "":
                return .thinking
            default:
                return .thinking
            }
        case "user":
            return .thinking
        case "permission-mode":
            return .attention
        case "system":
            return .idle
        default:
            return .idle
        }
    }

    private static func contentBlocks(in message: [String: Any]?) -> [[String: Any]] {
        guard let content = message?["content"] as? [Any] else {
            return []
        }

        return content.compactMap { $0 as? [String: Any] }
    }
}
