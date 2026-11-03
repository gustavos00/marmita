import AppKit
import MarmitaCore
import ServiceManagement

/// The menu bar icon and its menu, rebuilt each time it opens so it always
/// shows the current screens, layouts and permission state.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let state: AppState
    private let openEditor: () -> Void
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    init(state: AppState, openEditor: @escaping () -> Void) {
        self.state = state
        self.openEditor = openEditor
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Marmita")
            button.image?.isTemplate = true
        }

        menu.delegate = self
        statusItem.menu = menu
    }

    func refreshIcon() {
        let symbol = AccessibilityPermission.isGranted ? "square.grid.2x2" : "exclamationmark.triangle"

        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Marmita")
        statusItem.button?.image?.isTemplate = true
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !AccessibilityPermission.isGranted {
            let warning = NSMenuItem(title: "Falta a permissão de Acessibilidade", action: nil, keyEquivalent: "")
            warning.isEnabled = false
            menu.addItem(warning)
            menu.addItem(makeItem("Conceder permissão…", #selector(grantPermission)))
            menu.addItem(.separator())
        }

        let screens = NSScreen.screens

        for screen in screens {
            let title = screens.count > 1 ? "Layout em \(screen.localizedName)" : "Layout"
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = makeLayoutSubmenu(for: screen)
            menu.addItem(item)
        }

        menu.addItem(makeItem("Editar layouts…", #selector(editLayouts), key: "e"))
        menu.addItem(.separator())

        let modifierItem = NSMenuItem(title: "Tecla para mostrar zonas", action: nil, keyEquivalent: "")
        modifierItem.submenu = makeModifierSubmenu()
        menu.addItem(modifierItem)

        let gapItem = NSMenuItem(title: "Espaço entre zonas", action: nil, keyEquivalent: "")
        gapItem.submenu = makeGapSubmenu()
        menu.addItem(gapItem)

        let loginItem = makeItem("Abrir ao iniciar sessão", #selector(toggleLaunchAtLogin))
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(makeItem("Atalhos de teclado…", #selector(showShortcuts)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Sair da Marmita", #selector(quit), key: "q"))
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self

        return item
    }

    private func makeLayoutSubmenu(for screen: NSScreen) -> NSMenu {
        let submenu = NSMenu()
        let activeID = state.getLayout(for: screen)?.id

        for layout in state.preferences.layouts {
            let item = makeItem(layout.name, #selector(chooseLayout(_:)))
            item.state = layout.id == activeID ? .on : .off
            item.representedObject = LayoutChoice(layoutID: layout.id, screen: screen)
            submenu.addItem(item)
        }

        return submenu
    }

    private func makeModifierSubmenu() -> NSMenu {
        let submenu = NSMenu()

        for key in ModifierKey.allCases {
            let item = makeItem(key.displayName, #selector(chooseModifier(_:)))
            item.state = key == state.preferences.modifier ? .on : .off
            item.representedObject = key.rawValue
            submenu.addItem(item)
        }

        return submenu
    }

    private func makeGapSubmenu() -> NSMenu {
        let submenu = NSMenu()

        for gap in [0.0, 4, 8, 12, 16] {
            let item = makeItem(gap == 0 ? "Sem espaço" : "\(Int(gap)) pt", #selector(chooseGap(_:)))
            item.state = gap == state.preferences.gap ? .on : .off
            item.representedObject = gap
            submenu.addItem(item)
        }

        return submenu
    }

    @objc private func grantPermission() {
        AccessibilityPermission.request()
        AccessibilityPermission.openSystemSettings()
    }

    @objc private func editLayouts() {
        openEditor()
    }

    @objc private func chooseLayout(_ sender: NSMenuItem) {
        if let choice = sender.representedObject as? LayoutChoice {
            state.assignLayout(choice.layoutID, to: choice.screen)
        }
    }

    @objc private func chooseModifier(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let key = ModifierKey(rawValue: raw) {
            state.preferences.modifier = key
        }
    }

    @objc private func chooseGap(_ sender: NSMenuItem) {
        if let gap = sender.representedObject as? Double {
            state.preferences.gap = gap
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showAlert(title: "Não foi possível alterar o arranque automático", text: error.localizedDescription)
        }
    }

    @objc private func showShortcuts() {
        let text = Shortcuts.summary.map { "\($0.keys)\t\($0.action)" }.joined(separator: "\n")

        showAlert(title: "Atalhos da Marmita", text: text)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showAlert(title: String, text: String) {
        NSApp.activate()

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}

private final class LayoutChoice: NSObject {
    let layoutID: UUID
    let screen: NSScreen

    init(layoutID: UUID, screen: NSScreen) {
        self.layoutID = layoutID
        self.screen = screen
    }
}
