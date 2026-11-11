import AppKit
import Observation
import RightShortcutsActions
import RightShortcutsCore

/// What the sandbox lets the app do, and the questions that widen it: which folders it may
/// work in, and whether it may run custom commands.
@MainActor
@Observable
final class AccessController {
    enum Problem: LocalizedError {
        case notCovered(needed: String, chosen: String)
        case wrongScriptsFolder
        case helperUnavailable

        var errorDescription: String? {
            switch self {
            case .notCovered(let needed, let chosen):
                "“\(chosen)” doesn’t include “\(needed)”, so nothing was changed."
            case .wrongScriptsFolder:
                "The command helper only works in the folder that opens. Try again without choosing another folder."
            case .helperUnavailable:
                "The command helper is missing from this copy of Right Shortcuts. Install the app again."
            }
        }
    }

    /// Every folder the user allowed, in the order they were added.
    private(set) var folders: [String] = []
    /// Allowed folders that can't be reached right now, such as on a drive that isn't connected.
    private(set) var unavailableFolders: [String] = []
    private(set) var helperState: HelperScript.State = .missing

    @ObservationIgnored private let grants = FolderGrants()
    @ObservationIgnored private let helper = AccessController.makeHelper()
    @ObservationIgnored private var published = SharedFiles.hostAccess.load()

    init() {
        update()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    var worksEverywhere: Bool { grants.covers("/") }

    /// Looks again at drives that came or went and at the installed helper.
    func refresh() {
        grants.refresh()
        update()
    }

    // MARK: - Folders

    /// From settings: asks for the whole disk, which covers every folder and drive in one step.
    func allowEverywhere() {
        attempt {
            try requestAccess(covering: [], startingAt: "/", forFinderClick: false,
                              message: "Choose your disk to let Right Shortcuts work in every folder. "
                                  + "It only touches files when you pick one of its menu items.")
        }
    }

    /// From settings: asks for one more folder of the user's choice.
    func allowAnotherFolder() {
        attempt {
            try requestAccess(covering: [], startingAt: UserHome.path, forFinderClick: false,
                              message: "Choose a folder Right Shortcuts may work in, including everything inside it.")
        }
    }

    func revoke(_ folder: String) {
        grants.remove(folder)
        update()
    }

    /// Quietly remembers a folder the user just picked for something else, like a quick folder.
    func remember(_ folder: URL) {
        do {
            try grants.add(folder)
            update()
        } catch {
            // Not fatal: the app asks again when an action first needs the folder.
            Log.app.error("Couldn’t remember a folder: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// After a click in Finder: makes sure the app may work on `paths`, asking for the folder
    /// that holds them when it may not yet.
    /// - Throws: `CancellationError` if the user closed the picker, or the reason it didn't help.
    func ensureAccess(to paths: [String]) throws {
        let missing = paths.filter { !grants.covers($0) }
        guard let first = missing.first, var start = PathMatching.commonAncestor(of: missing) else { return }
        // Ask for no more than the action needs: the folder itself, or the one holding the file.
        if !FileOperations.isFolder(start) { start = (start as NSString).deletingLastPathComponent }
        let name = FileManager.default.displayName(atPath: first)
        try requestAccess(
            covering: missing,
            startingAt: start,
            forFinderClick: true,
            message: "Right Shortcuts needs your permission to work with “\(name)”. Allow this folder, "
                + "or choose your disk in the sidebar to allow every folder at once."
        )
    }

    private func requestAccess(covering paths: [String], startingAt start: String, forFinderClick: Bool,
                               message: String) throws {
        let panel = Panels.folderPicker(message: message, prompt: "Allow",
                                        startingAt: URL(fileURLWithPath: start, isDirectory: true))
        guard let chosen = Panels.run(panel, forFinderClick: forFinderClick) else { throw CancellationError() }

        try grants.add(chosen)
        update()
        if let uncovered = paths.first(where: { !grants.covers($0) }) {
            throw Problem.notCovered(needed: FileManager.default.displayName(atPath: uncovered),
                                     chosen: FileManager.default.displayName(atPath: chosen.path))
        }
    }

    // MARK: - Command helper

    /// The folder macOS runs this app's scripts from.
    var scriptsFolder: URL? { helper?.installed.deletingLastPathComponent() }

    /// After a click in Finder: the helper, ready to run commands. Asks to install it first when needed.
    func ensureHelper() throws -> HelperScript {
        guard let helper else { throw Problem.helperUnavailable }
        if helper.state != .installed { try installHelper(forFinderClick: true) }
        return helper
    }

    /// Shows the scripts folder and installs the helper there once the user agrees.
    /// macOS only lets an app add scripts to that folder with the user's say-so.
    private func installHelper(forFinderClick: Bool) throws {
        guard let helper, let folder = scriptsFolder else { throw Problem.helperUnavailable }
        let panel = Panels.folderPicker(
            message: "Custom commands run through a small helper script that macOS keeps in this folder. "
                + "Click Install to add it here.",
            prompt: "Install",
            startingAt: folder
        )
        guard let chosen = Panels.run(panel, forFinderClick: forFinderClick) else { throw CancellationError() }
        guard chosen.standardizedFileURL.path == folder.standardizedFileURL.path else { throw Problem.wrongScriptsFolder }

        try helper.install()
        update()
    }

    /// For buttons in settings: installs the helper and shows what went wrong, if anything.
    func installHelperFromSettings() {
        attempt { try installHelper(forFinderClick: false) }
    }

    /// Runs a step the user started from settings. Closing the picker is not a problem worth reporting.
    private func attempt(_ step: () throws -> Void) {
        do {
            try step()
        } catch is CancellationError {
            return
        } catch {
            Log.app.error("Access change failed: \(error.localizedDescription, privacy: .public)")
            ToastCenter.shared.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill", style: .failure)
        }
    }

    /// The names of the standard folders a cloud service keeps in sync. Finder shows no
    /// extension menus in those, which is worth telling the user before they wonder.
    static func cloudSyncedHomeFolders() -> [String] {
        ["Desktop", "Documents"].filter { CloudFolders.isSynced((UserHome.path as NSString).appendingPathComponent($0)) }
    }

    // MARK: - Plumbing

    private static func makeHelper() -> HelperScript? {
        guard let bundled = Bundle.main.url(forResource: "CommandHelper", withExtension: "txt"),
              let folder = try? FileManager.default.url(for: .applicationScriptsDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true) else { return nil }
        // The bundled copy is plain text so no build tool compiles it; macOS runs it as an AppleScript once installed.
        return HelperScript(bundled: bundled, installed: folder.appendingPathComponent("Right Shortcuts Commands.applescript"))
    }

    /// Refreshes what the interface shows and tells the Finder extension when something changed.
    private func update() {
        folders = grants.folders
        unavailableFolders = grants.unavailableFolders
        helperState = helper?.state ?? .missing

        let current = HostAccess(folders: grants.availableFolders, canRunCommands: helperState == .installed)
        guard current != published else { return }
        do {
            try SharedFiles.hostAccess.save(current)
            published = current
        } catch {
            Log.app.error("Couldn’t share the access list: \(error.localizedDescription, privacy: .public)")
        }
    }
}
