import Combine
import AppKit
import SwiftUI

import AIIslandCore

@MainActor
final class IslandWindowController: NSWindowController {
    private let canvasLayout = IslandCanvasLayout.default
    private let islandSize = NSSize(width: IslandPalette.canvasWidth, height: IslandPalette.canvasHeight)
    private let islandWindow: NSPanel
    private let shellInteractionController: ShellInteractionController
    private let expandedCardInteractionModel = ExpandedCardInteractionModel()
    private let hotzoneView = HotzoneTrackingView()
    private var hostingView: NSHostingView<IslandRootView>!
    private var cancellables: Set<AnyCancellable> = []

    init(
        initialShellState: ShellInteractionState = .collapsed,
        reviewConfiguration: AppReviewConfiguration? = nil
    ) {
        let panel = IslandPanel(
            contentRect: NSRect(origin: .zero, size: islandSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary,
        ]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        islandWindow = panel
        panel.contentView = hotzoneView

        shellInteractionController = ShellInteractionController(
            initialState: initialShellState,
            scheduler: MainQueueShellInteractionScheduler()
        )

        super.init(window: panel)

        hostingView = NSHostingView(
            rootView: IslandRootView(
                shellInteractionController: shellInteractionController,
                expandedCardInteractionModel: expandedCardInteractionModel,
                reviewConfiguration: reviewConfiguration
            )
        )
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        hotzoneView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: hotzoneView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: hotzoneView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: hotzoneView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: hotzoneView.bottomAnchor),
        ])

        hotzoneView.containsInteractivePoint = { [weak self] point in
            guard let self else {
                return false
            }

            return self.canvasLayout.containsPointer(
                point,
                shellState: self.shellInteractionController.state,
                expandedCardInteractiveHeight: self.expandedCardInteractionModel.interactiveHeight
            )
        }
        expandedCardInteractionModel.onInteractionBoundsChanged = { [weak self] in
            self?.hotzoneView.syncPointerState()
        }

        configureHotzoneCallbacks()
        bindShellState()
        installNotificationObservers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showIsland() {
        positionWindow()
        islandWindow.orderFront(nil)
        hotzoneView.syncPointerState()
    }

    private func configureHotzoneCallbacks() {
        hotzoneView.onPointerEntered = { [weak self] in
            self?.handlePointerEntered()
        }
        hotzoneView.onPointerExited = { [weak self] in
            self?.handlePointerExited()
        }
        hotzoneView.onMouseDown = { [weak self] screenPoint in
            self?.handleMouseDown(at: screenPoint)
        }
        hotzoneView.onEscapeKey = { [weak self] in
            self?.handleEscapeKey()
        }
        hotzoneView.onToggleDiagnostics = { [weak self] in
            self?.toggleDiagnostics()
        }
    }

    private func handlePointerEntered() {
        shellInteractionController.send(.pointerEnterHotzone)
    }

    private func handlePointerExited() {
        shellInteractionController.send(.pointerLeaveHotzone)
    }

    private func handleMouseDown(at screenPoint: CGPoint) {
        guard let localPoint = localPoint(fromScreenPoint: screenPoint) else {
            return
        }

        if canvasLayout.containsShellPoint(localPoint) {
            shellInteractionController.send(.clickIsland)
            islandWindow.orderFront(nil)
            hotzoneView.syncPointerState()
            return
        }

        if canvasLayout.containsExpandedCardInteractivePoint(
            localPoint,
            expandedCardInteractiveHeight: expandedCardInteractionModel.interactiveHeight
        ) {
            shellInteractionController.send(.clickExpandedCard)
            islandWindow.orderFront(nil)
            hotzoneView.syncPointerState()
            return
        }

        guard shellInteractionController.state != .collapsed else {
            return
        }

        shellInteractionController.send(.clickOutside)
        islandWindow.resignKey()
        hotzoneView.syncPointerState()
    }

    private func handleEscapeKey() {
        guard shellInteractionController.state != .collapsed else {
            return
        }

        shellInteractionController.send(.escapeKey)
        islandWindow.resignKey()
        hotzoneView.syncPointerState()
    }

    private func toggleDiagnostics() {
        let key = IslandPalette.diagnosticsUserDefaultsKey
        let current = UserDefaults.standard.bool(forKey: key)
        UserDefaults.standard.set(!current, forKey: key)
    }

    private func localPoint(fromScreenPoint screenPoint: CGPoint) -> CGPoint? {
        guard islandWindow.windowNumber >= 0 else {
            return nil
        }

        let windowPoint = islandWindow.convertPoint(fromScreen: screenPoint)
        return hotzoneView.convert(windowPoint, from: nil)
    }

    private func positionWindow() {
        guard let screen = anchoredScreen() else {
            return
        }

        let centerX = notchAnchorCenterX(for: screen)
        let x = centerX - islandSize.width / 2
        let y = screen.frame.maxY - islandSize.height
        islandWindow.setFrameOrigin(NSPoint(x: x, y: y))
        hotzoneView.syncPointerState()
    }

    private func bindShellState() {
        shellInteractionController.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.hotzoneView.syncPointerState()
            }
            .store(in: &cancellables)
    }

    private func installNotificationObservers() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleScreenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleActiveSpaceDidChange(_:)),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    @objc
    private func handleScreenParametersDidChange(_ notification: Notification) {
        reanchorAndResetHover()
    }

    @objc
    private func handleActiveSpaceDidChange(_ notification: Notification) {
        reanchorAndResetHover()
    }

    private func reanchorAndResetHover() {
        hotzoneView.forcePointerExit()
        positionWindow()
    }

    private func anchoredScreen() -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return nil
        }

        return screens.max { lhs, rhs in
            menuBarHeight(for: lhs) < menuBarHeight(for: rhs)
        }
    }

    private func menuBarHeight(for screen: NSScreen) -> CGFloat {
        screen.frame.maxY - screen.visibleFrame.maxY
    }

    private func safeTopInset(for screen: NSScreen) -> CGFloat {
        if #available(macOS 12.0, *) {
            return max(screen.safeAreaInsets.top, 0)
        }

        return max(menuBarHeight(for: screen), 0)
    }

    private func notchAnchorCenterX(for screen: NSScreen) -> CGFloat {
        let correction = IslandPalette.notchCenterXCorrection

        if #available(macOS 12.0, *) {
            if
                let leftArea = screen.auxiliaryTopLeftArea,
                let rightArea = screen.auxiliaryTopRightArea,
                !leftArea.isEmpty,
                !rightArea.isEmpty
            {
                return (leftArea.maxX + rightArea.minX) / 2 + correction
            }
        }

        return screen.frame.midX + correction
    }
}

@MainActor
private final class MainQueueShellInteractionScheduler: ShellInteractionScheduling {
    private final class Task: ShellInteractionScheduledTask {
        private let workItem: DispatchWorkItem

        init(workItem: DispatchWorkItem) {
            self.workItem = workItem
        }

        func cancel() {
            workItem.cancel()
        }
    }

    func schedule(
        after delay: TimeInterval,
        _ action: @MainActor @escaping () -> Void
    ) -> any ShellInteractionScheduledTask {
        let workItem = DispatchWorkItem {
            Swift.Task { @MainActor in
                action()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        return Task(workItem: workItem)
    }
}
