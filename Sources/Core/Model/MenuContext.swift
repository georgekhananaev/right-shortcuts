import Foundation

/// The places in Finder where a menu item can appear.
public enum MenuContext: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Right-click on one or more files.
    case files
    /// Right-click on one or more folders.
    case folders
    /// Right-click on the empty background of a Finder window.
    case background
    /// The Right Shortcuts button in Finder's toolbar.
    case toolbar

    public var id: String { rawValue }

    public static let all = Set(allCases)

    public var title: String {
        switch self {
        case .files: "Files"
        case .folders: "Folders"
        case .background: "Background"
        case .toolbar: "Toolbar"
        }
    }

    public var explanation: String {
        switch self {
        case .files: "When you right-click a file"
        case .folders: "When you right-click a folder"
        case .background: "When you right-click empty space in a window"
        case .toolbar: "In the Right Shortcuts toolbar button"
        }
    }

    public var symbol: String {
        switch self {
        case .files: "doc"
        case .folders: "folder"
        case .background: "macwindow"
        case .toolbar: "menubar.rectangle"
        }
    }
}
