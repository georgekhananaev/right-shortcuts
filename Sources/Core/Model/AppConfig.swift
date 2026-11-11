import Foundation

/// Where Finder shows the menu.
public enum Coverage: String, Codable, Sendable {
    case everywhere
    case selectedFolders
}

/// How the items are placed in Finder's right-click menu.
public enum MenuLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    /// All items inside one "Right Shortcuts" submenu.
    case submenu
    /// Items directly in Finder's menu.
    case inline

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .submenu: "Grouped in a submenu"
        case .inline: "Directly in the menu"
        }
    }
}

/// Everything the app and the extension share. Stored as JSON in the App Group container.
public struct AppConfig: Codable, Equatable, Sendable {
    /// Raised whenever the file format changes in a way older versions can't read.
    public static let currentSchemaVersion = 1

    public var schemaVersion = AppConfig.currentSchemaVersion
    public var isPaused = false
    public var coverage: Coverage = .everywhere
    public var watchedFolders: [String] = []
    public var excludedFolders: [String] = []
    public var menuLayout: MenuLayout = .submenu
    public var showIcons = true
    public var items: [MenuItem] = []
    public var templates: [FileTemplate] = FileTemplate.builtins
    public var quickFolders: [QuickFolder] = []
    public var askForFileName = true
    public var openCreatedFile = false
    public var showConfirmations = true

    public init() {}

    /// A fresh configuration with sensible defaults.
    /// - Parameters:
    ///   - homeDirectory: Used for the default quick folders.
    ///   - apps: Apps to offer as "Open in …" items, most important first.
    public static func makeDefault(homeDirectory: String, apps: [OpenWithApp]) -> AppConfig {
        var config = AppConfig()
        let appItems = apps.map { MenuItem(kind: .openWith(app: $0)) }
        config.items = [MenuItem.builtin(.newFile), .separator()]
            + appItems
            + (appItems.isEmpty ? [] : [.separator()])
            + [.builtin(.copyPath), .builtin(.copyName), .builtin(.copyPathAs), .builtin(.copyContents), .separator()]
            + [.builtin(.copyTo), .builtin(.moveTo), .builtin(.goTo), .separator()]
            + [.builtin(.makeExecutable), .builtin(.hide), .builtin(.unhide), .builtin(.airDrop), .builtin(.deletePermanently)]
            + [.separator()]
            + exampleCommands
        config.quickFolders = ["Desktop", "Documents", "Downloads"].map {
            QuickFolder(path: (homeDirectory as NSString).appendingPathComponent($0))
        }
        return config
    }

    /// Commands that show what custom scripts can do. Off until the user turns them on.
    public static let exampleCommands: [MenuItem] = [
        MenuItem(
            kind: .command(command: CustomCommand(
                name: "Copy SHA-256 Checksum",
                script: #"shasum -a 256 "$@" | awk '{print $1}' | pbcopy"#
            )),
            customSymbol: "number.square",
            isEnabled: false,
            contexts: [.files, .toolbar]
        ),
        MenuItem(
            kind: .command(command: CustomCommand(
                name: "Convert to PNG",
                script: #"for f in "$@"; do sips -s format png "$f" --out "${f%.*}.png"; done"#
            )),
            customSymbol: "photo",
            isEnabled: false,
            contexts: [.files, .toolbar],
            fileExtensions: ["jpg", "jpeg", "heic", "tiff", "webp", "gif", "bmp"]
        ),
    ]

    /// Adds built-in actions and templates that a newer version introduced, so upgrades
    /// never hide new features. New entries are appended switched off.
    public func reconciled() -> AppConfig {
        var copy = self
        let presentActions = Set(items.compactMap(\.builtinAction))
        for action in BuiltinAction.allCases where !presentActions.contains(action) {
            var item = MenuItem.builtin(action)
            item.isEnabled = false
            copy.items.append(item)
        }
        let presentTemplates = Set(templates.map(\.id))
        for template in FileTemplate.builtins where !presentTemplates.contains(template.id) {
            var disabled = template
            disabled.isEnabled = false
            copy.templates.append(disabled)
        }
        return copy
    }

    /// True when a newer version of the app wrote this file. Saving it from this version
    /// would drop settings this version doesn't know about.
    public var isFromNewerVersion: Bool {
        schemaVersion > AppConfig.currentSchemaVersion
    }

    /// Whether the path sits inside one of the excluded folders.
    public func isExcluded(_ path: String) -> Bool {
        excludedFolders.contains { PathMatching.isPath(path, inside: $0) }
    }
}

// Decoding tolerates missing keys and unknown items, so older or newer files still load.
extension AppConfig {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, isPaused, coverage, watchedFolders, excludedFolders, menuLayout, showIcons
        case items, templates, quickFolders, askForFileName, openCreatedFile, showConfirmations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppConfig()
        // Files written before versions existed are version 1.
        schemaVersion = (try? container.decodeIfPresent(Int.self, forKey: .schemaVersion)) ?? 1
        isPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused) ?? defaults.isPaused
        coverage = (try? container.decodeIfPresent(Coverage.self, forKey: .coverage)) ?? defaults.coverage
        watchedFolders = try container.decodeIfPresent([String].self, forKey: .watchedFolders) ?? []
        excludedFolders = try container.decodeIfPresent([String].self, forKey: .excludedFolders) ?? []
        menuLayout = (try? container.decodeIfPresent(MenuLayout.self, forKey: .menuLayout)) ?? defaults.menuLayout
        showIcons = try container.decodeIfPresent(Bool.self, forKey: .showIcons) ?? defaults.showIcons
        items = try container.decodeLossyArray(MenuItem.self, forKey: .items)
        templates = try container.decodeLossyArray(FileTemplate.self, forKey: .templates, default: defaults.templates)
        quickFolders = try container.decodeLossyArray(QuickFolder.self, forKey: .quickFolders)
        askForFileName = try container.decodeIfPresent(Bool.self, forKey: .askForFileName) ?? defaults.askForFileName
        openCreatedFile = try container.decodeIfPresent(Bool.self, forKey: .openCreatedFile) ?? defaults.openCreatedFile
        showConfirmations = try container.decodeIfPresent(Bool.self, forKey: .showConfirmations)
            ?? defaults.showConfirmations
    }
}

private struct LossyElement<Element: Decodable>: Decodable {
    let value: Element?

    init(from decoder: Decoder) throws {
        value = try? Element(from: decoder)
    }
}

extension KeyedDecodingContainer {
    fileprivate func decodeLossyArray<Element: Decodable>(
        _ type: Element.Type,
        forKey key: Key,
        default fallback: [Element] = []
    ) throws -> [Element] {
        guard contains(key) else { return fallback }
        return try decode([LossyElement<Element>].self, forKey: key).compactMap(\.value)
    }
}
