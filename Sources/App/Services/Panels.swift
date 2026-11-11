import AppKit

/// The system's folder pickers, set up one way everywhere.
@MainActor
enum Panels {
    /// A picker for folders. It opens at `start` rather than wherever the previous picker ended up.
    static func folderPicker(
        message: String,
        prompt: String,
        startingAt start: URL?,
        allowsMultiple: Bool = false,
        canCreateFolders: Bool = false
    ) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = allowsMultiple
        panel.canCreateDirectories = canCreateFolders
        panel.directoryURL = start
        panel.message = message
        panel.prompt = prompt
        return panel
    }

    /// Shows a picker above other apps.
    /// - Parameter forFinderClick: The picker answers a click in Finder, so Finder gets the focus back afterwards.
    /// - Returns: The chosen folder, or nil if the user closed the picker.
    static func run(_ panel: NSOpenPanel, forFinderClick: Bool) -> URL? {
        // A click in Finder brings the app forward, but macOS may still decline; keep the picker visible.
        panel.level = .modalPanel
        NSApp.activate()
        let response = panel.runModal()
        if forFinderClick { FocusHandoff.returnToFinder() }
        return response == .OK ? panel.url : nil
    }
}
