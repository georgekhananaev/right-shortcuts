import Foundation

/// One entry in the user's right-click menu.
public struct MenuItem: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: Codable, Hashable, Sendable {
        case builtin(action: BuiltinAction)
        case openWith(app: OpenWithApp)
        case command(command: CustomCommand)
        case separator
    }

    public var id: UUID
    public var kind: Kind
    /// Replaces the default title when set.
    public var customTitle: String?
    /// Replaces the default SF Symbol when set.
    public var customSymbol: String?
    public var isEnabled: Bool
    public var contexts: Set<MenuContext>
    /// Limits the item to files with these extensions. Empty means any file.
    public var fileExtensions: [String]

    public init(
        id: UUID = UUID(),
        kind: Kind,
        customTitle: String? = nil,
        customSymbol: String? = nil,
        isEnabled: Bool = true,
        contexts: Set<MenuContext>? = nil,
        fileExtensions: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.customTitle = customTitle
        self.customSymbol = customSymbol
        self.isEnabled = isEnabled
        self.contexts = contexts ?? kind.defaultContexts
        self.fileExtensions = fileExtensions
    }

    public static func builtin(_ action: BuiltinAction) -> MenuItem {
        MenuItem(kind: .builtin(action: action), isEnabled: action.isEnabledByDefault)
    }

    public static func separator() -> MenuItem {
        MenuItem(kind: .separator)
    }

    public var isSeparator: Bool { kind == .separator }

    public var builtinAction: BuiltinAction? {
        if case .builtin(let action) = kind { action } else { nil }
    }

    public var title: String {
        if let customTitle, !customTitle.trimmingCharacters(in: .whitespaces).isEmpty {
            return customTitle
        }
        return kind.defaultTitle
    }

    public var symbol: String {
        if let customSymbol, !customSymbol.isEmpty { return customSymbol }
        return kind.defaultSymbol
    }

    /// The user's contexts limited to the ones the item supports.
    public var effectiveContexts: Set<MenuContext> {
        contexts.intersection(kind.supportedContexts)
    }

    /// Lowercased extensions without leading dots or blanks.
    public var normalizedExtensions: Set<String> {
        Set(fileExtensions.compactMap { raw in
            let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                .lowercased()
            return cleaned.isEmpty ? nil : cleaned
        })
    }
}

extension MenuItem.Kind {
    public var defaultTitle: String {
        switch self {
        case .builtin(let action): action.title
        case .openWith(let app): "Open in \(app.appName)"
        case .command(let command): command.name
        case .separator: "Separator"
        }
    }

    public var defaultSymbol: String {
        switch self {
        case .builtin(let action): action.symbol
        case .openWith: "arrow.up.forward.app"
        case .command: "terminal"
        case .separator: "minus"
        }
    }

    public var supportedContexts: Set<MenuContext> {
        if case .builtin(let action) = self { return action.supportedContexts }
        return MenuContext.all
    }

    public var defaultContexts: Set<MenuContext> {
        switch self {
        case .builtin(let action): action.defaultContexts
        case .openWith, .separator: MenuContext.all
        case .command: [.files, .folders, .toolbar]
        }
    }

    public var requiresSelection: Bool {
        switch self {
        case .builtin(let action): action.requiresSelection
        case .openWith, .command, .separator: false
        }
    }
}

/// An app that can open the selection.
public struct OpenWithApp: Codable, Hashable, Sendable {
    public var appPath: String
    public var appName: String
    public var bundleID: String?
    public var target: OpenTarget

    public init(appPath: String, appName: String, bundleID: String?, target: OpenTarget = .automatic) {
        self.appPath = appPath
        self.appName = appName
        self.bundleID = bundleID
        self.target = target
    }
}

/// What gets handed to an app.
public enum OpenTarget: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Terminals get the folder, everything else gets the selected items.
    case automatic
    /// Always the selected items.
    case items
    /// Always a folder: the selected folder, or the folder holding the selected files.
    case folder

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: "Automatic"
        case .items: "The selected items"
        case .folder: "The enclosing folder"
        }
    }
}

/// A user-defined shell script.
public struct CustomCommand: Codable, Hashable, Sendable {
    public var name: String
    /// Runs with zsh. The selected paths are passed as "$@".
    public var script: String
    public var runMode: RunMode

    public init(name: String, script: String, runMode: RunMode = .background) {
        self.name = name
        self.script = script
        self.runMode = runMode
    }
}

public enum RunMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case background
    case terminal

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .background: "In the background"
        case .terminal: "In a Terminal window"
        }
    }
}
