import Foundation

/// Formats for the Copy Path As submenu.
public enum CopyFormat: String, Codable, CaseIterable, Sendable {
    case fullPath
    case tildePath
    case name
    case nameWithoutExtension
    case parentPath
    case shellQuoted
    case fileURL

    public var title: String {
        switch self {
        case .fullPath: "Full Path"
        case .tildePath: "Path with ~"
        case .name: "Name"
        case .nameWithoutExtension: "Name Without Extension"
        case .parentPath: "Enclosing Folder Path"
        case .shellQuoted: "Path Quoted for Shell"
        case .fileURL: "File URL"
        }
    }

    /// Formats each path and joins them: spaces for shell arguments, new lines otherwise.
    public func string(for paths: [String], homeDirectory: String) -> String {
        let parts = paths.map { format($0, homeDirectory: homeDirectory) }
        return parts.joined(separator: self == .shellQuoted ? " " : "\n")
    }

    private func format(_ path: String, homeDirectory: String) -> String {
        let nsPath = path as NSString
        switch self {
        case .fullPath:
            return path
        case .tildePath:
            return UserHome.abbreviate(path, home: homeDirectory)
        case .name:
            return nsPath.lastPathComponent
        case .nameWithoutExtension:
            return (nsPath.lastPathComponent as NSString).deletingPathExtension
        case .parentPath:
            return nsPath.deletingLastPathComponent
        case .shellQuoted:
            return ShellQuoting.quote(path)
        case .fileURL:
            return URL(fileURLWithPath: path).absoluteString
        }
    }
}

public enum ShellQuoting {
    /// Wraps a string in single quotes so any shell reads it literally.
    public static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}

public enum PathMatching {
    /// True when `path` is `folder` or anywhere below it.
    public static func isPath(_ path: String, inside folder: String) -> Bool {
        let base = normalized(folder)
        let candidate = normalized(path)
        if base == "/" { return true }
        return candidate == base || candidate.hasPrefix(base + "/")
    }

    public static func isPath(_ path: String, insideAny folders: [String]) -> Bool {
        folders.contains { isPath(path, inside: $0) }
    }

    /// The deepest folder that holds every path, or nil for an empty list.
    public static func commonAncestor(of paths: [String]) -> String? {
        let split = paths.map { normalized($0).split(separator: "/") }
        guard var shared = split.first else { return nil }
        for components in split.dropFirst() {
            let length = zip(shared, components).prefix { $0 == $1 }.count
            shared = Array(shared.prefix(length))
        }
        return "/" + shared.joined(separator: "/")
    }

    private static func normalized(_ path: String) -> String {
        var result = (path as NSString).standardizingPath
        while result.count > 1 && result.hasSuffix("/") { result.removeLast() }
        return result
    }
}

public enum PathSafety {
    private static let homeFolders: Set<String> = [
        "Applications", "Desktop", "Documents", "Downloads", "Library", "Movies", "Music", "Pictures", "Public",
    ]

    /// True for places that must never be deleted, moved or hidden by a stray click: the startup
    /// disk, its top-level folders, drive roots, the home folder and the standard folders in it.
    public static func isProtected(_ path: String, homeDirectory: String) -> Bool {
        let standardized = (path as NSString).standardizingPath
        let home = (homeDirectory as NSString).standardizingPath
        let parent = (standardized as NSString).deletingLastPathComponent
        let name = (standardized as NSString).lastPathComponent
        return standardized == "/"
            || parent == "/"
            || parent == "/Volumes"
            || standardized == home
            || (parent == home && homeFolders.contains(name))
    }
}

public enum FileNaming {
    public static func fileName(base: String, pathExtension: String) -> String {
        pathExtension.isEmpty ? base : "\(base).\(pathExtension)"
    }

    /// The name to try on the given attempt: "name", then "name 2", "name 3" …
    /// Files keep their extension: "report 2.pdf".
    public static func candidateName(_ name: String, isDirectory: Bool, attempt: Int) -> String {
        guard attempt > 1 else { return name }
        let nsName = name as NSString
        let fileExtension = isDirectory ? "" : nsName.pathExtension
        let base = fileExtension.isEmpty ? name : nsName.deletingPathExtension
        return fileName(base: "\(base) \(attempt)", pathExtension: fileExtension)
    }

    /// True when something has this name, including a link that points nowhere.
    public static func itemExists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    /// Returns `directory/name`, or "name 2", "name 3" … if that is taken.
    public static func availableURL(
        in directory: URL,
        name: String,
        isDirectory: Bool = false,
        exists: (URL) -> Bool = FileNaming.itemExists
    ) -> URL {
        var attempt = 1
        while true {
            let candidate = directory.appendingPathComponent(
                candidateName(name, isDirectory: isDirectory, attempt: attempt),
                isDirectory: isDirectory
            )
            if !exists(candidate) { return candidate }
            attempt += 1
        }
    }

    /// A message describing why the name can't be used, or nil when it's fine.
    public static func problem(with name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Enter a name." }
        if trimmed.contains("/") || trimmed.contains(":") { return "Names can’t contain “/” or “:”." }
        if trimmed == "." || trimmed == ".." { return "Choose a different name." }
        if trimmed.utf8.count > 255 { return "That name is too long." }
        return nil
    }
}
