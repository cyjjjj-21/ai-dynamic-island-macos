import AIIslandCore

enum ShellMotionStateReconciler {
    static func inputForMotionPhaseChange(
        _ phase: IslandMotionPhase,
        shellState: ShellInteractionState
    ) -> ShellInteractionInput? {
        guard phase == .collapsed, shellState == .collapsing else {
            return nil
        }

        return .collapseAnimationCompleted
    }
}
