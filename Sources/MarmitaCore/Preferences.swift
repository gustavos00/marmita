import Foundation

/// The key that, held while dragging a window, shows the zones.
public enum ModifierKey: String, Codable, CaseIterable, Sendable {
    case shift
    case option
    case control
    case command

    public var displayName: String {
        switch self {
        case .shift: "Shift ⇧"
        case .option: "Option ⌥"
        case .control: "Control ⌃"
        case .command: "Command ⌘"
        }
    }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var layouts: [ZoneLayout]
    public var screenLayouts: [String: UUID]
    public var modifier: ModifierKey
    public var gap: Double

    public init(layouts: [ZoneLayout], screenLayouts: [String: UUID] = [:], modifier: ModifierKey = .shift, gap: Double = 8) {
        self.layouts = layouts
        self.screenLayouts = screenLayouts
        self.modifier = modifier
        self.gap = gap
    }

    public static var defaults: Preferences {
        Preferences(layouts: LayoutPreset.allCases.map { $0.makeLayout() })
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Preferences.defaults

        let decodedLayouts = try container.decodeIfPresent([ZoneLayout].self, forKey: .layouts) ?? fallback.layouts

        // A hand-edited file can hold anything; out-of-range values would
        // otherwise go straight into window frames.
        layouts = decodedLayouts.map { layout in
            var layout = layout
            layout.zones = layout.zones.map { Zone(id: $0.id, rect: $0.rect.makeClamped()) }

            return layout
        }
        screenLayouts = try container.decodeIfPresent([String: UUID].self, forKey: .screenLayouts) ?? [:]
        modifier = (try container.decodeIfPresent(String.self, forKey: .modifier)).flatMap(ModifierKey.init(rawValue:)) ?? fallback.modifier
        gap = min(max(try container.decodeIfPresent(Double.self, forKey: .gap) ?? fallback.gap, 0), 64)
    }

    /// The layout assigned to a screen, falling back to the first layout.
    public func getLayout(forScreen key: String) -> ZoneLayout? {
        if let id = screenLayouts[key], let layout = layouts.first(where: { $0.id == id }) {
            return layout
        }

        return layouts.first
    }

    /// Moves the layouts at `source` so they land before the layout that was
    /// at `destination`, the convention of a list's drag to reorder.
    public mutating func reorderLayouts(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().compactMap { layouts.indices.contains($0) ? layouts[$0] : nil }
        var remaining = layouts.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertion = destination - source.filter { $0 < destination }.count

        remaining.insert(contentsOf: moving, at: min(max(insertion, 0), remaining.count))
        layouts = remaining
    }

    /// Moves one layout up (negative `step`) or down the list, stopping at the ends.
    public mutating func shiftLayout(id: UUID, by step: Int) {
        guard let index = layouts.firstIndex(where: { $0.id == id }) else {
            return
        }

        let target = min(max(index + step, 0), layouts.count - 1)

        guard target != index else {
            return
        }

        layouts.swapAt(index, target)
    }

    public mutating func removeLayout(id: UUID) {
        layouts.removeAll { $0.id == id }
        screenLayouts = screenLayouts.filter { $0.value != id }
    }
}

/// Reads and writes the preferences as JSON in Application Support.
public struct PreferencesStore: Sendable {
    let url: URL

    public init(url: URL = PreferencesStore.makeDefaultURL()) {
        self.url = url
    }

    public static func makeDefaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")

        return base.appendingPathComponent("Marmita/preferences.json")
    }

    /// The saved preferences, or the defaults when there is no file. A file
    /// that cannot be decoded is moved aside first, to a timestamped `.bak`
    /// next to it, so the next save does not overwrite the user's layouts with
    /// the defaults and an earlier backup is never replaced.
    public func load() -> Preferences {
        guard let data = try? Data(contentsOf: url) else {
            return .defaults
        }

        if let preferences = try? JSONDecoder().decode(Preferences.self, from: data), !preferences.layouts.isEmpty {
            return preferences
        }

        let stamp = Int(Date().timeIntervalSince1970)
        let backup = url.deletingPathExtension().appendingPathExtension("\(stamp).json.bak")

        do {
            try FileManager.default.moveItem(at: url, to: backup)
            NSLog("Marmita: preferences could not be read; kept them in \(backup.path) and started from the defaults")
        } catch {
            NSLog("Marmita: preferences could not be read or moved aside: \(error)")
        }

        return .defaults
    }

    public func save(_ preferences: Preferences) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(preferences).write(to: url, options: .atomic)
    }
}
