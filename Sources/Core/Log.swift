import os

/// Unified logging. Read with:
/// `log show --last 10m --predicate 'subsystem == "com.georgekhananaev.RightShortcuts"'`
public enum Log {
    public static let app = Logger(subsystem: AppIdentity.hostBundleID, category: "app")
    public static let finder = Logger(subsystem: AppIdentity.hostBundleID, category: "finder-extension")
}
