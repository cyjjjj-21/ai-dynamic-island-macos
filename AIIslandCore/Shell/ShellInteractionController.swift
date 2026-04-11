import Combine
import Foundation

public protocol ShellInteractionScheduledTask: AnyObject {
    func cancel()
}

@MainActor
public protocol ShellInteractionScheduling {
    @discardableResult
    func schedule(
        after delay: TimeInterval,
        _ action: @MainActor @escaping () -> Void
    ) -> any ShellInteractionScheduledTask
}

@MainActor
public final class ShellInteractionController: ObservableObject {
    @Published public private(set) var state: ShellInteractionState

    private let graceDelay: TimeInterval
    private let scheduler: any ShellInteractionScheduling
    private var pendingCollapseTask: (any ShellInteractionScheduledTask)?

    public init(
        initialState: ShellInteractionState = .collapsed,
        graceDelay: TimeInterval = 0.25,
        scheduler: any ShellInteractionScheduling
    ) {
        self.state = initialState
        self.graceDelay = graceDelay
        self.scheduler = scheduler
    }

    public func send(_ input: ShellInteractionInput) {
        switch input {
        case .pointerEnterHotzone:
            handlePointerEnterHotzone()
        case .pointerLeaveHotzone:
            handlePointerLeaveHotzone()
        case .clickIsland:
            handlePrimaryClick()
        case .clickExpandedCard:
            handleExpandedCardClick()
        case .clickOutside:
            handleOutsideClick()
        case .escapeKey:
            handleEscapeKey()
        case .collapseAnimationCompleted:
            handleCollapseAnimationCompleted()
        }
    }

    private func handlePointerEnterHotzone() {
        switch state {
        case .collapsed:
            state = .hoverExpanded
        case .collapsing:
            cancelPendingCollapse()
            state = .hoverExpanded
        case .hoverExpanded:
            cancelPendingCollapse()
        case .pinnedExpanded:
            break
        }
    }

    private func handlePointerLeaveHotzone() {
        guard state == .hoverExpanded else {
            return
        }

        scheduleCollapseIfNeeded()
    }

    private func handlePrimaryClick() {
        switch state {
        case .collapsed, .hoverExpanded, .collapsing:
            cancelPendingCollapse()
            state = .pinnedExpanded
        case .pinnedExpanded:
            break
        }
    }

    private func handleExpandedCardClick() {
        switch state {
        case .collapsed, .collapsing:
            break
        case .hoverExpanded:
            cancelPendingCollapse()
            state = .pinnedExpanded
        case .pinnedExpanded:
            break
        }
    }

    private func handleOutsideClick() {
        guard state != .collapsed else {
            return
        }

        cancelPendingCollapse()
        state = .collapsed
    }

    private func handleEscapeKey() {
        guard state != .collapsed else {
            return
        }

        cancelPendingCollapse()
        state = .collapsed
    }

    private func handleCollapseAnimationCompleted() {
        guard state == .collapsing else {
            return
        }

        cancelPendingCollapse()
        state = .collapsed
    }

    private func scheduleCollapseIfNeeded() {
        guard pendingCollapseTask == nil else {
            return
        }

        pendingCollapseTask = scheduler.schedule(after: graceDelay) { [weak self] in
            self?.beginCollapseIfStillHoverExpanded()
        }
    }

    private func beginCollapseIfStillHoverExpanded() {
        pendingCollapseTask = nil

        guard state == .hoverExpanded else {
            return
        }

        state = .collapsing
    }

    private func cancelPendingCollapse() {
        pendingCollapseTask?.cancel()
        pendingCollapseTask = nil
    }
}
