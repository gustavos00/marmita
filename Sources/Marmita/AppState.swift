import AppKit
import Combine
import MarmitaCore

/// The preferences everything reads, saved shortly after each change so a drag
/// in the editor does not write the file on every frame.
@MainActor
final class AppState: ObservableObject {
    @Published var preferences: Preferences {
        didSet {
            scheduleSave()
        }
    }

    private let store: PreferencesStore
    private var saveWorkItem: DispatchWorkItem?

    init(store: PreferencesStore = PreferencesStore()) {
        self.store = store
        preferences = store.load()
    }

    func getLayout(for screen: NSScreen) -> ZoneLayout? {
        preferences.getLayout(forScreen: screen.displayKey)
    }

    func assignLayout(_ id: UUID, to screen: NSScreen) {
        preferences.screenLayouts[screen.displayKey] = id
    }

    /// The screen rectangles of the zones on a screen, in reading order.
    func getZoneFrames(on screen: NSScreen) -> [CGRect] {
        ZoneGeometry.makeZoneFrames(for: getLayout(for: screen), in: screen.quartzVisibleFrame, gap: preferences.gap)
    }

    /// Writes a pending change at once; with nothing pending it leaves the file alone.
    func saveNow() {
        guard let item = saveWorkItem else {
            return
        }

        item.cancel()
        saveWorkItem = nil
        writePreferences()
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()

        let item = DispatchWorkItem { [weak self] in
            self?.saveWorkItem = nil
            self?.writePreferences()
        }

        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    private func writePreferences() {
        do {
            try store.save(preferences)
        } catch {
            NSLog("Marmita: could not save preferences: \(error)")
        }
    }
}
