import Foundation
import XCTest
@testable import AIIslandCore

@MainActor
final class ShellInteractionControllerTests: XCTestCase {
    @MainActor
    func testTransitionTableCoversClosedShellInputs() {
        let cases: [(ShellInteractionState, ShellInteractionInput, ShellInteractionState)] = [
            (.collapsed, .pointerEnterHotzone, .hoverExpanded),
            (.collapsed, .pointerLeaveHotzone, .collapsed),
            (.collapsed, .clickIsland, .pinnedExpanded),
            (.collapsed, .clickExpandedCard, .collapsed),
            (.collapsed, .clickOutside, .collapsed),
            (.collapsed, .escapeKey, .collapsed),
            (.collapsed, .collapseAnimationCompleted, .collapsed),
            (.hoverExpanded, .pointerEnterHotzone, .hoverExpanded),
            (.hoverExpanded, .pointerLeaveHotzone, .hoverExpanded),
            (.hoverExpanded, .clickIsland, .pinnedExpanded),
            (.hoverExpanded, .clickExpandedCard, .pinnedExpanded),
            (.hoverExpanded, .clickOutside, .collapsed),
            (.hoverExpanded, .escapeKey, .collapsed),
            (.hoverExpanded, .collapseAnimationCompleted, .hoverExpanded),
            (.pinnedExpanded, .pointerEnterHotzone, .pinnedExpanded),
            (.pinnedExpanded, .pointerLeaveHotzone, .pinnedExpanded),
            (.pinnedExpanded, .clickIsland, .pinnedExpanded),
            (.pinnedExpanded, .clickExpandedCard, .pinnedExpanded),
            (.pinnedExpanded, .clickOutside, .collapsed),
            (.pinnedExpanded, .escapeKey, .collapsed),
            (.pinnedExpanded, .collapseAnimationCompleted, .pinnedExpanded),
            (.collapsing, .pointerEnterHotzone, .hoverExpanded),
            (.collapsing, .pointerLeaveHotzone, .collapsing),
            (.collapsing, .clickIsland, .pinnedExpanded),
            (.collapsing, .clickExpandedCard, .collapsing),
            (.collapsing, .clickOutside, .collapsed),
            (.collapsing, .escapeKey, .collapsed),
            (.collapsing, .collapseAnimationCompleted, .collapsed)
        ]

        for (state, input, expected) in cases {
            let harness = makeHarness(initialState: state)
            harness.controller.send(input)
            XCTAssertEqual(
                harness.controller.state,
                expected,
                "Unexpected transition for \(state) + \(input)"
            )
        }
    }

    @MainActor
    func testCollapsedClickIslandPinsExpanded() {
        let harness = makeHarness(initialState: .collapsed)

        harness.controller.send(.clickIsland)

        XCTAssertEqual(harness.controller.state, .pinnedExpanded)
    }

    @MainActor
    func testPointerLeaveHotzoneSchedulesCollapseAfterGraceDelay() {
        let harness = makeHarness(initialState: .hoverExpanded, graceDelay: 0.5)

        harness.controller.send(.pointerLeaveHotzone)
        XCTAssertEqual(harness.controller.state, .hoverExpanded)
        XCTAssertEqual(harness.scheduler.scheduledTaskCount, 1)

        harness.scheduler.advance(by: 0.25)
        XCTAssertEqual(harness.controller.state, .hoverExpanded)

        harness.scheduler.advance(by: 0.25)
        XCTAssertEqual(harness.controller.state, .collapsing)
    }

    @MainActor
    func testPointerEnterHotzoneDuringGracePeriodCancelsScheduledCollapse() {
        let harness = makeHarness(initialState: .hoverExpanded, graceDelay: 0.5)

        harness.controller.send(.pointerLeaveHotzone)
        harness.controller.send(.pointerEnterHotzone)
        XCTAssertEqual(harness.controller.state, .hoverExpanded)

        harness.scheduler.advance(by: 1.0)

        XCTAssertEqual(harness.controller.state, .hoverExpanded)
        XCTAssertEqual(harness.scheduler.firedTaskCount, 0)
    }

    @MainActor
    func testCollapsingPointerEnterReturnsToHoverExpanded() {
        let harness = makeHarness(initialState: .hoverExpanded, graceDelay: 0.5)

        harness.controller.send(.pointerLeaveHotzone)
        harness.scheduler.advance(by: 0.5)

        XCTAssertEqual(harness.controller.state, .collapsing)

        harness.controller.send(.pointerEnterHotzone)

        XCTAssertEqual(harness.controller.state, .hoverExpanded)
    }

    @MainActor
    func testPinnedStateIgnoresClickIsland() {
        let harness = makeHarness(initialState: .pinnedExpanded)

        harness.controller.send(.clickIsland)

        XCTAssertEqual(harness.controller.state, .pinnedExpanded)
    }

    @MainActor
    func testOutsideClickCollapsesFromPinnedExpanded() {
        let harness = makeHarness(initialState: .pinnedExpanded)

        harness.controller.send(.clickOutside)

        XCTAssertEqual(harness.controller.state, .collapsed)
    }

    @MainActor
    func testEscapeCollapsesFromHoverExpanded() {
        let harness = makeHarness(initialState: .hoverExpanded)

        harness.controller.send(.escapeKey)

        XCTAssertEqual(harness.controller.state, .collapsed)
    }

    @MainActor
    func testCollapseAnimationCompletedCollapsesFromCollapsing() {
        let harness = makeHarness(initialState: .collapsing)

        harness.controller.send(.collapseAnimationCompleted)

        XCTAssertEqual(harness.controller.state, .collapsed)
    }

    @MainActor
    private func makeHarness(
        initialState: ShellInteractionState = .collapsed,
        graceDelay: TimeInterval = 0.25
    ) -> Harness {
        let scheduler = ManualShellInteractionScheduler()
        let controller = ShellInteractionController(
            initialState: initialState,
            graceDelay: graceDelay,
            scheduler: scheduler
        )
        return Harness(controller: controller, scheduler: scheduler)
    }
}

@MainActor
private struct Harness {
    let controller: ShellInteractionController
    let scheduler: ManualShellInteractionScheduler
}

@MainActor
private final class ManualShellInteractionScheduler: ShellInteractionScheduling {
    private final class Task: ShellInteractionScheduledTask {
        private(set) var isCancelled = false

        func cancel() {
            isCancelled = true
        }
    }

    private struct ScheduledAction {
        let deadline: TimeInterval
        let task: Task
        let action: @MainActor () -> Void
    }

    private(set) var scheduledTaskCount = 0
    private(set) var firedTaskCount = 0
    private var now: TimeInterval = 0
    private var scheduledActions: [ScheduledAction] = []

    func schedule(
        after delay: TimeInterval,
        _ action: @MainActor @escaping () -> Void
    ) -> any ShellInteractionScheduledTask {
        let task = Task()
        scheduledTaskCount += 1
        scheduledActions.append(
            ScheduledAction(
                deadline: now + delay,
                task: task,
                action: action
            )
        )
        return task
    }

    func advance(by interval: TimeInterval) {
        now += interval

        while true {
            guard let index = scheduledActions.firstIndex(where: { $0.deadline <= now }) else {
                return
            }

            let action = scheduledActions.remove(at: index)
            guard !action.task.isCancelled else {
                continue
            }

            firedTaskCount += 1
            action.action()
        }
    }
}
