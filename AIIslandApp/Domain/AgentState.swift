import Foundation

enum AgentKind: String, Codable {
    case codex
    case claude
}

enum AgentAvailability: String, Codable {
    case available
    case statusUnavailable
    case offline
}

enum AgentGlobalState: String, Codable {
    case idle
    case thinking
    case working
    case attention
    case offline
}

enum AgentQuotaAvailability: String, Codable {
    case available
    case unavailable
}

struct AgentThread: Codable, Identifiable, Equatable {
    let id: String
    let taskLabel: String
    let modelLabel: String
    let contextRatio: Double?
    let state: AgentGlobalState
}

struct AgentQuota: Codable, Equatable {
    let availability: AgentQuotaAvailability?
    let fiveHourRatio: Double?
    let weeklyRatio: Double?
}

struct AgentState: Codable, Equatable {
    let kind: AgentKind
    let online: Bool
    let availability: AgentAvailability
    let globalState: AgentGlobalState
    let threads: [AgentThread]
    let quota: AgentQuota?
}

struct FixtureAgents: Codable, Equatable {
    let codex: AgentState
    let claude: AgentState
}

struct FixtureBundle: Codable, Equatable {
    let version: Int
    let notes: String
    let shellStates: [String]
    let fixtures: [String: FixtureAgents]
}
