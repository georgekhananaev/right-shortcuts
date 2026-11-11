import Foundation
import RightShortcutsCore

/// Creates new files from templates and stores the templates the user adds.
public enum TemplateWriter {
    public enum Failure: LocalizedError, Equatable {
        case missingResource(String)

        public var errorDescription: String? {
            switch self {
            case .missingResource(let name): "The template file “\(name)” is missing."
            }
        }
    }

    /// Creates `destination` from the template. Never overwrites an existing file.
    /// - Parameter bundledTemplates: The folder holding the templates that ship with the app.
    public static func write(_ template: FileTemplate, to destination: URL, bundledTemplates: URL?) throws {
        let manager = FileManager.default
        switch template.source {
        case .text(let content):
            try Data(content.utf8).write(to: destination, options: .withoutOverwriting)
        case .bundled(let resource):
            guard let url = bundledTemplates?.appendingPathComponent(resource),
                  manager.fileExists(atPath: url.path) else { throw Failure.missingResource(resource) }
            try manager.copyItem(at: url, to: destination)
        case .file(let path):
            guard manager.fileExists(atPath: path) else {
                throw Failure.missingResource((path as NSString).lastPathComponent)
            }
            try manager.copyItem(at: URL(fileURLWithPath: path), to: destination)
        }
        if template.makesExecutable {
            try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        }
    }

    /// Copies a file the user picked into `directory` and returns a template for it.
    public static func importTemplate(from source: URL, into directory: URL) throws -> FileTemplate {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)

        let id = UUID().uuidString
        let fileExtension = source.pathExtension
        let stored = directory.appendingPathComponent(FileNaming.fileName(base: id, pathExtension: fileExtension))
        try manager.copyItem(at: source, to: stored)

        let baseName = source.deletingPathExtension().lastPathComponent
        return FileTemplate(
            id: id,
            name: baseName,
            fileExtension: fileExtension,
            baseName: baseName,
            symbol: "doc.on.doc",
            source: .file(path: stored.path)
        )
    }

    /// Deletes the stored copy of a user template. Files outside `directory` are never touched.
    public static func removeStoredFile(of template: FileTemplate, in directory: URL) {
        guard case .file(let path) = template.source,
              PathMatching.isPath(path, inside: directory.path),
              !PathMatching.isPath(directory.path, inside: path) else { return }
        try? FileManager.default.removeItem(atPath: path)
    }
}
