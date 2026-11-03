import AppKit
import ApplicationServices

enum AccessibilityPermission {
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt that sends the user to Privacy & Security › Accessibility.
    static func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Caps every Accessibility call at 250 ms. The default is about six
    /// seconds, and one call to a hung app would freeze the overlay, the
    /// shortcuts and the menu for that long.
    static func limitMessagingTimeout() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Another app's window, reached through the Accessibility API. Positions are
/// global Quartz coordinates (top-left origin).
struct AXWindow {
    let element: AXUIElement
    let pid: pid_t

    static func getFocused() -> AXWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        guard let window = copyElement(appElement, kAXFocusedWindowAttribute) else {
            return nil
        }

        return AXWindow(element: window, pid: app.processIdentifier)
    }

    /// The window under a point, walking up from whatever element was hit
    /// (a title bar, a toolbar, a tab strip) to the window that owns it.
    static func getWindow(atQuartzPoint point: CGPoint) -> AXWindow? {
        var hit: AXUIElement?

        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
              let hit
        else {
            return nil
        }

        var pid: pid_t = 0
        AXUIElementGetPid(hit, &pid)

        if pid == ProcessInfo.processInfo.processIdentifier {
            return nil
        }

        if getRole(of: hit) == kAXWindowRole {
            return AXWindow(element: hit, pid: pid)
        }

        if let window = copyElement(hit, kAXWindowAttribute) {
            return AXWindow(element: window, pid: pid)
        }

        var current = hit

        for _ in 0..<12 {
            guard let parent = copyElement(current, kAXParentAttribute) else {
                break
            }

            if getRole(of: parent) == kAXWindowRole {
                return AXWindow(element: parent, pid: pid)
            }

            current = parent
        }

        return nil
    }

    var frame: CGRect? {
        guard let positionValue = AXWindow.copyAXValue(element, kAXPositionAttribute),
              let sizeValue = AXWindow.copyAXValue(element, kAXSizeAttribute)
        else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue, .cgPoint, &position)
        AXValueGetValue(sizeValue, .cgSize, &size)

        return CGRect(origin: position, size: size)
    }

    /// Moves and resizes the window. Size is set before and after the move so a
    /// window crossing to a smaller screen is not clamped by its old position.
    /// Apps with "enhanced user interface" on (turned on by VoiceOver-style
    /// clients) animate every change and drop some of them, so it is switched
    /// off for the duration.
    func setFrame(_ frame: CGRect) {
        let app = AXUIElementCreateApplication(pid)

        // Resizing a busy app can take longer than the global 250 ms cap.
        AXUIElementSetMessagingTimeout(element, 1)
        AXUIElementSetMessagingTimeout(app, 1)
        let enhancedAttribute = "AXEnhancedUserInterface" as CFString
        var enhancedValue: CFTypeRef?
        let wasEnhanced = AXUIElementCopyAttributeValue(app, enhancedAttribute, &enhancedValue) == .success
            && (enhancedValue as? Bool) == true

        if wasEnhanced {
            AXUIElementSetAttributeValue(app, enhancedAttribute, kCFBooleanFalse)
        }

        setSize(frame.size)
        setPosition(frame.origin)
        setSize(frame.size)

        if wasEnhanced {
            AXUIElementSetAttributeValue(app, enhancedAttribute, kCFBooleanTrue)
        }
    }

    private func setSize(_ size: CGSize) {
        var size = size

        if let value = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
        }
    }

    private func setPosition(_ position: CGPoint) {
        var position = position

        if let value = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
        }
    }

    private static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?

        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        return value
    }

    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copyAttribute(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private static func copyAXValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        guard let value = copyAttribute(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        return (value as! AXValue)
    }

    private static func getRole(of element: AXUIElement) -> String? {
        copyAttribute(element, kAXRoleAttribute) as? String
    }
}
