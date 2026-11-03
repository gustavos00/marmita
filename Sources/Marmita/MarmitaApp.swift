import AppKit

@main
enum MarmitaMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()

        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private lazy var overlay = OverlayController(state: state)
    private lazy var actions = WindowActions(state: state)
    private lazy var dragSnapper = DragSnapper(state: state, overlay: overlay)
    private var statusMenu: StatusMenuController?
    private var editor: EditorWindowController?
    private var permissionTimer: Timer?
    private var wasTrusted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusMenu = StatusMenuController(state: state) { [weak self] in
            self?.openEditor()
        }

        AccessibilityPermission.limitMessagingTimeout()
        Shortcuts.registerAll(actions: actions)

        wasTrusted = AccessibilityPermission.isGranted

        if !wasTrusted {
            AccessibilityPermission.request()
        }

        dragSnapper.start()
        statusMenu?.refreshIcon()

        // There is no notification for the Accessibility grant, so poll for it
        // and reinstall the monitors the moment it arrives.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkPermission()
            }
        }

        if CommandLine.arguments.contains("--open-editor") {
            openEditor()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.saveNow()
    }

    private func checkPermission() {
        let isTrusted = AccessibilityPermission.isGranted

        guard isTrusted != wasTrusted else {
            return
        }

        wasTrusted = isTrusted
        statusMenu?.refreshIcon()

        if isTrusted {
            dragSnapper.start()
        }
    }

    private func openEditor() {
        if editor == nil {
            editor = EditorWindowController(state: state)
        }

        editor?.present()
    }
}
