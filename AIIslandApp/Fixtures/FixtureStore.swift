import Foundation

final class FixtureStore {
    enum Error: Swift.Error, Equatable {
        case missingScenario(FixtureScenario)
    }

    private let bundle: FixtureBundle

    private(set) var currentScenario: FixtureScenario

    init(bundle: FixtureBundle, initialScenario: FixtureScenario = .bothIdle) throws {
        self.bundle = bundle
        self.currentScenario = initialScenario

        guard bundle.fixtures[initialScenario.rawValue] != nil else {
            throw Error.missingScenario(initialScenario)
        }
    }

    var currentFixtureName: String {
        currentScenario.rawValue
    }

    var allScenarios: [FixtureScenario] {
        FixtureScenario.allCases
    }

    var codex: AgentState {
        resolvedStates.codex
    }

    var claude: AgentState {
        resolvedStates.claude
    }

    func setScenario(_ scenario: FixtureScenario) throws {
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
