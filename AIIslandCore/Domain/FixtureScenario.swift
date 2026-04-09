import Foundation

public enum FixtureScenario: String, CaseIterable, Codable, Sendable {
    case bothIdle = "both-idle"
    case codexBusyClaudeIdle = "codex-busy-claude-idle"
    case codexIdleClaudeBusy = "codex-idle-claude-busy"
    case bothBusy = "both-busy"
    case attentionNeeded = "attention-needed"
    case codexOffline = "codex-offline"
    case claudeOffline = "claude-offline"
    case statusUnavailable = "status-unavailable"
    case contextUnavailable = "context-unavailable"
    case quotaUnavailable = "quota-unavailable"
    case threadOverflow = "thread-overflow"
    case longModelNames = "long-model-names"
}
