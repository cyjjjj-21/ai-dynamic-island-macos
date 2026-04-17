import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var islandWindowController: IslandWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let reviewConfiguration = AppReviewConfiguration.fromLaunchContext(
            environment: ProcessInfo.processInfo.environment,
            arguments: CommandLine.arguments
        )
        let islandWindowController = IslandWindowController(
            initialShellState: reviewConfiguration?.shellState ?? .collapsed,
            reviewConfiguration: reviewConfiguration
        )
        islandWindowController.showIsland()
        self.islandWindowController = islandWindowController
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
