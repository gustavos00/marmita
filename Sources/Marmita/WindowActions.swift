import AppKit
import MarmitaCore

/// What the keyboard shortcuts do to the focused window.
@MainActor
final class WindowActions {
    private let state: AppState

    init(state: AppState) {
        self.state = state
    }

    /// ⌃⌥1…9: the zone with that number on the window's screen.
    func snapFocusedWindow(toZoneAt index: Int) {
        performOnFocusedWindow { window, frame in
            guard let screen = NSScreen.getScreen(bestMatching: frame) else {
                return false
            }

            let frames = state.getZoneFrames(on: screen)

            guard frames.indices.contains(index) else {
                return false
            }

            window.setFrame(frames[index])

            return true
        }
    }

    /// ⌃⌥← / ⌃⌥→: the previous or next zone, wrapping around.
    func moveFocusedWindow(by step: Int) {
        performOnFocusedWindow { window, frame in
            guard let screen = NSScreen.getScreen(bestMatching: frame) else {
                return false
            }

            let frames = state.getZoneFrames(on: screen)
            let current = ZoneGeometry.findBestMatchIndex(for: frame, in: frames)

            guard let next = ZoneGeometry.stepIndex(from: current, count: frames.count, step: step) else {
                return false
            }

            window.setFrame(frames[next])

            return true
        }
    }

    /// ⌃⌥⌘← / ⌃⌥⌘→: the same zone number on the neighbouring screen.
    func moveFocusedWindowToScreen(by step: Int) {
        performOnFocusedWindow { window, frame in
            let screens = NSScreen.spatiallyOrdered

            guard screens.count > 1,
                  let screen = NSScreen.getScreen(bestMatching: frame),
                  let position = screens.firstIndex(of: screen),
                  let nextPosition = ZoneGeometry.stepIndex(from: position, count: screens.count, step: step)
            else {
                return false
            }

            let current = ZoneGeometry.findBestMatchIndex(for: frame, in: state.getZoneFrames(on: screen)) ?? 0
            let targetFrames = state.getZoneFrames(on: screens[nextPosition])

            guard !targetFrames.isEmpty else {
                return false
            }

            window.setFrame(targetFrames[min(current, targetFrames.count - 1)])

            return true
        }
    }

    /// Runs `body` on the focused window and beeps when nothing could be done.
    private func performOnFocusedWindow(_ body: (AXWindow, CGRect) -> Bool) {
        // The menu offers the permission; prompting from a shortcut would
        // bring the system dialog back on every key press.
        guard AccessibilityPermission.isGranted else {
            NSSound.beep()

            return
        }

        guard let window = AXWindow.getFocused(), let frame = window.frame, body(window, frame) else {
            NSSound.beep()

            return
        }
    }
}
