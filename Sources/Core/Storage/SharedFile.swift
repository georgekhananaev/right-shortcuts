import Foundation

/// Locations inside the App Group container that both processes can reach.
public enum SharedContainer {
    public static var rootURL: URL {
        if let group = AppIdentity.appGroupID,
           let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
            return url
        }
        // Unsigned development builds have no App Group. The app still works, the extension won't.
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent(AppIdentity.displayName, isDirectory: true)
    }

    public static var configURL: URL { rootURL.appendingPathComponent("config.json") }
    public static var accessURL: URL { rootURL.appendingPathComponent("access.json") }
    public static var inboxURL: URL { rootURL.appendingPathComponent("Inbox", isDirectory: true) }
    public static var templatesURL: URL { rootURL.appendingPathComponent("Templates", isDirectory: true) }
}

/// A JSON file both processes read. The app writes it; the extension reloads it when told.
public struct SharedFile<Value: Codable & Sendable>: Sendable {
    public enum Stored: Sendable {
        case none
        case valid(Value)
        /// The file exists but couldn't be read, for example after a manual edit went wrong.
        case damaged
    }

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func read() -> Stored {
        guard FileManager.default.fileExists(atPath: url.path) else { return .none }
        guard let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(Value.self, from: data) else { return .damaged }
        return .valid(value)
    }

    /// Nil when there is no usable file.
    public func load() -> Value? {
        if case .valid(let value) = read() { value } else { nil }
    }

    /// Writes the file and tells the other process to reload it.
    public func save(_ value: Value) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        ConfigNotifier.post()
    }

    /// Lets a reader skip re-reading an unchanged file.
    public func modificationDate() -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date
    }

    /// Sets a copy aside as "name.label-date.json", so replacing the file never destroys what was in it.
    /// - Returns: Where the copy went.
    public func backUp(label: String, removingOriginal: Bool) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let name = url.deletingPathExtension().lastPathComponent
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("\(name).\(label)-\(formatter.string(from: Date())).\(url.pathExtension)")
        if removingOriginal {
            try FileManager.default.moveItem(at: url, to: backup)
        } else {
            try FileManager.default.copyItem(at: url, to: backup)
        }
        return backup
    }
}

/// The files the app and the extension share.
public enum SharedFiles {
    /// The user's settings.
    public static var config: SharedFile<AppConfig> { SharedFile(url: SharedContainer.configURL) }
    /// What the app is currently allowed to do.
    public static var hostAccess: SharedFile<HostAccess> { SharedFile(url: SharedContainer.accessURL) }
}
