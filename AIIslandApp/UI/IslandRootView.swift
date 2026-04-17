import SwiftUI

import AIIslandCore

struct IslandRootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var motionCoordinator = IslandMotionCoordinator()
    @ObservedObject private var shellInteractionController: ShellInteractionController
    @StateObject private var codexMonitor = CodexMonitor()
    @StateObject private var claudeMonitor = ClaudeCodeMonitor()
    private let reviewConfiguration: AppReviewConfiguration?
    private let reviewAgents: FixtureAgents?

    init(
        shellInteractionController: ShellInteractionController,
        reviewConfiguration: AppReviewConfiguration? = nil
    ) {
        _shellInteractionController = ObservedObject(wrappedValue: shellInteractionController)
        self.reviewConfiguration = reviewConfiguration
        self.reviewAgents = ReviewFixtureResolver.resolve(reviewConfiguration)
    }

    var body: some View {
        let codexState = reviewAgents?.codex ?? codexMonitor.codexState
        let claudeState = reviewAgents?.claude ?? claudeMonitor.claudeState
        let codexDiagnostics = reviewAgents == nil
            ? codexMonitor.diagnostics
            : AgentMonitorDiagnostics.empty(
                kind: .codex,
                freshnessPolicy: .v02Smooth,
                triggerMode: "review"
            )
        let claudeDiagnostics = reviewAgents == nil
            ? claudeMonitor.diagnostics
            : AgentMonitorDiagnostics.empty(
                kind: .claude,
                freshnessPolicy: .v02Smooth,
                triggerMode: "review"
            )

        PromotionContainerView(
            coordinator: motionCoordinator,
            codex: codexState,
            claude: claudeState,
            codexDiagnostics: codexDiagnostics,
            claudeDiagnostics: claudeDiagnostics
        )
            .frame(width: IslandPalette.canvasWidth, height: IslandPalette.canvasHeight, alignment: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
            .onAppear {
                if reviewAgents == nil {
                    codexMonitor.start()
                    claudeMonitor.start()
                }
                motionCoordinator.configure(reducedMotionEnabled: reduceMotion)
                motionCoordinator.apply(shellState: shellInteractionController.state)
            }
            .onDisappear {
                if reviewAgents == nil {
                    codexMonitor.stop()
                    claudeMonitor.stop()
                }
            }
            .onChange(of: shellInteractionController.state) { _, newValue in
                motionCoordinator.apply(shellState: newValue)
            }
            .onChange(of: motionCoordinator.phase) { _, newValue in
                guard let input = ShellMotionStateReconciler.inputForMotionPhaseChange(
                    newValue,
                    shellState: shellInteractionController.state
                ) else {
                    return
                }

                shellInteractionController.send(input)
            }
            .onChange(of: reduceMotion) { _, newValue in
                motionCoordinator.configure(reducedMotionEnabled: newValue)
            }
    }
}
