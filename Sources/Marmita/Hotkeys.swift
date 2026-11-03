import AppKit
import Carbon.HIToolbox

/// System-wide shortcuts through Carbon's RegisterEventHotKey, which needs no
/// permission and swallows the key so the focused app never sees it.
@MainActor
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    private var actions: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var isInstalled = false

    func register(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        installHandlerIfNeeded()

        let id = nextID
        nextID += 1

        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D52_4D54), id: id)
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &reference)

        guard status == noErr, reference != nil else {
            let reason = status == eventHotKeyExistsErr ? "is taken by another app" : "could not be registered"
            NSLog("Marmita: shortcut \(keyCode) \(reason) (status \(status))")

            return
        }

        actions[id] = action
    }

    fileprivate func runAction(id: UInt32) {
        actions[id]?()
    }

    private func installHandlerIfNeeded() {
        guard !isInstalled else {
            return
        }

        isInstalled = true

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            let id = hotKeyID.id

            // Carbon delivers hot keys on the main run loop.
            MainActor.assumeIsolated {
                HotkeyCenter.shared.runAction(id: id)
            }

            return noErr
        }, 1, &eventType, nil, nil)
    }
}

enum Shortcuts {
    static let summary: [(keys: String, action: String)] = [
        ("⌃⌥ ← / →", "Mover a janela ativa para a zona anterior / seguinte"),
        ("⌃⌥ 1 … 9", "Encaixar a janela ativa na zona com esse número"),
        ("⌃⌥⌘ ← / →", "Mover a janela ativa para o ecrã anterior / seguinte"),
        ("Arrastar + tecla", "Arrastar uma janela com a tecla escolhida premida mostra as zonas"),
    ]

    @MainActor
    static func registerAll(actions: WindowActions) {
        let center = HotkeyCenter.shared
        let zoneModifiers = controlKey | optionKey
        let screenModifiers = controlKey | optionKey | cmdKey
        let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]

        center.register(keyCode: kVK_LeftArrow, modifiers: zoneModifiers) { actions.moveFocusedWindow(by: -1) }
        center.register(keyCode: kVK_RightArrow, modifiers: zoneModifiers) { actions.moveFocusedWindow(by: 1) }
        center.register(keyCode: kVK_LeftArrow, modifiers: screenModifiers) { actions.moveFocusedWindowToScreen(by: -1) }
        center.register(keyCode: kVK_RightArrow, modifiers: screenModifiers) { actions.moveFocusedWindowToScreen(by: 1) }

        for (index, keyCode) in digits.enumerated() {
            center.register(keyCode: keyCode, modifiers: zoneModifiers) { actions.snapFocusedWindow(toZoneAt: index) }
        }
    }
}
