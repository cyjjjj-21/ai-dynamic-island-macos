import Foundation

import AIIslandCore

struct AgentSectionPresentation: Equatable, Sendable {
    let kind: AgentKind
    let title: String
    let globalState: AgentGlobalState
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
        self.init(state: state, now: Date())
    }

    init(state: AgentState, now: Date) {
        kind = state.kind
        title = state.kind == .codex ? "Codex" : "Claude Code"
        globalState = state.globalState
        primaryStatusCopy = FallbackRenderingRules.primaryStatusCopy(for: state)
        emptyStateCopy = FallbackRenderingRules.emptyStateCopy(for: state)
        quotaPresentation = FallbackRenderingRules.quotaPresentation(for: state)
        visibleThreads = FallbackRenderingRules.visibleThreads(for: state)
            .enumerated()
            .map { index, thread in
                ThreadRowPresentation(thread: thread, isPrimary: index == 0, now: now)
            }
        overflowCount = FallbackRenderingRules.overflowCount(for: state)
    }
}

struct ThreadRowPresentation: Identifiable, Equatable, Sendable {
    let id: String
    let threadTitle: String
    let taskLabel: String
    let detailCopy: String
    let modelLabel: String
    let contextCopy: String
    let recencyCopy: String?
    let state: AgentGlobalState
    let isPrimary: Bool

    init(thread: AgentThread) {
        self.init(thread: thread, isPrimary: false, now: Date())
    }

    init(thread: AgentThread, isPrimary: Bool, now: Date) {
        id = thread.id
        threadTitle = thread.title
        taskLabel = thread.title
        detailCopy = Self.compactStateCopy(detail: thread.detail, state: thread.state)
        modelLabel = ModelLabelFormatter.displayName(for: thread.modelLabel)
        contextCopy = FallbackRenderingRules.contextCopy(for: thread.contextRatio)
        recencyCopy = FallbackRenderingRules.recencyCopy(for: thread.lastUpdatedAt, now: now)
        state = thread.state
        self.isPrimary = isPrimary
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

    private static func compactStateCopy(detail: String?, state: AgentGlobalState) -> String {
        if let detail, !detail.isEmpty {
            return detail
        }

        switch state {
        case .idle:
            return "最近活跃"
        case .thinking:
            return "思考中"
        case .working:
            return "执行工具中"
        case .attention:
            return "等待确认"
        case .offline:
            return "未运行"
        }
    }
}

struct QuotaStripPresentation: Equatable, Sendable {
    let availabilityCopy: String?
    let fiveHourRatio: Double?
    let weeklyRatio: Double?
    let fiveHourResetsAt: Date?
    let weeklyResetsAt: Date?

    var fiveHourCopy: String {
        FallbackRenderingRules.percentageCopy(for: fiveHourRatio)
    }

    var weeklyCopy: String {
        FallbackRenderingRules.percentageCopy(for: weeklyRatio)
    }

    var fiveHourRefreshCopy: String? {
        guard let resetsAt = fiveHourResetsAt else { return nil }
        return formatCountdown(until: resetsAt)
    }

    var weeklyRefreshCopy: String? {
        guard let resetsAt = weeklyResetsAt else { return nil }
        return formatDateTime(resetsAt)
    }
}

private func formatCountdown(until date: Date) -> String {
    let now = Date()
    let interval = date.timeIntervalSince(now)
    guard interval > 0 else { return "即将刷新" }

    let hours = Int(interval) / 3600
    let minutes = (Int(interval) % 3600) / 60

    if hours > 0 {
        return "\(hours)小时\(minutes)分钟后刷新"
    } else if minutes > 0 {
        return "\(minutes)分钟后刷新"
    } else {
        return "即将刷新"
    }
}

private func formatDateTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "M月d日HH时mm分刷新"
    return formatter.string(from: date)
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
            weeklyRatio: quota?.weeklyRatio,
            fiveHourResetsAt: quota?.fiveHourResetsAt,
            weeklyResetsAt: quota?.weeklyResetsAt
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

    static func recencyCopy(for date: Date?, now: Date) -> String? {
        guard let date else {
            return nil
        }

        let delta = Int(max(0, now.timeIntervalSince(date)))
        if delta < 60 {
            return "\(delta)s"
        }
        if delta < 3600 {
            return "\(delta / 60)m"
        }
        return "\(delta / 3600)h"
    }
}
