import AppKit
import RightShortcutsCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private let extensionController = ExtensionController()
    private let loginItem = LoginItemController()
    private let access = AccessController()
    private lazy var runner = ActionRunner(model: model, access: access)
    private lazy var windows = WindowCoordinator(model: model, extensionController: extensionController,
                                                 loginItem: loginItem, access: access)
    private lazy var statusBar = StatusBarController(model: model, extensionController: extensionController, windows: windows)

    func applicationDidFinishLaunching(_ notification: Notification) {
        Diagnostics.start()
        if let notice = model.startupNotice {
            Log.app.error("\(notice, privacy: .public)")
            ToastCenter.shared.show(notice, symbol: "exclamationmark.triangle.fill", style: .failure)
        }
        model.onMenuBarIconChange = { [weak self] in self?.statusBar.updateVisibility() }
        statusBar.updateVisibility()

        // A menu click launches the app with a URL event; only a launch by the user shows a window.
        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        let launchedAtLogin = LoginItemController.isLoginLaunch(appleEvent: launchEvent)
        let openedByUser = launchEvent?.eventID == AEEventID(kAEOpenApplication) && !launchedAtLogin
        Log.app.info("Launched (event \(launchEvent.map { Self.fourCharacterCode($0.eventID) } ?? "none", privacy: .public), login item: \(launchedAtLogin))")

        if openedByUser { windows.showMainWindow() }
        runner.drainInbox()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == AppIdentity.urlScheme }) else { return }
        runner.drainInbox()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows.showMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard ProgressCenter.shared.isBusy else { return .terminateNow }
        // A copy in progress is stopped and its unfinished item removed before the app goes away.
        Task {
            await ProgressCenter.shared.stopAll()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.flushPendingSave()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        extensionController.refresh()
        loginItem.refresh()
        access.refresh()
    }

    private static func fourCharacterCode(_ code: FourCharCode) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }, encoding: .macOSRoman) ?? "\(code)"
    }
}
