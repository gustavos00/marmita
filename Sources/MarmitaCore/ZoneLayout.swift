import Foundation

/// A rectangle in unit coordinates (0...1) with a top-left origin, so a zone
/// keeps its shape on any screen size.
public struct UnitRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }

    /// Keeps the rectangle inside the unit square and at least `minSize` wide and tall.
    public func makeClamped(minSize: Double = 0.02) -> UnitRect {
        let width = min(max(self.width, minSize), 1)
        let height = min(max(self.height, minSize), 1)

        return UnitRect(
            x: min(max(x, 0), 1 - width),
            y: min(max(y, 0), 1 - height),
            width: width,
            height: height
        )
    }
}

public struct Zone: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var rect: UnitRect

    public init(id: UUID = UUID(), rect: UnitRect) {
        self.id = id
        self.rect = rect
    }
}

public struct ZoneLayout: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var zones: [Zone]

    public init(id: UUID = UUID(), name: String, zones: [Zone]) {
        self.id = id
        self.name = name
        self.zones = zones
    }

    /// Zones in reading order (top to bottom, then left to right). Zone numbers,
    /// the ⌃⌥1…9 shortcuts and next/previous all follow this order.
    public var orderedZones: [Zone] {
        zones.sorted { a, b in
            if abs(a.rect.y - b.rect.y) > 0.0001 {
                return a.rect.y < b.rect.y
            }

            return a.rect.x < b.rect.x
        }
    }
}

public enum LayoutPreset: String, CaseIterable, Sendable {
    case twoColumns
    case threeColumns
    case grid2x2
    case grid3x2
    case focus
    case mainAndStack

    public var displayName: String {
        switch self {
        case .twoColumns: "Duas colunas"
        case .threeColumns: "Três colunas"
        case .grid2x2: "Grelha 2×2"
        case .grid3x2: "Grelha 3×2"
        case .focus: "Foco (2/3 + 1/3)"
        case .mainAndStack: "Principal + pilha"
        }
    }

    public func makeZones() -> [Zone] {
        switch self {
        case .twoColumns:
            return LayoutPreset.makeGrid(rows: 1, columns: 2)
        case .threeColumns:
            return LayoutPreset.makeGrid(rows: 1, columns: 3)
        case .grid2x2:
            return LayoutPreset.makeGrid(rows: 2, columns: 2)
        case .grid3x2:
            return LayoutPreset.makeGrid(rows: 2, columns: 3)
        case .focus:
            return [
                Zone(rect: UnitRect(x: 0, y: 0, width: 2.0 / 3, height: 1)),
                Zone(rect: UnitRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1)),
            ]
        case .mainAndStack:
            return [
                Zone(rect: UnitRect(x: 0, y: 0, width: 0.5, height: 1)),
                Zone(rect: UnitRect(x: 0.5, y: 0, width: 0.5, height: 0.5)),
                Zone(rect: UnitRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)),
            ]
        }
    }

    public func makeLayout() -> ZoneLayout {
        ZoneLayout(name: displayName, zones: makeZones())
    }

    static func makeGrid(rows: Int, columns: Int) -> [Zone] {
        guard rows > 0, columns > 0 else {
            return []
        }

        var zones: [Zone] = []

        for row in 0..<rows {
            for column in 0..<columns {
                zones.append(Zone(rect: UnitRect(
                    x: Double(column) / Double(columns),
                    y: Double(row) / Double(rows),
                    width: 1 / Double(columns),
                    height: 1 / Double(rows)
                )))
            }
        }

        return zones
    }
}
