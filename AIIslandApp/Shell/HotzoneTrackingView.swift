import AppKit

final class HotzoneTrackingView: NSView {
    var onPointerEntered: (() -> Void)?
    var onPointerExited: (() -> Void)?
    var onMouseDown: ((CGPoint) -> Void)?
    var onEscapeKey: (() -> Void)?
    var containsInteractivePoint: ((CGPoint) -> Bool)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isPointerInside = false

    override var isFlipped: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        if window == nil {
            removeMonitors()
            forcePointerExit()
        } else {
            installMonitorsIfNeeded()
            syncPointerState()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        syncPointerState()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncPointerState()
    }

    func syncPointerState() {
        guard let window else {
            forcePointerExit()
            return
        }

        let screenPoint = NSEvent.mouseLocation
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let localPoint = convert(windowPoint, from: nil)
        let pointerIsInside = containsInteractivePoint?(localPoint) ?? bounds.contains(localPoint)

        guard pointerIsInside != isPointerInside else {
            return
        }

        isPointerInside = pointerIsInside
        if pointerIsInside {
            onPointerEntered?()
        } else {
            onPointerExited?()
        }
    }

    func forcePointerExit() {
        guard isPointerInside else {
            return
        }

        isPointerInside = false
        onPointerExited?()
    }

    private func installMonitorsIfNeeded() {
        guard globalMonitor == nil, localMonitor == nil else {
            return
        }

        let eventMask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .keyDown,
        ]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] event in
            DispatchQueue.main.async {
                self?.handleObservedEvent(event)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            self?.handleObservedEvent(event)
            return event
        }
    }

    private func handleObservedEvent(_ event: NSEvent) {
        switch event.type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            syncPointerState()
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            syncPointerState()
            handleMouseDown(event)
        case .keyDown:
            handleKeyDown(event)
        default:
            break
        }
    }

    private func handleMouseDown(_ event: NSEvent) {
        onMouseDown?(NSEvent.mouseLocation)
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard event.keyCode == 53 || event.charactersIgnoringModifiers == "\u{1B}" else {
            return
        }

        onEscapeKey?()
    }

    private func removeMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }
}
