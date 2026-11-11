import Foundation
import RightShortcutsCore

/// The file system work behind the built-in actions.
public enum FileOperations {
    public enum Failure: LocalizedError, Equatable {
        case intoItself(String)
        case notText(String)
        case tooLarge(String)
        case protected(String)
        case couldNotCopy(name: String, reason: String)
        case couldNotMove(name: String, reason: String)
        case locked(String)

        public var errorDescription: String? {
            switch self {
            case .intoItself(let name): "“\(name)” can’t be put inside itself."
            case .notText(let name): "“\(name)” isn’t a text file."
            case .tooLarge(let name): "“\(name)” is too large to copy as text."
            case .protected(let name): "“\(name)” is a system or home folder, so Right Shortcuts leaves it alone."
            case .couldNotCopy(let name, let reason): "“\(name)” couldn’t be copied: \(reason)."
            case .couldNotMove(let name, let reason): "“\(name)” couldn’t be moved: \(reason)."
            case .locked(let name): "“\(name)” is locked, so nothing was changed. Unlock it in Finder’s Get Info window first."
            }
        }
    }

    /// Refuses to touch the startup disk, drive roots, the home folder and its standard folders,
    /// whichever path leads to them: a link, or the system's other name for the same folder.
    public static func ensureUnprotected(_ paths: [String], homeDirectory: String = UserHome.path) throws {
        let home = canonical(homeDirectory)
        if let path = paths.map(canonical).first(where: { PathSafety.isProtected($0, homeDirectory: home) }) {
            throw Failure.protected((path as NSString).lastPathComponent)
        }
    }

    /// The one true path of an existing item, with links followed.
    private static func canonical(_ path: String) -> String {
        (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.canonicalPathKey]).canonicalPath) ?? path
    }

    /// Refuses when an item, or anything inside it, is locked. Deleting or moving would stop
    /// half-way at the locked item, so it is better not to start.
    static func ensureNothingLocked(_ paths: [String], control: OperationControl) throws {
        for url in paths.map({ URL(fileURLWithPath: $0) }) {
            if isLocked(url) { throw Failure.locked(url.lastPathComponent) }
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isUserImmutableKey])
            while let item = enumerator?.nextObject() as? URL {
                try control.checkCancelled()
                if isLocked(item) { throw Failure.locked(item.lastPathComponent) }
            }
        }
    }

    /// True for items with the lock Finder shows in Get Info.
    static func isLocked(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isUserImmutableKey]).isUserImmutable) == true
    }

    /// True for real folders. Packages such as apps count as files.
    public static func isFolder(_ path: String) -> Bool {
        let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }

    public static func setHidden(_ hidden: Bool, paths: [String], homeDirectory: String = UserHome.path) throws {
        if hidden { try ensureUnprotected(paths, homeDirectory: homeDirectory) }
        for path in paths {
            var url = URL(fileURLWithPath: path)
            var values = URLResourceValues()
            values.isHidden = hidden
            try url.setResourceValues(values)
        }
    }

    /// Adds execute permission wherever read permission is set, like chmod +x.
    /// Symbolic links are resolved, so the permissions read and written belong to the same file.
    public static func makeExecutable(_ paths: [String]) throws {
        let manager = FileManager.default
        for path in paths.map({ URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }) {
            let current = (try manager.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber)?.intValue ?? 0o644
            let updated = current | ((current & 0o444) >> 2)
            try manager.setAttributes([.posixPermissions: updated], ofItemAtPath: path)
        }
    }

    /// Deletes right away, skipping the Trash. Stops before the next item once cancelled.
    public static func deletePermanently(
        _ paths: [String],
        homeDirectory: String = UserHome.path,
        control: OperationControl = OperationControl()
    ) throws {
        try ensureUnprotected(paths, homeDirectory: homeDirectory)
        try ensureNothingLocked(paths, control: control)
        for path in paths {
            try control.checkCancelled()
            try FileManager.default.removeItem(atPath: path)
        }
    }

    /// Reads text files and joins them with blank lines in between.
    public static func readText(_ paths: [String], limit: Int = 10_000_000) throws -> String {
        try paths.map { path in
            let name = (path as NSString).lastPathComponent
            let size = (try FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.intValue ?? 0
            guard size <= limit else { throw Failure.tooLarge(name) }
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard !data.contains(0), let text = String(data: data, encoding: .utf8) else {
                throw Failure.notText(name)
            }
            return text
        }.joined(separator: "\n\n")
    }
}

/// Folders that a cloud service keeps in sync.
public enum CloudFolders {
    /// True for a folder in iCloud Drive or another cloud provider, or anywhere inside one.
    /// Finder doesn't ask extensions for menu items in these folders.
    public static func isSynced(_ path: String) -> Bool {
        var url = URL(fileURLWithPath: path).standardizedFileURL
        if (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true { return true }
        // Each provider marks the top folder it manages.
        while url.path != "/" {
            if getxattr(url.path, "com.apple.file-provider-domain-id", nil, 0, 0, 0) >= 0 { return true }
            url.deleteLastPathComponent()
        }
        return false
    }
}
