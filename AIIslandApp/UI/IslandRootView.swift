import SwiftUI

import AIIslandCore

struct IslandRootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var motionCoordinator = IslandMotionCoordinator()
    @ObservedObject private var shellInteractionController: ShellInteractionController
    @StateObject private var codexMonitor = CodexMonitor()
    @StateObject private var claudeMonitor = ClaudeCodeMonitor()

    init(shellInteractionController: ShellInteractionController) {
        _shellInteractionController = ObservedObject(wrappedValue: shellInteractionController)
    }

    var body: some View {
        PromotionContainerView(
            coordinator: motionCoordinator,
            codex: codexMonitor.codexState,
            claude: claudeMonitor.claudeState
        )
            .frame(width: IslandPalette.canvasWidth, height: IslandPalette.canvasHeight, alignment: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
            .onAppear {
                codexMonitor.start()
                claudeMonitor.start()
                motionCoordinator.configure(reducedMotionEnabled: reduceMotion)
                motionCoordinator.apply(shellState: shellInteractionController.state)
            }
            .onDisappear {
                codexMonitor.stop()
                claudeMonitor.stop()
            }
            .onChange(of: shellInteractionController.state) { _, newValue in
                motionCoordinator.apply(shellState: newValue)
            }
            .onChange(of: reduceMotion) { _, newValue in
                motionCoordinator.configure(reducedMotionEnabled: newValue)
            }
    }
}
