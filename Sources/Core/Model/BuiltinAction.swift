import Foundation

/// Actions that ship with the app.
public enum BuiltinAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case newFile
    case copyPath
    case copyName
    case copyPathAs
    case copyContents
    case copyTo
    case moveTo
    case goTo
    case makeExecutable
    case hide
    case unhide
    case airDrop
    case deletePermanently

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .newFile: "New File"
        case .copyPath: "Copy Path"
        case .copyName: "Copy Name"
        case .copyPathAs: "Copy Path As"
        case .copyContents: "Copy Contents"
        case .copyTo: "Copy To"
        case .moveTo: "Move To"
        case .goTo: "Go To"
        case .makeExecutable: "Make Executable"
        case .hide: "Hide"
        case .unhide: "Unhide"
        case .airDrop: "AirDrop"
        case .deletePermanently: "Delete Permanently"
        }
    }

    public var summary: String {
        switch self {
        case .newFile: "Create a new file from one of your templates."
        case .copyPath: "Copy the full path of the selected items."
        case .copyName: "Copy only the file or folder name."
        case .copyPathAs: "Copy the path in another format: with ~, quoted for the shell, as a file URL and more."
        case .copyContents: "Copy the text inside a file to the clipboard."
        case .copyTo: "Copy the selected items to one of your quick folders."
        case .moveTo: "Move the selected items to one of your quick folders."
        case .goTo: "Open one of your quick folders in Finder."
        case .makeExecutable: "Let scripts run, like chmod +x."
        case .hide: "Hide items in Finder."
        case .unhide: "Make hidden items visible again."
        case .airDrop: "Send the selected items with AirDrop."
        case .deletePermanently: "Delete right away, skipping the Trash. Always asks first."
        }
    }

    public var symbol: String {
        switch self {
        case .newFile: "doc.badge.plus"
        case .copyPath: "doc.on.clipboard"
        case .copyName: "character.cursor.ibeam"
        case .copyPathAs: "list.clipboard"
        case .copyContents: "doc.plaintext"
        case .copyTo: "plus.rectangle.on.folder"
        case .moveTo: "folder.badge.gearshape"
        case .goTo: "arrow.right.circle"
        case .makeExecutable: "terminal"
        case .hide: "eye.slash"
        case .unhide: "eye"
        case .airDrop: "dot.radiowaves.left.and.right"
        case .deletePermanently: "xmark.bin"
        }
    }

    /// Contexts where the action makes sense at all.
    public var supportedContexts: Set<MenuContext> {
        switch self {
        case .newFile, .goTo, .copyPath, .copyName, .copyPathAs:
            MenuContext.all
        case .copyContents, .makeExecutable:
            [.files, .toolbar]
        case .copyTo, .moveTo, .hide, .unhide, .airDrop, .deletePermanently:
            [.files, .folders, .toolbar]
        }
    }

    /// Contexts switched on for a fresh install.
    public var defaultContexts: Set<MenuContext> {
        switch self {
        case .newFile: [.folders, .background, .toolbar]
        case .goTo: [.background, .toolbar]
        default: supportedContexts
        }
    }

    public var isEnabledByDefault: Bool {
        switch self {
        case .copyContents, .goTo, .makeExecutable: false
        default: true
        }
    }

    /// Whether the action needs selected items, as opposed to working on the current folder.
    public var requiresSelection: Bool {
        switch self {
        case .newFile, .goTo, .copyPath, .copyName, .copyPathAs: false
        default: true
        }
    }

    /// Which files the action reads or changes. The sandboxed app needs the user's
    /// permission for exactly these before it can run the action.
    public enum FileAccess: Sendable {
        /// Only the path is used; the file itself is never touched.
        case none
        /// A new item appears in the folder being worked in.
        case workingFolder
        /// The selected items are read or changed in place.
        case items
        /// Items are removed from the folders that hold them.
        case enclosingFolders
    }

    public var fileAccess: FileAccess {
        switch self {
        case .copyPath, .copyName, .copyPathAs, .goTo: .none
        case .newFile: .workingFolder
        case .copyContents, .copyTo, .makeExecutable, .hide, .unhide, .airDrop: .items
        case .moveTo, .deletePermanently: .enclosingFolders
        }
    }

    /// Whether the action's submenu lists the quick folders.
    public var usesQuickFolder: Bool {
        self == .copyTo || self == .moveTo || self == .goTo
    }

    /// Whether the action opens a submenu instead of running directly.
    public var opensSubmenu: Bool {
        switch self {
        case .newFile, .copyPathAs, .copyTo, .moveTo, .goTo: true
        default: false
        }
    }
}
