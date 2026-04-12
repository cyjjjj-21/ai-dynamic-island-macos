import Foundation

public enum AgentKind: String, Codable, Sendable {
    case codex
    case claude
}

public enum AgentAvailability: String, Codable, Sendable {
    case available
    case statusUnavailable
    case offline
}

public enum AgentGlobalState: String, Codable, Sendable {
    case idle
    case thinking
    case working
    case attention
    case offline
}

public enum AgentQuotaAvailability: String, Codable, Sendable {
    case available
    case unavailable
}

public struct AgentThread: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let taskLabel: String
    public let modelLabel: String
    public let contextRatio: Double?
    public let state: AgentGlobalState

    public init(
        id: String,
        taskLabel: String,
        modelLabel: String,
        contextRatio: Double?,
        state: AgentGlobalState
    ) {
        self.id = id
        self.taskLabel = taskLabel
        self.modelLabel = modelLabel
        self.contextRatio = contextRatio
        self.state = state
    }
}

public struct AgentQuota: Codable, Equatable, Sendable {
    public let availability: AgentQuotaAvailability?
    public let fiveHourRatio: Double?
    public let weeklyRatio: Double?
    public let fiveHourResetsAt: Date?
    public let weeklyResetsAt: Date?

    public init(
        availability: AgentQuotaAvailability?,
        fiveHourRatio: Double?,
        weeklyRatio: Double?,
        fiveHourResetsAt: Date? = nil,
        weeklyResetsAt: Date? = nil
    ) {
        self.availability = availability
        self.fiveHourRatio = fiveHourRatio
        self.weeklyRatio = weeklyRatio
        self.fiveHourResetsAt = fiveHourResetsAt
        self.weeklyResetsAt = weeklyResetsAt
    }
}

public struct AgentState: Codable, Equatable, Sendable {
    public let kind: AgentKind
    public let online: Bool
    public let availability: AgentAvailability
    public let globalState: AgentGlobalState
    public let threads: [AgentThread]
    public let quota: AgentQuota?

    public init(
        kind: AgentKind,
        online: Bool,
        availability: AgentAvailability,
        globalState: AgentGlobalState,
        threads: [AgentThread],
        quota: AgentQuota?
    ) {
        self.kind = kind
        self.online = online
        self.availability = availability
        self.globalState = globalState
        self.threads = threads
        self.quota = quota
    }
}

public struct FixtureAgents: Codable, Equatable, Sendable {
    public let codex: AgentState
    public let claude: AgentState

    public init(codex: AgentState, claude: AgentState) {
        self.codex = codex
        self.claude = claude
    }
}

public struct FixtureBundle: Codable, Equatable, Sendable {
    public let version: Int
    public let notes: String
    public let shellStates: [String]
    public let fixtures: [String: FixtureAgents]

    public init(
        version: Int,
        notes: String,
        shellStates: [String],
        fixtures: [String: FixtureAgents]
    ) {
        self.version = version
        self.notes = notes
        self.shellStates = shellStates
        self.fixtures = fixtures
    }
}
