import Foundation

/// A throwaway folder tree for one test, removed when the test ends.
final class Sandbox {
    let root: URL

    init() throws {
        // Resolved, so paths compare equal to what the file system reports back.
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("RightShortcutsActions-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        // Locked and read-only items would survive a plain delete.
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let item = enumerator?.nextObject() as? URL {
            setLocked(false, item.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: item.path)
        }
        try? FileManager.default.removeItem(at: root)
    }

    /// Sets or clears the lock Finder shows as "Locked" in Get Info.
    func setLocked(_ locked: Bool, _ path: String) {
        var url = URL(fileURLWithPath: path)
        var values = URLResourceValues()
        values.isUserImmutable = locked
        try? url.setResourceValues(values)
    }

    func isLocked(_ relative: String) -> Bool {
        (try? root.appendingPathComponent(relative).resourceValues(forKeys: [.isUserImmutableKey]).isUserImmutable) == true
    }

    func path(_ relative: String) -> String {
        root.appendingPathComponent(relative).path
    }

    @discardableResult
    func folder(_ relative: String) throws -> String {
        try FileManager.default.createDirectory(atPath: path(relative), withIntermediateDirectories: true)
        return path(relative)
    }

    @discardableResult
    func file(_ relative: String, _ contents: String = "x", permissions: Int? = nil) throws -> String {
        try file(relative, data: Data(contents.utf8), permissions: permissions)
    }

    @discardableResult
    func file(_ relative: String, data: Data, permissions: Int? = nil) throws -> String {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        if let permissions {
            try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }
        return url.path
    }

    func exists(_ relative: String) -> Bool {
        (try? root.appendingPathComponent(relative).checkResourceIsReachable()) == true
            || FileManager.default.fileExists(atPath: path(relative))
    }

    func text(_ relative: String) -> String? {
        try? String(contentsOfFile: path(relative), encoding: .utf8)
    }

    func permissions(_ relative: String) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: path(relative))[.posixPermissions] as? NSNumber)?.intValue
    }

    func names(_ relative: String = "") -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: path(relative))) ?? []).sorted()
    }
}
