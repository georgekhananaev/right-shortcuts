import AppKit

// A plain AppKit entry point keeps full control over windows, activation and URL events,
// which a menu bar app needs. The interface itself is SwiftUI.
let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.run()
