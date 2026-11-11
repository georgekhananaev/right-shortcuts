import Foundation

/// What the sandboxed app may do right now. The app publishes it so the extension can tell
/// whether a click will first have to ask for permission, which needs the app in front.
public struct HostAccess: Codable, Equatable, Sendable {
    /// Folders the user allowed the app to work in, including everything inside them.
    public var folders: [String]
    /// Whether the helper for custom commands is installed.
    public var canRunCommands: Bool

    public init(folders: [String] = [], canRunCommands: Bool = false) {
        self.folders = folders
        self.canRunCommands = canRunCommands
    }

    public func covers(_ path: String) -> Bool {
        PathMatching.isPath(path, insideAny: folders)
    }
}

extension AppConfig {
    /// The folders and items a click will read, change or open. Empty for actions that only
    /// use the path itself, such as Copy Path, and for commands, which run through the helper.
    public func pathsNeedingAccess(for request: ActionRequest, isDirectory: (String) -> Bool) -> [String] {
        guard let item = items.first(where: { $0.id == request.target.itemID }) else { return [] }
        switch item.kind {
        case .openWith(let app):
            return request.pathsToOpen(with: app, isDirectory: isDirectory)
        case .command, .separator:
            return []
        case .builtin(let action):
            // A quick folder is written to or opened. A folder from the picker comes with its own permission.
            let quickFolder = action.usesQuickFolder
                ? quickFolders.first { $0.id.uuidString == request.target.option }?.path
                : nil
            if action == .goTo { return quickFolder.map { [$0] } ?? [] }

            let operands = request.operands(for: action)
            var paths: [String]
            switch action.fileAccess {
            case .none: return []
            case .workingFolder: paths = request.workingDirectory(isDirectory: isDirectory).map { [$0] } ?? []
            case .items: paths = operands
            case .enclosingFolders: paths = operands.map { ($0 as NSString).deletingLastPathComponent }
            }
            guard !paths.isEmpty else { return [] }
            if let quickFolder { paths.append(quickFolder) }
            return paths.reduce(into: []) { unique, path in
                if !unique.contains(path) { unique.append(path) }
            }
        }
    }

    /// Whether a click opens a system window that needs the app in front: AirDrop, the folder
    /// picker, or a request for permission. The app's own prompts work without it.
    public func needsActivation(
        _ request: ActionRequest,
        access: HostAccess,
        isDirectory: (String) -> Bool
    ) -> Bool {
        guard let item = items.first(where: { $0.id == request.target.itemID }) else { return false }
        if case .command = item.kind { return !access.canRunCommands }
        if case .builtin(let action) = item.kind {
            if action == .airDrop { return true }
            if (action == .copyTo || action == .moveTo) && request.target.option == ActionTarget.chooseFolderOption {
                return true
            }
        }
        return !pathsNeedingAccess(for: request, isDirectory: isDirectory).allSatisfy(access.covers)
    }
}
