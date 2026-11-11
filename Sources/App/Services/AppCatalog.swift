import AppKit
import RightShortcutsCore

/// Finds the well-known apps that are installed on this Mac.
enum AppCatalog {
    /// Known apps that are installed, in catalog order.
    static func installed() -> [OpenWithApp] {
        KnownApps.all.compactMap { app in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID).map {
                makeApp(at: $0, knownBundleID: app.bundleID)
            }
        }
    }

    /// Terminal plus the first installed code editor, for a fresh install.
    static func defaultApps() -> [OpenWithApp] {
        let installed = installed()
        let terminal = installed.first { KnownApps.isTerminal(bundleID: $0.bundleID) }
        let editor = installed.first { !KnownApps.isTerminal(bundleID: $0.bundleID) && $0.bundleID != "com.apple.TextEdit" }
        return [terminal, editor].compactMap { $0 }
    }

    /// - Parameter knownBundleID: Used when the app's own files can't be read, which happens
    ///   in the sandbox for apps outside the usual places.
    static func makeApp(at url: URL, knownBundleID: String? = nil) -> OpenWithApp {
        let bundle = Bundle(url: url)
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return OpenWithApp(appPath: url.path, appName: name, bundleID: bundle?.bundleIdentifier ?? knownBundleID)
    }
}
