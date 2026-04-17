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

public enum AgentThreadTitleSource: String, Codable, Equatable, Sendable {
    case codexPromptSummary
    case codexSessionIndexHint
    case claudeTaskSummary
    case claudePromptSummary
    case workspaceFallback
    case unknown
}

public struct AgentThread: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String?
    public let workspaceLabel: String?
    public let modelLabel: String
    public let contextRatio: Double?
    public let state: AgentGlobalState
    public let lastUpdatedAt: Date?
    public let titleSource: AgentThreadTitleSource

    public var taskLabel: String {
        title
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case taskLabel
        case detail
        case workspaceLabel
        case modelLabel
        case contextRatio
        case state
        case lastUpdatedAt
        case titleSource
    }

    public init(
        id: String,
        title: String,
        detail: String?,
        workspaceLabel: String?,
        modelLabel: String,
        contextRatio: Double?,
        state: AgentGlobalState,
        lastUpdatedAt: Date?,
        titleSource: AgentThreadTitleSource
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.workspaceLabel = workspaceLabel
        self.modelLabel = modelLabel
        self.contextRatio = contextRatio
        self.state = state
        self.lastUpdatedAt = lastUpdatedAt
        self.titleSource = titleSource
    }

    public init(
        id: String,
        taskLabel: String,
        modelLabel: String,
        contextRatio: Double?,
        state: AgentGlobalState
    ) {
        self.init(
            id: id,
            title: taskLabel,
            detail: nil,
            workspaceLabel: nil,
            modelLabel: modelLabel,
            contextRatio: contextRatio,
            state: state,
            lastUpdatedAt: nil,
            titleSource: .unknown
        )
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? container.decodeIfPresent(String.self, forKey: .taskLabel)
            ?? id
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        workspaceLabel = try container.decodeIfPresent(String.self, forKey: .workspaceLabel)
        modelLabel = try container.decodeIfPresent(String.self, forKey: .modelLabel) ?? ""
        contextRatio = try container.decodeIfPresent(Double.self, forKey: .contextRatio)
        state = try container.decodeIfPresent(AgentGlobalState.self, forKey: .state) ?? .idle
        lastUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .lastUpdatedAt)
        titleSource = try container.decodeIfPresent(AgentThreadTitleSource.self, forKey: .titleSource) ?? .unknown
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(title, forKey: .taskLabel)
        try container.encodeIfPresent(detail, forKey: .detail)
        try container.encodeIfPresent(workspaceLabel, forKey: .workspaceLabel)
        try container.encode(modelLabel, forKey: .modelLabel)
        try container.encodeIfPresent(contextRatio, forKey: .contextRatio)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(lastUpdatedAt, forKey: .lastUpdatedAt)
        try container.encode(titleSource, forKey: .titleSource)
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
