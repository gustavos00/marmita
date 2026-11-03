import AppKit
import MarmitaCore

/// Watches mouse drags system-wide. When a window is being dragged and the
/// modifier is held, it shows the zones; releasing the mouse over a zone snaps
/// the window into it.
@MainActor
final class DragSnapper {
    private let state: AppState
    private let overlay: OverlayController
    private var monitors: [Any] = []
    private var window: AXWindow?
    private var startFrame: CGRect?
    private var isWindowDrag = false
    private var lastCheck = Date.distantPast
    private var target: ZoneTarget?

    init(state: AppState, overlay: OverlayController) {
        self.state = state
        self.overlay = overlay
    }

    /// (Re)installs the global monitors. Called again once Accessibility is
    /// granted, since monitors added before that receive no key events.
    func start() {
        stop()

        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]

        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type

            MainActor.assumeIsolated {
                self?.handle(type)
            }
        }) {
            monitors.append(monitor)
        }
    }

    func stop() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }

        monitors.removeAll()
        reset()
    }

    private func handle(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown:
            reset()
        case .leftMouseDragged, .flagsChanged:
            update()
        case .leftMouseUp:
            finish()
        default:
            break
        }
    }

    private var isModifierHeld: Bool {
        let flags = NSEvent.modifierFlags

        switch state.preferences.modifier {
        case .shift: return flags.contains(.shift)
        case .option: return flags.contains(.option)
        case .control: return flags.contains(.control)
        case .command: return flags.contains(.command)
        }
    }

    private func update() {
        guard NSEvent.pressedMouseButtons & 1 == 1, isModifierHeld else {
            overlay.hide()
            target = nil

            return
        }

        if window == nil {
            findDraggedWindow()
        } else if !isWindowDrag {
            detectWindowDrag()
        }

        if isWindowDrag {
            target = overlay.show(highlightingAt: NSScreen.mouseQuartzLocation)
        }
    }

    /// Looks up the window under the mouse only once the modifier is held
    /// during a drag, so ordinary clicks never wait on another process. A
    /// dragged window moves with the mouse, so it is still under it.
    private func findDraggedWindow() {
        guard Date().timeIntervalSince(lastCheck) > 0.05 else {
            return
        }

        lastCheck = Date()
        window = AXWindow.getWindow(atQuartzPoint: NSScreen.mouseQuartzLocation)
        startFrame = window?.frame
    }

    /// A drag counts as a window drag once the window moved without changing
    /// size; that rules out text selection and resizing from an edge. The
    /// check asks another process, so it runs at most every 50 ms.
    private func detectWindowDrag() {
        guard Date().timeIntervalSince(lastCheck) > 0.05,
              let window,
              let startFrame,
              let current = window.frame
        else {
            return
        }

        lastCheck = Date()

        let moved = abs(current.minX - startFrame.minX) > 2 || abs(current.minY - startFrame.minY) > 2
        let sameSize = abs(current.width - startFrame.width) < 2 && abs(current.height - startFrame.height) < 2
        isWindowDrag = moved && sameSize
    }

    private func finish() {
        let window = self.window
        let target = isWindowDrag && isModifierHeld ? self.target : nil

        overlay.hide()
        reset()

        guard let window, let target else {
            return
        }

        // The window server is still finishing its own move when mouse-up
        // arrives; moving the window right away gets overwritten.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            window.setFrame(target.frame)
        }
    }

    private func reset() {
        window = nil
        startFrame = nil
        isWindowDrag = false
        target = nil
        lastCheck = .distantPast
    }
}
