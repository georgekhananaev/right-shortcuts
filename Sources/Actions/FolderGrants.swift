import Foundation
import RightShortcutsCore

/// The folders the user allowed the app to work in. A sandboxed app can only reach folders the
/// user picked, and keeps that permission across restarts as security-scoped bookmarks.
public final class FolderGrants {
    private struct Entry {
        var path: String
        var bookmark: Data
        /// The resolved folder while it can be reached, with whether access had to be started.
        var active: (url: URL, started: Bool)?
    }

    private let defaults: UserDefaults
    private let key: String
    private var entries: [Entry]

    public init(defaults: UserDefaults = .standard, key: String = "folderGrants") {
        self.defaults = defaults
        self.key = key
        let stored = defaults.array(forKey: key) as? [[String: Any]] ?? []
        entries = stored.compactMap { item in
            guard let path = item["path"] as? String, let bookmark = item["bookmark"] as? Data else { return nil }
            return Entry(path: path, bookmark: bookmark)
        }
        refresh()
    }

    /// Every allowed folder, including ones that can't be reached right now.
    public var folders: [String] { entries.map(\.path) }

    /// Allowed folders that are missing, for example on a drive that isn't connected.
    public var unavailableFolders: [String] { entries.filter { $0.active == nil }.map(\.path) }

    public var availableFolders: [String] { entries.filter { $0.active != nil }.map(\.path) }

    public func covers(_ path: String) -> Bool {
        PathMatching.isPath(path, insideAny: availableFolders)
    }

    /// Remembers a folder the user just picked. Folders inside it no longer need their own entry.
    public func add(_ url: URL) throws {
        let folder = url.standardizedFileURL
        guard !covers(folder.path) else { return }
        let bookmark = try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil,
                                               relativeTo: nil)
        for entry in entries where PathMatching.isPath(entry.path, inside: folder.path) { release(entry) }
        entries.removeAll { PathMatching.isPath($0.path, inside: folder.path) }
        entries.append(Entry(path: folder.path, bookmark: bookmark,
                             active: (folder, folder.startAccessingSecurityScopedResource())))
        save()
    }

    public func remove(_ path: String) {
        for entry in entries where entry.path == path { release(entry) }
        entries.removeAll { $0.path == path }
        save()
    }

    /// Checks every folder again: drives come and go, and folders get renamed.
    public func refresh() {
        var changed = false
        for index in entries.indices {
            if let active = entries[index].active {
                if (try? active.url.checkResourceIsReachable()) == true { continue }
                release(entries[index])
                entries[index].active = nil
            }
            var isStale = false
            // Never mount a missing drive or put up a connect window just to look; it is simply unavailable.
            guard let url = try? URL(resolvingBookmarkData: entries[index].bookmark,
                                     options: [.withSecurityScope, .withoutMounting, .withoutUI],
                                     relativeTo: nil, bookmarkDataIsStale: &isStale) else { continue }
            let started = url.startAccessingSecurityScopedResource()
            guard (try? url.checkResourceIsReachable()) == true else {
                if started { url.stopAccessingSecurityScopedResource() }
                continue
            }
            entries[index].active = (url, started)
            if entries[index].path != url.standardizedFileURL.path {
                entries[index].path = url.standardizedFileURL.path
                changed = true
            }
            if isStale, let fresh = try? url.bookmarkData(options: .withSecurityScope,
                                                          includingResourceValuesForKeys: nil, relativeTo: nil) {
                entries[index].bookmark = fresh
                changed = true
            }
        }
        if changed { save() }
    }

    private func release(_ entry: Entry) {
        if let active = entry.active, active.started { active.url.stopAccessingSecurityScopedResource() }
    }

    private func save() {
        defaults.set(entries.map { ["path": $0.path, "bookmark": $0.bookmark] as [String: Any] }, forKey: key)
    }
}
