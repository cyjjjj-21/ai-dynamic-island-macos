import Foundation

public final class FixtureStore {
    public enum Error: Swift.Error, Equatable {
        case missingScenario(FixtureScenario)
    }

    private let bundle: FixtureBundle

    public private(set) var currentScenario: FixtureScenario

    public init(bundle: FixtureBundle, initialScenario: FixtureScenario = .bothIdle) throws {
        self.bundle = bundle
        self.currentScenario = initialScenario

        guard bundle.fixtures[initialScenario.rawValue] != nil else {
            throw Error.missingScenario(initialScenario)
        }
    }

    public var currentFixtureName: String {
        currentScenario.rawValue
    }

    public var allScenarios: [FixtureScenario] {
        FixtureScenario.allCases.filter { bundle.fixtures[$0.rawValue] != nil }
    }

    public var codex: AgentState {
        resolvedStates.codex
    }

    public var claude: AgentState {
        resolvedStates.claude
    }

    public func setScenario(_ scenario: FixtureScenario) throws {
        guard bundle.fixtures[scenario.rawValue] != nil else {
            throw Error.missingScenario(scenario)
        }

        currentScenario = scenario
    }

    private var resolvedStates: FixtureAgents {
        guard let states = bundle.fixtures[currentScenario.rawValue] else {
            preconditionFailure("Missing fixture for scenario \(currentScenario.rawValue)")
        }

        return states
    }
}
