import AppKit
import SwiftUI

/// Owns the settings and onboarding windows. The Dock icon shows only while one is open.
@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let extensionController: ExtensionController
    private let loginItem: LoginItemController
    private let access: AccessController
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    init(model: AppModel, extensionController: ExtensionController, loginItem: LoginItemController,
         access: AccessController) {
        self.model = model
        self.extensionController = extensionController
        self.loginItem = loginItem
        self.access = access
    }

    /// The window to show when the user opens the app: the welcome flow until it is done, then settings.
    func showMainWindow() {
        if model.hasCompletedOnboarding {
            showSettings()
        } else {
            showOnboarding()
        }
    }

    func showSettings(pane: SettingsPane? = nil) {
        if let pane { model.selectedPane = pane }
        let window = settingsWindow ?? makeSettingsWindow()
        settingsWindow = window
        present(window)
    }

    private func showOnboarding() {
        let window = onboardingWindow ?? makeOnboardingWindow()
        onboardingWindow = window
        present(window)
    }

    private func present(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        // macOS may turn down the activation request while another app is in front.
        // The window still comes forward so it isn't lost behind other windows.
        if !NSApp.isActive { window.orderFrontRegardless() }
    }

    private func finishOnboarding() {
        model.hasCompletedOnboarding = true
        onboardingWindow?.close()
        showSettings(pane: .menu)
    }

    // MARK: - Window construction

    private func makeSettingsWindow() -> NSWindow {
        let window = makeWindow(
            content: SettingsView(),
            size: NSSize(width: 980, height: 660),
            style: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        )
        window.contentMinSize = NSSize(width: 860, height: 580)
        window.title = "Right Shortcuts"
        window.toolbarStyle = .unified
        window.toolbar = NSToolbar(identifier: "settings")
        window.titleVisibility = .hidden
        window.setFrameAutosaveName("RightShortcutsSettings")
        return window
    }

    private func makeOnboardingWindow() -> NSWindow {
        let window = makeWindow(
            content: OnboardingView { [weak self] in self?.finishOnboarding() },
            size: NSSize(width: 620, height: 540),
            style: [.titled, .closable, .fullSizeContentView]
        )
        window.title = "Welcome to Right Shortcuts"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        return window
    }

    private func makeWindow<Content: View>(content: Content, size: NSSize, style: NSWindow.StyleMask) -> NSWindow {
        let root = content
            .environment(model)
            .environment(extensionController)
            .environment(loginItem)
            .environment(access)
        let controller = NSHostingController(rootView: root)
        // The window owns its size. Letting SwiftUI report a minimum size makes lists claim
        // the height of all their rows, which pushes the content out of the window.
        controller.sizingOptions = []

        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style,
                              backing: .buffered, defer: false)
        window.contentViewController = controller
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        let stillOpen = [settingsWindow, onboardingWindow].contains { $0 !== closing && $0?.isVisible == true }
        if !stillOpen {
            model.flushPendingSave()
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
