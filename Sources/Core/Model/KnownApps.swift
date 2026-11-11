import Foundation

/// Well-known apps people like to open files and folders with.
public enum KnownApps {
    public enum Category: Sendable {
        case terminal
        case editor
    }

    public struct App: Sendable {
        public let bundleID: String
        public let category: Category
    }

    /// In order of preference within each category.
    public static let all: [App] = [
        App(bundleID: "com.apple.Terminal", category: .terminal),
        App(bundleID: "com.googlecode.iterm2", category: .terminal),
        App(bundleID: "dev.warp.Warp-Stable", category: .terminal),
        App(bundleID: "com.mitchellh.ghostty", category: .terminal),
        App(bundleID: "net.kovidgoyal.kitty", category: .terminal),
        App(bundleID: "com.github.wez.wezterm", category: .terminal),
        App(bundleID: "org.alacritty", category: .terminal),
        App(bundleID: "com.microsoft.VSCode", category: .editor),
        App(bundleID: "com.todesktop.230313mzl4w4u92", category: .editor), // Cursor
        App(bundleID: "dev.zed.Zed", category: .editor),
        App(bundleID: "com.exafunction.windsurf", category: .editor),
        App(bundleID: "com.sublimetext.4", category: .editor),
        App(bundleID: "com.panic.Nova", category: .editor),
        App(bundleID: "com.barebones.bbedit", category: .editor),
        App(bundleID: "com.apple.dt.Xcode", category: .editor),
        App(bundleID: "com.jetbrains.WebStorm", category: .editor),
        App(bundleID: "com.jetbrains.intellij", category: .editor),
        App(bundleID: "com.jetbrains.pycharm", category: .editor),
        App(bundleID: "com.jetbrains.goland", category: .editor),
        App(bundleID: "com.jetbrains.CLion", category: .editor),
        App(bundleID: "com.jetbrains.rustrover", category: .editor),
        App(bundleID: "com.google.android.studio", category: .editor),
        App(bundleID: "com.apple.TextEdit", category: .editor),
    ]

    public static func isTerminal(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return all.contains { $0.bundleID == bundleID && $0.category == .terminal }
    }
}

extension OpenWithApp {
    /// Whether the app is handed the folder rather than the selected items.
    /// Left on automatic, terminals get the folder and everything else gets the items.
    public var opensFolder: Bool {
        switch target {
        case .automatic: KnownApps.isTerminal(bundleID: bundleID)
        case .items: false
        case .folder: true
        }
    }
}
