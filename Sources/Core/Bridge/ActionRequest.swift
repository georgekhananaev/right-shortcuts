import Foundation

/// A menu click, sent from the Finder extension to the app.
public struct ActionRequest: Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var target: ActionTarget
    public var location: MenuLocation
    public var targetPath: String?
    public var selectedPaths: [String]

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        target: ActionTarget,
        location: MenuLocation,
        targetPath: String?,
        selectedPaths: [String]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.target = target
        self.location = location
        self.targetPath = targetPath
        self.selectedPaths = selectedPaths
    }

    /// The selected items that apply. A background click acts on the folder,
    /// even if Finder still reports an earlier selection.
    public var selection: [String] {
        location == .container ? [] : selectedPaths
    }

    /// The items to act on: the selection, or the current folder when nothing is selected.
    public var operandPaths: [String] {
        if !selection.isEmpty { return selection }
        return targetPath.map { [$0] } ?? []
    }

    /// What a built-in action works on. Actions on selected items never fall back to the current
    /// folder, so Delete Permanently or Move To can't hit the folder itself if Finder reports no selection.
    public func operands(for action: BuiltinAction) -> [String] {
        action.requiresSelection ? selection : operandPaths
    }

    /// What "Open in …" hands to the app: the items, or the folder to work in.
    public func pathsToOpen(with app: OpenWithApp, isDirectory: (String) -> Bool) -> [String] {
        if app.opensFolder && !selection.allSatisfy(isDirectory) {
            return workingDirectory(isDirectory: isDirectory).map { [$0] } ?? []
        }
        return operandPaths
    }

    /// The folder to work in: the current folder, a single selected folder,
    /// or the folder holding the selected files.
    public func workingDirectory(isDirectory: (String) -> Bool) -> String? {
        guard let first = selection.first else { return targetPath }
        if selection.count == 1 && isDirectory(first) { return first }
        return (first as NSString).deletingLastPathComponent
    }
}

/// Requests travel as files in the shared container. The custom URL only rings the doorbell,
/// so a web page or another app can't forge a request by opening a link.
public enum ActionInbox {
    public static func post(_ request: ActionRequest) throws -> URL {
        let directory = SharedContainer.inboxURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(request)
        try data.write(to: directory.appendingPathComponent("\(request.id.uuidString).json"), options: .atomic)
        guard let url = URL(string: "\(AppIdentity.urlScheme)://perform/\(request.id.uuidString)") else {
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }

    /// Removes and returns every waiting request, oldest first. Stale requests are dropped.
    public static func drain(maxAge: TimeInterval = 120, now: Date = Date()) -> [ActionRequest] {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(
            at: SharedContainer.inboxURL,
            includingPropertiesForKeys: nil
        ) else { return [] }

        let requests = files.filter { $0.pathExtension == "json" }.compactMap { file -> ActionRequest? in
            defer { try? manager.removeItem(at: file) }
            guard let data = try? Data(contentsOf: file) else { return nil }
            return try? JSONDecoder().decode(ActionRequest.self, from: data)
        }
        return requests
            .filter { now.timeIntervalSince($0.createdAt) <= maxAge }
            .sorted { $0.createdAt < $1.createdAt }
    }
}
