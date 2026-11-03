import AppKit
import MarmitaCore

/// Where a dragged window will land.
struct ZoneTarget: Equatable {
    let screenKey: String
    let index: Int
    let frame: CGRect
}

/// One transparent, click-through panel per screen that draws the zones while
/// the user drags a window with the modifier held.
@MainActor
final class OverlayController {
    private let state: AppState
    private var panels: [String: OverlayPanel] = [:]

    init(state: AppState) {
        self.state = state
    }

    /// Shows the zones on every screen and highlights the one under the mouse.
    @discardableResult
    func show(highlightingAt point: CGPoint) -> ZoneTarget? {
        var target: ZoneTarget?
        let activeScreen = NSScreen.getScreen(containingQuartzPoint: point)
        var seen = Set<String>()

        for screen in NSScreen.screens {
            let key = screen.displayKey
            let frames = state.getZoneFrames(on: screen)
            var highlighted: Int?

            if screen == activeScreen, let index = ZoneGeometry.findZoneIndex(at: point, in: frames) {
                highlighted = index
                target = ZoneTarget(screenKey: key, index: index, frame: frames[index])
            }

            let panel = panels[key] ?? OverlayPanel()
            panels[key] = panel
            panel.update(screen: screen, zoneFrames: frames, highlighted: highlighted)
            seen.insert(key)
        }

        for (key, panel) in panels where !seen.contains(key) {
            panel.orderOut(nil)
            panels[key] = nil
        }

        return target
    }

    func hide() {
        for panel in panels.values {
            panel.orderOut(nil)
        }
    }
}

private final class OverlayPanel: NSPanel {
    private let zonesView = ZonesView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentView = zonesView
    }

    func update(screen: NSScreen, zoneFrames: [CGRect], highlighted: Int?) {
        if frame != screen.frame {
            setFrame(screen.frame, display: false)
        }

        let origin = screen.quartzFrame.origin
        let local = zoneFrames.map { $0.offsetBy(dx: -origin.x, dy: -origin.y) }

        if zonesView.zoneFrames != local || zonesView.highlighted != highlighted {
            zonesView.zoneFrames = local
            zonesView.highlighted = highlighted
            zonesView.needsDisplay = true
        }

        if !isVisible {
            orderFrontRegardless()
        }
    }
}

/// Flipped so the Quartz-style zone rectangles draw without conversion.
private final class ZonesView: NSView {
    var zoneFrames: [CGRect] = []
    var highlighted: Int?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor

        for (index, frame) in zoneFrames.enumerated() {
            let isHighlighted = index == highlighted
            let path = NSBezierPath(roundedRect: frame.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)

            accent.withAlphaComponent(isHighlighted ? 0.45 : 0.14).setFill()
            path.fill()
            accent.withAlphaComponent(isHighlighted ? 1 : 0.7).setStroke()
            path.lineWidth = isHighlighted ? 4 : 2
            path.stroke()

            drawNumber(index + 1, in: frame, isHighlighted: isHighlighted)
        }
    }

    private func drawNumber(_ number: Int, in frame: CGRect, isHighlighted: Bool) {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
        shadow.shadowBlurRadius = 6

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: isHighlighted ? 72 : 48, weight: .bold),
            .foregroundColor: NSColor.white.withAlphaComponent(isHighlighted ? 1 : 0.8),
            .shadow: shadow,
        ]
        let text = NSAttributedString(string: "\(number)", attributes: attributes)
        let size = text.size()

        text.draw(at: CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
    }
}
