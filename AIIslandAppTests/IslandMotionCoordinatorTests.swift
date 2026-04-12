import XCTest

import AIIslandCore
@testable import AIIslandApp

@MainActor
final class IslandMotionCoordinatorTests: XCTestCase {
    func testProgressMovesContinuouslyWithoutResetWhenRetargetingToPinned() {
        let coordinator = IslandMotionCoordinator(
            tuning: IslandMotionTuning(
                tickInterval: 1.0 / 120.0,
                hoverTargetProgress: 0.86,
                pinnedTargetProgress: 1.0,
                preserveMomentumGain: 0.28,
                snapBackGain: 0.40,
                reducedMotionGain: 0.44
            )
        )

        coordinator.apply(shellState: .hoverExpanded)
        coordinator.advanceForTesting(deltaTime: 1.0 / 120.0)
        coordinator.advanceForTesting(deltaTime: 1.0 / 120.0)
        let hoverProgress = coordinator.motionProgress.progress
        XCTAssertGreaterThan(hoverProgress, 0.0)

        coordinator.apply(shellState: .pinnedExpanded)
        coordinator.advanceForTesting(deltaTime: 1.0 / 120.0)
        let pinnedProgress = coordinator.motionProgress.progress

        XCTAssertGreaterThanOrEqual(pinnedProgress, hoverProgress)
        XCTAssertEqual(coordinator.motionProgress.interruptionPolicy, .holdPinned)
    }

    func testCollapseUsesGentleSnapBackInterruptionPolicy() {
        let coordinator = IslandMotionCoordinator()
        coordinator.apply(shellState: .pinnedExpanded)
        coordinator.advanceForTesting(deltaTime: 1.0 / 120.0)

        coordinator.apply(shellState: .collapsed)
        coordinator.advanceForTesting(deltaTime: 1.0 / 120.0)

        XCTAssertEqual(coordinator.motionProgress.interruptionPolicy, .gentleSnapBack)
    }

    func testPhaseTransitionsFollowProgressBands() {
        let coordinator = IslandMotionCoordinator(
            tuning: IslandMotionTuning(
                tickInterval: 1.0 / 120.0,
                hoverTargetProgress: 0.86,
                pinnedTargetProgress: 1.0,
                preserveMomentumGain: 0.10,
                snapBackGain: 0.10,
                reducedMotionGain: 0.10
            )
        )

        coordinator.apply(shellState: .hoverExpanded)
        XCTAssertEqual(coordinator.phase, .lifting(origin: .hover))

        for _ in 0..<5 {
            coordinator.advanceForTesting(deltaTime: 1.0 / 120.0)
        }
        XCTAssertEqual(coordinator.phase, .promoting(origin: .hover))

        for _ in 0..<11 {
            coordinator.advanceForTesting(deltaTime: 1.0 / 120.0)
        }
        XCTAssertEqual(coordinator.phase, .contentReveal(origin: .hover))
    }

    func testDefaultTuningKeepsEarlyHoverExpansionInLiftingOrPromotingBand() {
        let coordinator = IslandMotionCoordinator()

        coordinator.apply(shellState: .hoverExpanded)
        for _ in 0..<6 {
            coordinator.advanceForTesting(deltaTime: 1.0 / 120.0)
        }

        XCTAssertLessThan(coordinator.motionProgress.progress, 0.68)
        XCTAssertTrue(
            coordinator.phase == .lifting(origin: .hover)
                || coordinator.phase == .promoting(origin: .hover)
        )
    }
}
