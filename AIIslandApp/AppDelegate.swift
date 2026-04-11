import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var islandWindowController: IslandWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let islandWindowController = IslandWindowController()
        islandWindowController.showIsland()
        self.islandWindowController = islandWindowController
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
