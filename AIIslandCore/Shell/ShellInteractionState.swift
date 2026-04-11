import Foundation

public enum ShellInteractionState: String, Equatable, Sendable {
    case collapsed
    case hoverExpanded
    case pinnedExpanded
    case collapsing
}

public enum ShellInteractionInput: String, Equatable, Sendable {
    case pointerEnterHotzone
    case pointerLeaveHotzone
    case clickIsland
    case clickExpandedCard
    case clickOutside
    case escapeKey
    case collapseAnimationCompleted
}
