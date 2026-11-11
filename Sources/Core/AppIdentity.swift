import Foundation
import Security

/// Identifiers shared by the app and its Finder extension.
public enum AppIdentity {
    public static let displayName = "Right Shortcuts"
    public static let hostBundleID = "com.georgekhananaev.RightShortcuts"
    public static let urlScheme = "rightshortcuts"
    public static let configChangedNotification = "com.georgekhananaev.RightShortcuts.configChanged"
    public static let menuSymbol = "contextualmenu.and.cursorarrow"

    /// Pages in the public repository. The App Store listing uses the same two addresses,
    /// so the files they name must stay where they are.
    public static let privacyPolicyURL = publishedPage("PRIVACY.md")
    public static let supportURL = publishedPage("SUPPORT.md")

    private static func publishedPage(_ fileName: String) -> URL {
        URL(string: "https://github.com/georgekhananaev/right-shortcuts/blob/main/")!.appendingPathComponent(fileName)
    }

    /// The App Group shared by the app and the extension, read from this process's own
    /// entitlements. It starts with the signing team's ID, so it can't be hard-coded.
    public static let appGroupID: String? = {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        let groups = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil)
        return (groups as? [String])?.first
    }()
}
