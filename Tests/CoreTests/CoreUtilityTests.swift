import Foundation
@testable import RightShortcutsCore
import Testing

@Suite("Path formatting")
struct CopyFormatTests {
    private let home = "/Users/me"
    private let paths = ["/Users/me/My Docs/it's.txt", "/Users/me/archive.tar.gz"]

    @Test func formats() {
        #expect(CopyFormat.fullPath.string(for: paths, homeDirectory: home)
            == "/Users/me/My Docs/it's.txt\n/Users/me/archive.tar.gz")
        #expect(CopyFormat.tildePath.string(for: paths, homeDirectory: home)
            == "~/My Docs/it's.txt\n~/archive.tar.gz")
        #expect(CopyFormat.name.string(for: paths, homeDirectory: home) == "it's.txt\narchive.tar.gz")
        #expect(CopyFormat.nameWithoutExtension.string(for: paths, homeDirectory: home) == "it's\narchive.tar")
        #expect(CopyFormat.parentPath.string(for: paths, homeDirectory: home) == "/Users/me/My Docs\n/Users/me")
        #expect(CopyFormat.shellQuoted.string(for: paths, homeDirectory: home)
            == #"'/Users/me/My Docs/it'\''s.txt' '/Users/me/archive.tar.gz'"#)
        #expect(CopyFormat.fileURL.string(for: [paths[0]], homeDirectory: home)
            == "file:///Users/me/My%20Docs/it's.txt")
    }

    @Test func tildeOnlyReplacesWholeHomeFolder() {
        #expect(CopyFormat.tildePath.string(for: ["/Users/me"], homeDirectory: home) == "~")
        #expect(CopyFormat.tildePath.string(for: ["/Users/meg/file"], homeDirectory: home) == "/Users/meg/file")
    }
}

@Suite("Path matching")
struct PathMatchingTests {
    @Test func insideChecksWholeComponents() {
        #expect(PathMatching.isPath("/Users/me/Docs", inside: "/Users/me"))
        #expect(PathMatching.isPath("/Users/me", inside: "/Users/me/"))
        #expect(!PathMatching.isPath("/Users/meg", inside: "/Users/me"))
        #expect(PathMatching.isPath("/Volumes/Drive", inside: "/"))
    }
}

@Suite("Path safety")
struct PathSafetyTests {
    private let home = "/Users/me"

    @Test func protectsSystemAndHomeFolders() {
        for path in ["/", "/Applications", "/Users", "/System", "/Volumes/Backup", "/Users/me", "/Users/me/",
                     "/Users/me/Documents", "/Users/me/Desktop", "/Users/me/Library", "/Users/me/Docs/../Downloads"] {
            #expect(PathSafety.isProtected(path, homeDirectory: home), "\(path) should be protected")
        }
    }

    @Test func allowsEverydayItems() {
        for path in ["/Users/me/Documents/report.pdf", "/Users/me/Projects", "/Users/me/.zshrc",
                     "/Volumes/Backup/Photos", "/Applications/Some.app/Contents"] {
            #expect(!PathSafety.isProtected(path, homeDirectory: home), "\(path) should be allowed")
        }
    }
}

@Suite("File naming")
struct FileNamingTests {
    private let folder = URL(fileURLWithPath: "/tmp/test", isDirectory: true)

    @Test func picksTheNextFreeName() {
        let taken: Set<String> = ["Untitled.txt", "Untitled 2.txt"]
        let url = FileNaming.availableURL(in: folder, name: "Untitled.txt") { taken.contains($0.lastPathComponent) }
        #expect(url.lastPathComponent == "Untitled 3.txt")
    }

    @Test func keepsTheNameWhenFree() {
        let url = FileNaming.availableURL(in: folder, name: "notes.md") { _ in false }
        #expect(url.lastPathComponent == "notes.md")
    }

    @Test func handlesFoldersAndDotFiles() {
        let folderURL = FileNaming.availableURL(in: folder, name: "v1.2", isDirectory: true) { $0.lastPathComponent == "v1.2" }
        #expect(folderURL.lastPathComponent == "v1.2 2")
        let dotFile = FileNaming.availableURL(in: folder, name: ".gitignore") { $0.lastPathComponent == ".gitignore" }
        #expect(dotFile.lastPathComponent == ".gitignore 2")
    }

    @Test func aBrokenLinkStillTakesItsName() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RightShortcutsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // The link points nowhere, but its name is taken all the same.
        try FileManager.default.createSymbolicLink(atPath: directory.appendingPathComponent("notes.txt").path,
                                                   withDestinationPath: "/nowhere/at/all")
        #expect(FileNaming.availableURL(in: directory, name: "notes.txt").lastPathComponent == "notes 2.txt")
    }

    @Test func candidateNamesCountUpAndKeepTheExtension() {
        #expect((1...3).map { FileNaming.candidateName("report.tar.gz", isDirectory: false, attempt: $0) }
            == ["report.tar.gz", "report.tar 2.gz", "report.tar 3.gz"])
        #expect((1...2).map { FileNaming.candidateName("v1.2", isDirectory: true, attempt: $0) } == ["v1.2", "v1.2 2"])
    }

    @Test func validatesNames() {
        #expect(FileNaming.problem(with: "  ") != nil)
        #expect(FileNaming.problem(with: "a/b") != nil)
        #expect(FileNaming.problem(with: "a:b") != nil)
        #expect(FileNaming.problem(with: "..") != nil)
        #expect(FileNaming.problem(with: "Report 2026.md") == nil)
    }

    @Test func shellQuoting() {
        #expect(ShellQuoting.quote("plain") == "'plain'")
        #expect(ShellQuoting.quote("it's") == #"'it'\''s'"#)
    }
}

@Suite("Action requests")
struct ActionRequestTests {
    private let target = ActionTarget(itemID: UUID())

    @Test func backgroundClicksIgnoreStaleSelection() {
        let request = ActionRequest(target: target, location: .container, targetPath: "/Docs",
                                    selectedPaths: ["/Docs/old.txt"])
        #expect(request.selection.isEmpty)
        #expect(request.operandPaths == ["/Docs"])
        #expect(request.workingDirectory { _ in true } == "/Docs")
    }

    @Test func workingDirectoryRules() {
        let folder = ActionRequest(target: target, location: .items, targetPath: "/Docs", selectedPaths: ["/Docs/Sub"])
        #expect(folder.workingDirectory { _ in true } == "/Docs/Sub")

        let file = ActionRequest(target: target, location: .items, targetPath: "/Docs", selectedPaths: ["/Docs/a.txt"])
        #expect(file.workingDirectory { _ in false } == "/Docs")

        let several = ActionRequest(target: target, location: .items, targetPath: "/Docs",
                                    selectedPaths: ["/Docs/A", "/Docs/B"])
        #expect(several.workingDirectory { _ in true } == "/Docs")
    }

    @Test func roundTripsThroughJSON() throws {
        let request = ActionRequest(target: ActionTarget(itemID: UUID(), option: "fullPath"), location: .toolbar,
                                    targetPath: "/Docs", selectedPaths: ["/Docs/a"])
        let decoded = try JSONDecoder().decode(ActionRequest.self, from: JSONEncoder().encode(request))
        #expect(decoded.id == request.id)
        #expect(decoded.target == request.target)
        #expect(decoded.location == .toolbar)
        #expect(decoded.selectedPaths == ["/Docs/a"])
    }
}

@Suite("Configuration")
struct AppConfigTests {
    @Test func defaultConfigurationHasTheEssentials() {
        let app = OpenWithApp(appPath: "/System/Applications/Utilities/Terminal.app", appName: "Terminal",
                              bundleID: "com.apple.Terminal")
        let config = AppConfig.makeDefault(homeDirectory: "/Users/me", apps: [app])
        let actions = config.items.compactMap(\.builtinAction)
        #expect(Set(actions) == Set(BuiltinAction.allCases))
        #expect(config.items.contains { if case .openWith = $0.kind { true } else { false } })
        #expect(config.quickFolders.map(\.path) == ["/Users/me/Desktop", "/Users/me/Documents", "/Users/me/Downloads"])
        #expect(config.reconciled() == config)
    }

    @Test func roundTripsThroughJSON() throws {
        let config = AppConfig.makeDefault(homeDirectory: "/Users/me", apps: [])
        let decoded = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded == config)
    }

    @Test func toleratesMissingKeysAndUnknownItems() throws {
        let json = """
        {
          "menuLayout": "somethingNew",
          "items": [
            { "id": "\(UUID().uuidString)", "kind": { "builtin": { "action": "copyPath" } },
              "isEnabled": true, "contexts": ["files"], "fileExtensions": [] },
            { "id": "\(UUID().uuidString)", "kind": { "builtin": { "action": "teleport" } },
              "isEnabled": true, "contexts": ["files"], "fileExtensions": [] }
          ]
        }
        """
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(config.menuLayout == .submenu)
        #expect(config.items.count == 1)
        #expect(config.templates == FileTemplate.builtins)
        #expect(config.askForFileName)
    }

    @Test func reconcileAddsNewBuiltinsSwitchedOff() {
        var config = AppConfig()
        config.items = [.builtin(.copyPath)]
        config.templates = []
        let reconciled = config.reconciled()
        #expect(reconciled.items.count == BuiltinAction.allCases.count)
        #expect(reconciled.items.dropFirst().allSatisfy { !$0.isEnabled })
        #expect(reconciled.templates.count == FileTemplate.builtins.count)
        #expect(reconciled.templates.allSatisfy { !$0.isEnabled })
    }
}
