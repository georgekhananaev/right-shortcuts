import Foundation
@testable import RightShortcutsActions
import RightShortcutsCore
import Testing

@Suite("File operations")
struct FileOperationsTests {
    private let box: Sandbox
    private var home: String { box.path("Home") }

    init() throws {
        box = try Sandbox()
    }

    private func isHidden(_ path: String) -> Bool? {
        try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isHiddenKey]).isHidden
    }

    @Test func hidesAndShowsItems() throws {
        let file = try box.file("notes.txt")
        try FileOperations.setHidden(true, paths: [file], homeDirectory: home)
        #expect(isHidden(file) == true)
        try FileOperations.setHidden(false, paths: [file], homeDirectory: home)
        #expect(isHidden(file) == false)
    }

    @Test func refusesToHideProtectedFolders() throws {
        let downloads = try box.folder("Home/Downloads")
        #expect(throws: FileOperations.Failure.protected("Downloads")) {
            try FileOperations.setHidden(true, paths: [downloads], homeDirectory: home)
        }
        #expect(isHidden(downloads) == false)
    }

    @Test func makeExecutableAddsRunPermissionWhereReadingIsAllowed() throws {
        let script = try box.file("run.sh", permissions: 0o640)
        try FileOperations.makeExecutable([script])
        #expect(box.permissions("run.sh") == 0o750)
    }

    @Test func makeExecutableFollowsLinksToTheRealFile() throws {
        try box.file("real.sh", permissions: 0o644)
        try FileManager.default.createSymbolicLink(atPath: box.path("link.sh"), withDestinationPath: box.path("real.sh"))
        try FileOperations.makeExecutable([box.path("link.sh")])
        #expect(box.permissions("real.sh") == 0o755)
    }

    @Test func deletesFilesAndFolders() throws {
        let file = try box.file("notes.txt")
        let folder = try box.folder("Project")
        try box.file("Project/a.txt")
        try FileOperations.deletePermanently([file, folder], homeDirectory: home)
        #expect(box.names().isEmpty)
    }

    @Test func refusesToDeleteProtectedFoldersAndDeletesNothingElse() throws {
        let file = try box.file("notes.txt")
        let desktop = try box.folder("Home/Desktop")
        #expect(throws: FileOperations.Failure.protected("Desktop")) {
            try FileOperations.deletePermanently([file, desktop], homeDirectory: home)
        }
        #expect(box.exists("notes.txt"))
    }

    @Test func protectedFoldersAreRecognisedByAnyPathThatLeadsToThem() throws {
        let documents = try box.folder("Home/Documents")
        // The same folder as the system also names it, and reached through a linked parent folder.
        let real = try #require(try URL(fileURLWithPath: documents).resourceValues(forKeys: [.canonicalPathKey]).canonicalPath)
        let dataVolumeForm = "/System/Volumes/Data" + real
        try #require(FileManager.default.fileExists(atPath: dataVolumeForm))
        try FileManager.default.createSymbolicLink(atPath: box.path("HomeLink"), withDestinationPath: home)
        try FileManager.default.createSymbolicLink(atPath: box.path("shortcut"), withDestinationPath: documents)

        for path in [dataVolumeForm, box.path("HomeLink/Documents"), documents + "/"] {
            #expect(throws: FileOperations.Failure.protected("Documents"), "\(path)") {
                try FileOperations.ensureUnprotected([path], homeDirectory: home)
            }
        }
        // A link to a protected folder is only a link; removing it leaves the folder alone.
        #expect(throws: Never.self) {
            try FileOperations.ensureUnprotected([box.path("shortcut")], homeDirectory: home)
        }
        #expect(throws: Never.self) {
            try FileOperations.ensureUnprotected([try box.file("Home/Documents/report.txt")], homeDirectory: home)
        }
    }

    @Test func nothingIsDeletedWhenSomethingInsideIsLocked() throws {
        let folder = try box.folder("Project")
        try box.file("Project/a.txt")
        try box.file("Project/Deep/locked.txt")
        box.setLocked(true, box.path("Project/Deep/locked.txt"))
        let plain = try box.file("notes.txt")

        #expect(throws: FileOperations.Failure.locked("locked.txt")) {
            try FileOperations.deletePermanently([plain, folder], homeDirectory: home)
        }
        #expect(box.exists("notes.txt"))
        #expect(box.exists("Project/a.txt"))
    }

    @Test func cancelledDeletionStopsBeforeTheNextItem() throws {
        let file = try box.file("notes.txt")
        let control = OperationControl()
        control.cancel()
        #expect(throws: CancellationError.self) {
            try FileOperations.deletePermanently([file], homeDirectory: home, control: control)
        }
        #expect(box.exists("notes.txt"))
    }

    @Test func readsTextFilesJoinedByBlankLines() throws {
        let first = try box.file("a.txt", "one")
        let second = try box.file("b.txt", "two")
        #expect(try FileOperations.readText([first, second]) == "one\n\ntwo")
    }

    @Test func refusesBinaryAndOversizedFiles() throws {
        let binary = try box.file("image.bin", data: Data([0x89, 0x50, 0x00, 0x01]))
        #expect(throws: FileOperations.Failure.notText("image.bin")) { try FileOperations.readText([binary]) }
        let large = try box.file("large.txt", String(repeating: "a", count: 200))
        #expect(throws: FileOperations.Failure.tooLarge("large.txt")) { try FileOperations.readText([large], limit: 100) }
    }

    @Test func packagesCountAsFiles() throws {
        #expect(FileOperations.isFolder(try box.folder("Project")))
        #expect(!FileOperations.isFolder(try box.folder("Tool.app")))
        #expect(!FileOperations.isFolder(try box.file("notes.txt")))
        #expect(!FileOperations.isFolder(box.path("missing")))
    }

    @Test func ordinaryFoldersAreNotCloudSynced() throws {
        #expect(!CloudFolders.isSynced(try box.folder("Project")))
        #expect(!CloudFolders.isSynced(box.path("missing")))
    }
}

@Suite("Templates")
struct TemplateWriterTests {
    private let box: Sandbox

    init() throws {
        box = try Sandbox()
    }

    private func template(_ source: FileTemplate.Source, executable: Bool = false) -> FileTemplate {
        FileTemplate(id: "test", name: "Test", fileExtension: "txt", source: source, makesExecutable: executable)
    }

    @Test func writesTextTemplates() throws {
        let destination = box.root.appendingPathComponent("Untitled.txt")
        try TemplateWriter.write(template(.text(content: "hello")), to: destination, bundledTemplates: nil)
        #expect(box.text("Untitled.txt") == "hello")
    }

    @Test func neverOverwritesAnExistingFile() throws {
        try box.file("Untitled.txt", "mine")
        let destination = box.root.appendingPathComponent("Untitled.txt")
        #expect(throws: (any Error).self) {
            try TemplateWriter.write(template(.text(content: "new")), to: destination, bundledTemplates: nil)
        }
        #expect(box.text("Untitled.txt") == "mine")
    }

    @Test func scriptsCanRunStraightAway() throws {
        let destination = box.root.appendingPathComponent("run.sh")
        try TemplateWriter.write(template(.text(content: "#!/bin/sh\n"), executable: true), to: destination,
                                 bundledTemplates: nil)
        #expect(box.permissions("run.sh") == 0o755)
    }

    @Test func copiesBundledTemplates() throws {
        try box.file("Bundle/Blank.docx", "docx-bytes")
        let bundle = box.root.appendingPathComponent("Bundle")
        let destination = box.root.appendingPathComponent("New.docx")
        try TemplateWriter.write(template(.bundled(resource: "Blank.docx")), to: destination, bundledTemplates: bundle)
        #expect(box.text("New.docx") == "docx-bytes")

        #expect(throws: TemplateWriter.Failure.missingResource("Gone.docx")) {
            try TemplateWriter.write(template(.bundled(resource: "Gone.docx")),
                                     to: box.root.appendingPathComponent("x.docx"), bundledTemplates: bundle)
        }
    }

    @Test func importsAFileAsATemplateAndRemovesItAgain() throws {
        let source = URL(fileURLWithPath: try box.file("Invoice Draft.pages", "pages-bytes"))
        let library = box.root.appendingPathComponent("Templates", isDirectory: true)

        let imported = try TemplateWriter.importTemplate(from: source, into: library)
        #expect(imported.name == "Invoice Draft")
        #expect(imported.fileExtension == "pages")
        guard case .file(let stored) = imported.source else {
            Issue.record("Expected a stored file")
            return
        }
        #expect(stored.hasPrefix(library.path + "/"))
        #expect(try String(contentsOfFile: stored, encoding: .utf8) == "pages-bytes")

        let destination = box.root.appendingPathComponent("New.pages")
        try TemplateWriter.write(imported, to: destination, bundledTemplates: nil)
        #expect(box.text("New.pages") == "pages-bytes")

        TemplateWriter.removeStoredFile(of: imported, in: library)
        #expect(!FileManager.default.fileExists(atPath: stored))
    }

    @Test func removingNeverTouchesFilesOutsideTheLibrary() throws {
        let outside = try box.file("precious.txt")
        let library = box.root.appendingPathComponent("Templates", isDirectory: true)
        TemplateWriter.removeStoredFile(of: template(.file(path: outside)), in: library)
        TemplateWriter.removeStoredFile(of: template(.file(path: library.path)), in: library)
        #expect(box.exists("precious.txt"))
    }
}
