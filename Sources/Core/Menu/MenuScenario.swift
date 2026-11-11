import Foundation

/// Which Finder menu is being built.
public enum MenuLocation: String, Codable, Sendable {
    /// Right-click on selected items.
    case items
    /// Right-click on the background of a folder window.
    case container
    /// Right-click on a sidebar entry.
    case sidebar
    /// The extension's toolbar button.
    case toolbar
}

/// A selected item, as far as the menu needs to know.
public struct SelectedItem: Hashable, Sendable {
    public var path: String
    /// True for real folders. Packages such as apps count as files.
    public var isDirectory: Bool
    /// Nil when the extension couldn't read the attribute.
    public var isHidden: Bool?

    public init(path: String, isDirectory: Bool, isHidden: Bool? = nil) {
        self.path = path
        self.isDirectory = isDirectory
        self.isHidden = isHidden
    }

    public var pathExtension: String {
        (path as NSString).pathExtension.lowercased()
    }
}

/// The situation a menu is built for.
public struct MenuScenario: Sendable {
    public var location: MenuLocation
    /// The folder the user is looking at, or the right-clicked sidebar entry.
    public var targetPath: String?
    public var items: [SelectedItem]

    public init(location: MenuLocation, targetPath: String?, items: [SelectedItem]) {
        self.location = location
        self.targetPath = targetPath
        self.items = items
    }
}

/// Identifies what to run when a menu entry is clicked.
public struct ActionTarget: Codable, Hashable, Sendable {
    public static let chooseFolderOption = "choose"

    public var itemID: UUID
    /// Extra detail for submenu entries: a template ID, a copy format or a quick folder ID.
    public var option: String?

    public init(itemID: UUID, option: String? = nil) {
        self.itemID = itemID
        self.option = option
    }
}

/// A resolved entry, ready to become an NSMenuItem or a preview row.
public struct MenuNode: Identifiable, Hashable, Sendable {
    public enum Content: Hashable, Sendable {
        case action(ActionTarget)
        case submenu([MenuNode])
        case separator
    }

    public var id: String
    public var title: String
    public var symbol: String?
    /// Set for "Open in …" entries so the app's own icon can be shown.
    public var appPath: String?
    public var content: Content

    public init(id: String, title: String, symbol: String? = nil, appPath: String? = nil, content: Content) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.appPath = appPath
        self.content = content
    }

    public static func separator(id: String) -> MenuNode {
        MenuNode(id: id, title: "", content: .separator)
    }

    public var isSeparator: Bool { content == .separator }
}
