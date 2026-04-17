import Foundation

import AIIslandCore

struct AppReviewConfiguration: Equatable, Sendable {
    static let shellStateEnvironmentKey = "AIISLAND_REVIEW_STATE"
    static let fixtureScenarioEnvironmentKey = "AIISLAND_REVIEW_SCENARIO"
    static let shellStateArgumentKey = "--review-state"
    static let fixtureScenarioArgumentKey = "--review-scenario"

    let shellState: ShellInteractionState?
    let fixtureScenario: FixtureScenario?

    static func fromEnvironment(_ environment: [String: String]) -> Self? {
        fromLaunchContext(environment: environment, arguments: [])
    }

    static func fromLaunchContext(
        environment: [String: String],
        arguments: [String]
    ) -> Self? {
        let shellStateRawValue = argumentValue(
            for: shellStateArgumentKey,
            arguments: arguments
        ) ?? environment[shellStateEnvironmentKey]
        let fixtureScenarioRawValue = argumentValue(
            for: fixtureScenarioArgumentKey,
            arguments: arguments
        ) ?? environment[fixtureScenarioEnvironmentKey]

        let shellState = shellStateRawValue
            .flatMap(ShellInteractionState.init(rawValue:))
        let fixtureScenario = fixtureScenarioRawValue
            .flatMap(FixtureScenario.init(rawValue:))

        guard shellState != nil || fixtureScenario != nil else {
            return nil
        }

        return Self(shellState: shellState, fixtureScenario: fixtureScenario)
    }

    private static func argumentValue(
        for key: String,
        arguments: [String]
    ) -> String? {
        guard let index = arguments.firstIndex(of: key) else {
            return nil
        }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
            return nil
        }
        return arguments[valueIndex]
    }

}

enum ReviewFixtureResolver {
    static func resolve(_ configuration: AppReviewConfiguration?) -> FixtureAgents? {
        guard let scenario = configuration?.fixtureScenario else {
            return nil
        }

        guard let url = FixtureBundleMarker.bundle.url(
            forResource: "phase1-fixtures",
            withExtension: "json"
        ) else {
            return nil
        }

        guard let bundle = try? FixtureBundleLoader.load(from: url) else {
            return nil
        }

        guard let fixture = bundle.fixtures[scenario.rawValue] else {
            return nil
        }

        return normalizeForReview(fixture)
    }

    static func normalizeForReview(
        _ fixture: FixtureAgents,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> FixtureAgents {
        FixtureAgents(
            codex: normalizeQuotaDates(in: fixture.codex, now: now, calendar: calendar),
            claude: normalizeQuotaDates(in: fixture.claude, now: now, calendar: calendar)
        )
    }

    private static func normalizeQuotaDates(
        in state: AgentState,
        now: Date,
        calendar: Calendar
    ) -> AgentState {
        guard let quota = state.quota else {
            return state
        }

        let normalizedQuota = AgentQuota(
            availability: quota.availability,
            fiveHourRatio: quota.fiveHourRatio,
            weeklyRatio: quota.weeklyRatio,
            fiveHourResetsAt: quota.fiveHourResetsAt ?? now.addingTimeInterval((4 * 3600) + (11 * 60)),
            weeklyResetsAt: quota.weeklyResetsAt ?? synthesizedWeeklyResetDate(from: now, calendar: calendar)
        )

        return AgentState(
            kind: state.kind,
            online: state.online,
            availability: state.availability,
            globalState: state.globalState,
            threads: state.threads,
            quota: normalizedQuota
        )
    }

    private static func synthesizedWeeklyResetDate(
        from now: Date,
        calendar: Calendar
    ) -> Date {
        let baseDate = calendar.date(byAdding: .day, value: 2, to: now) ?? now
        return calendar.date(
            bySettingHour: 9,
            minute: 19,
            second: 0,
            of: baseDate
        ) ?? baseDate.addingTimeInterval((2 * 24 * 3600) + (9 * 3600) + (19 * 60))
    }
}
