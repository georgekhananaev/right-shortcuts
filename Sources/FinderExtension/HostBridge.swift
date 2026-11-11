import AppKit
import RightShortcutsCore

/// Hands a click over to the Right Shortcuts app, launching it if needed.
/// The sandboxed extension can't touch the user's files itself; the app does the work.
enum HostBridge {
    static func send(_ request: ActionRequest, activateApp: Bool) {
        do {
            let doorbell = try ActionInbox.post(request)
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = activateApp
            configuration.addsToRecentItems = false
            NSWorkspace.shared.open([doorbell], withApplicationAt: hostAppURL, configuration: configuration) { _, error in
                if let error { Log.finder.error("Couldn't reach the app: \(error.localizedDescription, privacy: .public)") }
            }
        } catch {
            Log.finder.error("Couldn't queue the action: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The app that contains this extension: Right Shortcuts.app/Contents/PlugIns/<extension>.appex
    private static var hostAppURL: URL {
        Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
