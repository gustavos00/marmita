import CoreGraphics
import Foundation

/// Pure geometry shared by the overlay, the drag snapper and the shortcuts.
/// Every rectangle here is in global Quartz coordinates (top-left origin of the
/// primary screen, y grows downwards), which is what the Accessibility API uses.
public enum ZoneGeometry {
    /// Turns a unit rectangle into a screen rectangle inside `area`, leaving
    /// `gap` points between neighbouring zones and between zones and the edges.
    static func computeFrame(for rect: UnitRect, in area: CGRect, gap: Double) -> CGRect {
        let inner = area.insetBy(dx: gap / 2, dy: gap / 2)
        let raw = CGRect(
            x: inner.minX + rect.x * inner.width,
            y: inner.minY + rect.y * inner.height,
            width: rect.width * inner.width,
            height: rect.height * inner.height
        ).insetBy(dx: gap / 2, dy: gap / 2)

        return CGRect(
            x: raw.minX.rounded(),
            y: raw.minY.rounded(),
            width: raw.width.rounded(),
            height: raw.height.rounded()
        )
    }

    /// Screen rectangles of a layout's zones, in the layout's reading order.
    public static func makeZoneFrames(for layout: ZoneLayout?, in area: CGRect, gap: Double) -> [CGRect] {
        guard let layout else {
            return []
        }

        return layout.orderedZones.map { computeFrame(for: $0.rect, in: area, gap: gap) }
    }

    /// The zone under `point`: the smallest one that contains it when zones
    /// overlap, otherwise the nearest one, so the gaps between zones still snap.
    public static func findZoneIndex(at point: CGPoint, in frames: [CGRect]) -> Int? {
        let containing = frames.indices.filter { frames[$0].contains(point) }

        if let smallest = containing.min(by: { computeArea(of: frames[$0]) < computeArea(of: frames[$1]) }) {
            return smallest
        }

        return frames.indices.min { measureDistance(from: point, to: frames[$0]) < measureDistance(from: point, to: frames[$1]) }
    }

    /// The zone a window currently sits in: the one with the highest overlap
    /// (intersection over union), or nil when the window overlaps none.
    public static func findBestMatchIndex(for window: CGRect, in frames: [CGRect]) -> Int? {
        var best: (index: Int, score: Double)?

        for (index, frame) in frames.enumerated() {
            let score = computeOverlapScore(window, frame)

            if score > 0, score > (best?.score ?? 0) {
                best = (index, score)
            }
        }

        return best?.index
    }

    /// Steps through `count` zones with wrap-around. With no current zone the
    /// first step forwards lands on the first zone and backwards on the last.
    public static func stepIndex(from current: Int?, count: Int, step: Int) -> Int? {
        guard count > 0 else {
            return nil
        }

        guard let current else {
            return step >= 0 ? 0 : count - 1
        }

        return ((current + step) % count + count) % count
    }

    /// Converts a Cocoa rectangle (bottom-left origin) to Quartz coordinates.
    public static func convertCocoaToQuartz(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func convertCocoaToQuartz(_ point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    private static func computeArea(of rect: CGRect) -> Double {
        rect.width * rect.height
    }

    private static func measureDistance(from point: CGPoint, to rect: CGRect) -> Double {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)

        return (dx * dx + dy * dy).squareRoot()
    }

    private static func computeOverlapScore(_ a: CGRect, _ b: CGRect) -> Double {
        let intersection = a.intersection(b)

        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else {
            return 0
        }

        let shared = computeArea(of: intersection)

        return shared / (computeArea(of: a) + computeArea(of: b) - shared)
    }
}
