import Foundation

import AIIslandCore

struct AgentSectionPresentation: Equatable, Sendable {
    let kind: AgentKind
    let title: String
    let primaryStatusCopy: String
    let emptyStateCopy: String?
    let quotaPresentation: QuotaStripPresentation?
    let visibleThreads: [ThreadRowPresentation]
    let overflowCount: Int

    var overflowSummaryCopy: String? {
        guard overflowCount > 0 else {
            return nil
        }

        return "+\(overflowCount) more"
    }

    init(state: AgentState) {
        kind = state.kind
        title = state.kind == .codex ? "Codex" : "Claude Code"
        primaryStatusCopy = FallbackRenderingRules.primaryStatusCopy(for: state)
        emptyStateCopy = FallbackRenderingRules.emptyStateCopy(for: state)
        quotaPresentation = FallbackRenderingRules.quotaPresentation(for: state)
        visibleThreads = FallbackRenderingRules.visibleThreads(for: state).map(ThreadRowPresentation.init)
        overflowCount = FallbackRenderingRules.overflowCount(for: state)
    }
}

struct ThreadRowPresentation: Identifiable, Equatable, Sendable {
    let id: String
    let taskLabel: String
    let modelLabel: String
    let contextCopy: String
    let state: AgentGlobalState

    init(thread: AgentThread) {
        id = thread.id
        taskLabel = thread.taskLabel
        modelLabel = ModelLabelFormatter.displayName(for: thread.modelLabel)
        contextCopy = FallbackRenderingRules.contextCopy(for: thread.contextRatio)
        state = thread.state
    }

    var stateCopy: String {
        switch state {
        case .idle:
            return "Idle"
        case .thinking:
            return "Thinking"
        case .working:
            return "Working"
        case .attention:
            return "Attention"
        case .offline:
            return "Offline"
        }
    }
}

struct QuotaStripPresentation: Equatable, Sendable {
    let availabilityCopy: String?
    let fiveHourRatio: Double?
    let weeklyRatio: Double?

    var fiveHourCopy: String {
        FallbackRenderingRules.percentageCopy(for: fiveHourRatio)
    }

    var weeklyCopy: String {
        FallbackRenderingRules.percentageCopy(for: weeklyRatio)
    }
}

enum FallbackRenderingRules {
    static let maximumVisibleThreads = 3

    static func primaryStatusCopy(for state: AgentState) -> String {
        if !state.online || state.availability == .offline || state.globalState == .offline {
            return "Not running"
        }

        if state.availability == .statusUnavailable {
            return "Status unavailable"
        }

        switch state.globalState {
        case .idle:
            return "Idle"
        case .thinking:
            return "Thinking"
        case .working:
            return "Working"
        case .attention:
            return "Attention"
        case .offline:
            return "Not running"
        }
    }

    static func emptyStateCopy(for state: AgentState) -> String? {
        guard state.threads.isEmpty else {
            return nil
        }

        let primaryStatus = primaryStatusCopy(for: state)
        if primaryStatus == "Idle" {
            return "No active threads"
        }

        return primaryStatus
    }

    static func quotaPresentation(for state: AgentState) -> QuotaStripPresentation? {
        guard state.kind == .codex else {
            return nil
        }

        guard state.online, state.availability != .offline, state.globalState != .offline else {
            return nil
        }

        let quota = state.quota
        return QuotaStripPresentation(
            availabilityCopy: quota?.availability == .unavailable ? "Quota unavailable" : nil,
            fiveHourRatio: quota?.fiveHourRatio,
            weeklyRatio: quota?.weeklyRatio
        )
    }

    static func visibleThreads(for state: AgentState) -> [AgentThread] {
        Array(state.threads.prefix(maximumVisibleThreads))
    }

    static func overflowCount(for state: AgentState) -> Int {
        max(state.threads.count - maximumVisibleThreads, 0)
    }

    static func contextCopy(for ratio: Double?) -> String {
        guard let ratio else {
            return "Context --"
        }

        let percentage = Int((ratio * 100).rounded())
        return "Context \(percentage)%"
    }

    static func percentageCopy(for ratio: Double?) -> String {
        guard let ratio else {
            return "--"
        }

        let percentage = Int((ratio * 100).rounded())
        return "\(percentage)%"
    }
}
