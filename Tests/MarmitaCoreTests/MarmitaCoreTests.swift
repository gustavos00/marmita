import CoreGraphics
import Foundation
import Testing
@testable import MarmitaCore

@Suite struct ZoneGeometryTests {
    @Test func framesSplitTheAreaWithGaps() {
        let layout = LayoutPreset.twoColumns.makeLayout()
        let frames = ZoneGeometry.makeZoneFrames(for: layout, in: CGRect(x: 0, y: 25, width: 1000, height: 600), gap: 10)

        #expect(frames == [
            CGRect(x: 10, y: 35, width: 485, height: 580),
            CGRect(x: 505, y: 35, width: 485, height: 580),
        ])
    }

    @Test func framesWithoutGapCoverTheArea() {
        let frames = ZoneGeometry.makeZoneFrames(for: LayoutPreset.grid2x2.makeLayout(), in: CGRect(x: 0, y: 0, width: 800, height: 600), gap: 0)

        #expect(frames.last == CGRect(x: 400, y: 300, width: 400, height: 300))
    }

    @Test func orderedZonesFollowReadingOrder() {
        let layout = ZoneLayout(name: "t", zones: [
            Zone(rect: UnitRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)),
            Zone(rect: UnitRect(x: 0.5, y: 0, width: 0.5, height: 0.5)),
            Zone(rect: UnitRect(x: 0, y: 0, width: 0.5, height: 1)),
        ])

        #expect(layout.orderedZones.map(\.rect.x) == [0, 0.5, 0.5])
        #expect(layout.orderedZones.map(\.rect.y) == [0, 0, 0.5])
    }

    @Test func pointInGapSnapsToNearestZone() {
        let frames = [CGRect(x: 0, y: 0, width: 100, height: 100), CGRect(x: 110, y: 0, width: 100, height: 100)]

        #expect(ZoneGeometry.findZoneIndex(at: CGPoint(x: 50, y: 50), in: frames) == 0)
        #expect(ZoneGeometry.findZoneIndex(at: CGPoint(x: 108, y: 50), in: frames) == 1)
    }

    @Test func overlappingZonesPreferTheSmallest() {
        let frames = [CGRect(x: 0, y: 0, width: 200, height: 200), CGRect(x: 50, y: 50, width: 50, height: 50)]

        #expect(ZoneGeometry.findZoneIndex(at: CGPoint(x: 60, y: 60), in: frames) == 1)
    }

    @Test func bestMatchFindsTheWindowsZone() {
        let frames = [CGRect(x: 0, y: 0, width: 100, height: 100), CGRect(x: 100, y: 0, width: 100, height: 100)]

        #expect(ZoneGeometry.findBestMatchIndex(for: CGRect(x: 102, y: 3, width: 95, height: 90), in: frames) == 1)
        #expect(ZoneGeometry.findBestMatchIndex(for: CGRect(x: 500, y: 500, width: 10, height: 10), in: frames) == nil)
    }

    @Test func stepIndexWraps() {
        #expect(ZoneGeometry.stepIndex(from: nil, count: 3, step: 1) == 0)
        #expect(ZoneGeometry.stepIndex(from: nil, count: 3, step: -1) == 2)
        #expect(ZoneGeometry.stepIndex(from: 2, count: 3, step: 1) == 0)
        #expect(ZoneGeometry.stepIndex(from: 0, count: 3, step: -1) == 2)
        #expect(ZoneGeometry.stepIndex(from: 0, count: 0, step: 1) == nil)
    }

    @Test func cocoaToQuartzFlipsY() {
        let rect = ZoneGeometry.convertCocoaToQuartz(CGRect(x: 0, y: 0, width: 1440, height: 875), primaryScreenHeight: 900)

        #expect(rect == CGRect(x: 0, y: 25, width: 1440, height: 875))
    }
}

@Suite struct PreferencesTests {
    @Test func roundTripsThroughTheStore() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("marmita-\(UUID().uuidString)/preferences.json")
        let store = PreferencesStore(url: url)
        var preferences = Preferences.defaults
        preferences.gap = 4
        preferences.modifier = .option
        preferences.screenLayouts["screen-a"] = preferences.layouts[2].id

        try store.save(preferences)

        #expect(store.load() == preferences)
        #expect(store.load().getLayout(forScreen: "screen-a")?.id == preferences.layouts[2].id)
    }

    @Test func missingFileGivesDefaults() {
        let store = PreferencesStore(url: URL(fileURLWithPath: "/nonexistent/marmita.json"))

        #expect(store.load().layouts.count == LayoutPreset.allCases.count)
    }

    @Test func removingALayoutDropsItsScreenAssignments() {
        var preferences = Preferences.defaults
        let id = preferences.layouts[1].id
        preferences.screenLayouts["a"] = id

        preferences.removeLayout(id: id)

        #expect(preferences.screenLayouts.isEmpty)
        #expect(preferences.getLayout(forScreen: "a")?.id == preferences.layouts.first?.id)
    }

    @Test func unreadableFileIsKeptAsBackup() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("marmita-\(UUID().uuidString)")
        let url = folder.appendingPathComponent("preferences.json")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: url)

        let preferences = PreferencesStore(url: url).load()

        #expect(preferences.layouts.map(\.name) == Preferences.defaults.layouts.map(\.name))
        let backups = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)

        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(backups.count == 1)
        #expect(backups.first?.lastPathComponent.hasSuffix(".json.bak") == true)
        #expect(try backups.first.map { try String(contentsOf: $0, encoding: .utf8) } == "{ not json")
    }

    @Test func decodingRepairsOutOfRangeValues() throws {
        let json = """
        {"gap": -5, "modifier": "hyper", "layouts": [{"id": "\(UUID().uuidString)", "name": "x",
          "zones": [{"id": "\(UUID().uuidString)", "rect": {"x": 0.8, "y": 0, "width": 0.5, "height": 2}}]}]}
        """

        let preferences = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))

        #expect(preferences.gap == 0)
        #expect(preferences.modifier == .shift)
        #expect(preferences.layouts[0].zones[0].rect == UnitRect(x: 0.5, y: 0, width: 0.5, height: 1))
    }

    @Test func makeClampedKeepsRectInside() {
        let rect = UnitRect(x: 0.9, y: -0.2, width: 0.5, height: 0.3).makeClamped()

        #expect(rect == UnitRect(x: 0.5, y: 0, width: 0.5, height: 0.3))
    }
}
