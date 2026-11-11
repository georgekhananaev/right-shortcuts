import AppKit
import FinderSync
import Observation
import ServiceManagement

/// Tracks whether the Finder extension is switched on. Only the user can switch it on,
/// in System Settings.
@MainActor
@Observable
final class ExtensionController {
    private(set) var isEnabled = FIFinderSyncController.isExtensionEnabled

    func refresh() {
        isEnabled = FIFinderSyncController.isExtensionEnabled
    }

    /// Opens System Settings at the list of Finder extensions.
    func openSystemSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }
}

/// Tracks and changes whether the app opens at login.
@MainActor
@Observable
final class LoginItemController {
    private(set) var status = SMAppService.mainApp.status
    private(set) var lastError: String?

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Whether macOS started the app at login, which should stay quiet.
    static func isLoginLaunch(appleEvent: NSAppleEventDescriptor?) -> Bool {
        appleEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }
}

/// Gives keyboard focus back to Finder after a system window, like the folder picker, closed.
@MainActor
enum FocusHandoff {
    static func returnToFinder() {
        guard NSApp.isActive, let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
        else { return }
        NSApp.yieldActivation(to: finder)
        finder.activate()
    }
}
