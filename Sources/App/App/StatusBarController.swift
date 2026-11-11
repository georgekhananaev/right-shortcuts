import AppKit
import RightShortcutsCore

/// The menu bar icon and its menu.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let extensionController: ExtensionController
    private let windows: WindowCoordinator
    private var statusItem: NSStatusItem?

    init(model: AppModel, extensionController: ExtensionController, windows: WindowCoordinator) {
        self.model = model
        self.extensionController = extensionController
        self.windows = windows
    }

    func updateVisibility() {
        if model.showMenuBarIcon {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: AppIdentity.menuSymbol, accessibilityDescription: AppIdentity.displayName)
            item.button?.image?.isTemplate = true
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        extensionController.refresh()
        menu.removeAllItems()

        let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if !extensionController.isEnabled {
            menu.addItem(item("Turn On Finder Extension…", #selector(enableExtension)))
        }
        menu.addItem(item(model.config.isPaused ? "Resume" : "Pause", #selector(togglePause)))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Quit Right Shortcuts", #selector(quit), key: "q"))
    }

    private var statusTitle: String {
        if !extensionController.isEnabled { return "Finder extension is off" }
        return model.config.isPaused ? "Paused" : "Active in Finder"
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func togglePause() {
        model.config.isPaused.toggle()
    }

    @objc private func enableExtension() {
        extensionController.openSystemSettings()
    }

    @objc private func openSettings() {
        windows.showSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
