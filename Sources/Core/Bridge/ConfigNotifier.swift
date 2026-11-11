import Foundation
import notify

/// A system-wide "configuration changed" signal. Darwin notifications cross the sandbox
/// boundary and carry no data, so they are safe for a sandboxed extension to listen to.
public enum ConfigNotifier {
    public static func post() {
        notify_post(AppIdentity.configChangedNotification)
    }

    /// Calls `handler` on the main queue whenever the configuration changes, for the life of the process.
    public static func observe(_ handler: @escaping () -> Void) {
        var token: Int32 = 0
        notify_register_dispatch(AppIdentity.configChangedNotification, &token, .main) { _ in handler() }
    }
}
