import Foundation

/// The user's real home folder. Inside the App Sandbox, `NSHomeDirectory()` points into the
/// app's container instead, which is never what paths shown to the user should start from.
public enum UserHome {
    public static let path: String = {
        guard let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir else { return NSHomeDirectory() }
        return String(cString: directory)
    }()

    /// Shortens paths inside the home folder to start with `~`.
    public static func abbreviate(_ path: String, home: String = UserHome.path) -> String {
        let base = home.count > 1 && home.hasSuffix("/") ? String(home.dropLast()) : home
        if path == base { return "~" }
        return path.hasPrefix(base + "/") ? "~" + path.dropFirst(base.count) : path
    }
}
