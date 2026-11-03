import AppKit
import MarmitaCore

extension NSScreen {
    /// A key that survives reboots and rearranging displays, so each monitor keeps its layout.
    var displayKey: String {
        if let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
           let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue(),
           let string = CFUUIDCreateString(nil, uuid) as String? {
            return string
        }

        return localizedName
    }

    static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    var quartzFrame: CGRect {
        ZoneGeometry.convertCocoaToQuartz(frame, primaryScreenHeight: NSScreen.primaryHeight)
    }

    /// The usable area (without the menu bar and the Dock) in Quartz coordinates.
    var quartzVisibleFrame: CGRect {
        ZoneGeometry.convertCocoaToQuartz(visibleFrame, primaryScreenHeight: NSScreen.primaryHeight)
    }

    static var mouseQuartzLocation: CGPoint {
        ZoneGeometry.convertCocoaToQuartz(NSEvent.mouseLocation, primaryScreenHeight: primaryHeight)
    }

    static func getScreen(containingQuartzPoint point: CGPoint) -> NSScreen? {
        screens.first { $0.quartzFrame.contains(point) }
    }

    /// The screen holding most of a window.
    static func getScreen(bestMatching rect: CGRect) -> NSScreen? {
        screens.max { a, b in
            computeOverlapArea(a.quartzFrame, rect) < computeOverlapArea(b.quartzFrame, rect)
        }
    }

    /// Screens from left to right, then top to bottom, for "next screen".
    static var spatiallyOrdered: [NSScreen] {
        screens.sorted { a, b in
            if a.quartzFrame.minX != b.quartzFrame.minX {
                return a.quartzFrame.minX < b.quartzFrame.minX
            }

            return a.quartzFrame.minY < b.quartzFrame.minY
        }
    }

    private static func computeOverlapArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)

        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}
