import Foundation
@testable import RightShortcutsCore
import Testing

@Suite("Host access")
struct HostAccessTests {
    private let config = AppConfig.makeDefault(homeDirectory: "/Users/me", apps: [])
    private let home = HostAccess(folders: ["/Users/me"], canRunCommands: false)

    private func request(
        _ action: BuiltinAction,
        option: String? = nil,
        location: MenuLocation = .items,
        target: String? = "/Users/me/Docs",
        selected: [String] = ["/Users/me/Docs/a.txt"]
    ) -> ActionRequest {
        let item = config.items.first { $0.builtinAction == action }!
        return ActionRequest(target: ActionTarget(itemID: item.id, option: option), location: location,
                             targetPath: target, selectedPaths: selected)
    }

    private func needed(_ request: ActionRequest, folders: Set<String> = []) -> [String] {
        config.pathsNeedingAccess(for: request) { folders.contains($0) }
    }

    @Test func coversAFolderAndEverythingInside() {
        #expect(home.covers("/Users/me"))
        #expect(home.covers("/Users/me/Docs/a.txt"))
        #expect(!home.covers("/Users/meg/a.txt"))
        #expect(!HostAccess().covers("/Users/me"))
        #expect(HostAccess(folders: ["/"]).covers("/Volumes/Drive/x"))
    }

    @Test func copyingPathsNeedsNoAccess() {
        for action in [BuiltinAction.copyPath, .copyName, .copyPathAs] {
            #expect(needed(request(action)).isEmpty, "\(action) should need no access")
        }
    }

    @Test func newFileNeedsTheFolderItCreatesIn() {
        #expect(needed(request(.newFile, location: .container, selected: [])) == ["/Users/me/Docs"])
        #expect(needed(request(.newFile, selected: ["/Users/me/Docs/Sub"]), folders: ["/Users/me/Docs/Sub"])
            == ["/Users/me/Docs/Sub"])
        #expect(needed(request(.newFile, selected: ["/Users/me/Docs/a.txt"])) == ["/Users/me/Docs"])
    }

    @Test func changingAnItemNeedsThatItem() {
        for action in [BuiltinAction.hide, .unhide, .makeExecutable, .copyContents, .airDrop] {
            #expect(needed(request(action)) == ["/Users/me/Docs/a.txt"], "\(action)")
        }
    }

    @Test func copyNeedsTheItemsAndTheDestination() {
        let documents = config.quickFolders[1]
        #expect(needed(request(.copyTo, option: documents.id.uuidString)) == ["/Users/me/Docs/a.txt", documents.path])
        // The folder picker grants the destination itself.
        #expect(needed(request(.copyTo, option: ActionTarget.chooseFolderOption)) == ["/Users/me/Docs/a.txt"])
    }

    @Test func moveAndDeleteNeedTheEnclosingFolder() {
        let downloads = config.quickFolders[2]
        #expect(needed(request(.moveTo, option: downloads.id.uuidString)) == ["/Users/me/Docs", downloads.path])
        #expect(needed(request(.deletePermanently, selected: ["/Users/me/Docs/a.txt", "/Users/me/Docs/b.txt"]))
            == ["/Users/me/Docs"])
    }

    @Test func goToNeedsTheFolderItOpens() {
        let downloads = config.quickFolders[2]
        #expect(needed(request(.goTo, option: downloads.id.uuidString, location: .container, selected: [])) == [downloads.path])
        #expect(needed(request(.goTo, option: UUID().uuidString)).isEmpty, "a removed quick folder opens nothing")
    }

    @Test func openingNeedsExactlyWhatGetsOpened() {
        var config = config
        let editor = MenuItem(kind: .openWith(app: OpenWithApp(appPath: "/Applications/Zed.app", appName: "Zed", bundleID: "dev.zed.Zed")))
        let terminal = MenuItem(kind: .openWith(app: OpenWithApp(appPath: "/System/Applications/Utilities/Terminal.app",
                                                                 appName: "Terminal", bundleID: "com.apple.Terminal")))
        config.items += [editor, terminal]
        func click(_ item: MenuItem, location: MenuLocation = .items, selected: [String]) -> [String] {
            let request = ActionRequest(target: ActionTarget(itemID: item.id), location: location,
                                        targetPath: "/Users/me/Docs", selectedPaths: selected)
            return config.pathsNeedingAccess(for: request) { $0.hasSuffix("/Sub") }
        }
        // An editor gets the items; a terminal gets the folder they are in.
        #expect(click(editor, selected: ["/Users/me/Docs/a.txt"]) == ["/Users/me/Docs/a.txt"])
        #expect(click(terminal, selected: ["/Users/me/Docs/a.txt"]) == ["/Users/me/Docs"])
        #expect(click(terminal, selected: ["/Users/me/Docs/Sub"]) == ["/Users/me/Docs/Sub"])
        #expect(click(terminal, location: .container, selected: []) == ["/Users/me/Docs"])
        #expect(config.needsActivation(
            ActionRequest(target: ActionTarget(itemID: terminal.id), location: .container, targetPath: "/Users/me/Docs", selectedPaths: []),
            access: HostAccess()
        ) { _ in false })
    }

    @Test func actionsOnSelectionIgnoreTheFolderBehindABackgroundClick() {
        #expect(needed(request(.deletePermanently, location: .container, selected: [])).isEmpty)
    }

    @Test func activationForSystemWindows() {
        let everything = HostAccess(folders: ["/"], canRunCommands: true)
        func activates(_ request: ActionRequest) -> Bool {
            config.needsActivation(request, access: everything) { _ in false }
        }
        #expect(activates(request(.airDrop)))
        #expect(activates(request(.moveTo, option: ActionTarget.chooseFolderOption)))
        #expect(!activates(request(.moveTo, option: config.quickFolders[0].id.uuidString)))
        #expect(!activates(request(.deletePermanently)))
        #expect(!activates(request(.newFile, option: "builtin.text")))
        #expect(!activates(request(.copyPath)))
    }

    @Test func activationWhenAccessIsMissing() {
        func activates(_ request: ActionRequest, _ access: HostAccess) -> Bool {
            config.needsActivation(request, access: access) { _ in false }
        }
        #expect(activates(request(.hide), HostAccess()))
        #expect(!activates(request(.hide), home))
        #expect(activates(request(.hide, selected: ["/Volumes/Drive/a.txt"]), home))
        // Copying a path never touches the file, so it never asks.
        #expect(!activates(request(.copyPath), HostAccess()))
    }

    @Test func commandsNeedTheHelperNotFolderAccess() {
        let command = config.items.first { if case .command = $0.kind { true } else { false } }!
        let click = ActionRequest(target: ActionTarget(itemID: command.id), location: .items,
                                  targetPath: "/Users/me/Docs", selectedPaths: ["/Users/me/Docs/a.txt"])
        #expect(config.pathsNeedingAccess(for: click) { _ in false }.isEmpty)
        #expect(config.needsActivation(click, access: HostAccess()) { _ in false })
        #expect(!config.needsActivation(click, access: HostAccess(canRunCommands: true)) { _ in false })
    }

    @Test func removedItemsNeverActivate() {
        let click = ActionRequest(target: ActionTarget(itemID: UUID()), location: .items, targetPath: "/x",
                                  selectedPaths: ["/x/a"])
        #expect(!config.needsActivation(click, access: HostAccess()) { _ in false })
    }

    @Test func operandsFollowWhatTheActionWorksOn() {
        let background = request(.copyPath, location: .container, selected: ["/Users/me/Docs/stale.txt"])
        #expect(background.operands(for: .copyPath) == ["/Users/me/Docs"])
        #expect(background.operands(for: .deletePermanently).isEmpty)
        #expect(request(.hide).operands(for: .hide) == ["/Users/me/Docs/a.txt"])
    }

    @Test func insideAnyFolder() {
        #expect(PathMatching.isPath("/Users/me/Docs/a", insideAny: ["/Volumes/Drive", "/Users/me"]))
        #expect(!PathMatching.isPath("/Users/me/Docs/a", insideAny: []))
    }

    @Test func terminalsAreRecognised() {
        #expect(KnownApps.isTerminal(bundleID: "com.apple.Terminal"))
        #expect(!KnownApps.isTerminal(bundleID: "com.microsoft.VSCode"))
        #expect(!KnownApps.isTerminal(bundleID: nil))
        #expect(OpenWithApp(appPath: "/x", appName: "X", bundleID: "com.googlecode.iterm2").opensFolder)
        #expect(!OpenWithApp(appPath: "/x", appName: "X", bundleID: "com.googlecode.iterm2", target: .items).opensFolder)
        #expect(OpenWithApp(appPath: "/x", appName: "X", bundleID: "dev.zed.Zed", target: .folder).opensFolder)
    }

    @Test func commonAncestor() {
        #expect(PathMatching.commonAncestor(of: ["/Users/me/Docs/a", "/Users/me/Downloads"]) == "/Users/me")
        #expect(PathMatching.commonAncestor(of: ["/Users/me/Docs"]) == "/Users/me/Docs")
        #expect(PathMatching.commonAncestor(of: ["/Users/me", "/Volumes/Drive"]) == "/")
        #expect(PathMatching.commonAncestor(of: ["/Users/me/Docs", "/Users/me/Docs/Sub/x"]) == "/Users/me/Docs")
        #expect(PathMatching.commonAncestor(of: ["/Users/me", "/Users/meg"]) == "/Users")
        #expect(PathMatching.commonAncestor(of: []) == nil)
    }
}

@Suite("Shared files")
struct SharedFileTests {
    private struct Sample: Codable, Equatable, Sendable {
        var name: String
    }

    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("RightShortcutsTests-\(UUID().uuidString)", isDirectory: true)

    private var file: SharedFile<Sample> {
        SharedFile(url: directory.appendingPathComponent("sample.json"))
    }

    @Test func missingFileReadsAsNone() {
        guard case .none = file.read() else {
            Issue.record("Expected .none")
            return
        }
        #expect(file.load() == nil)
        #expect(file.modificationDate() == nil)
    }

    @Test func savesAndLoads() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try file.save(Sample(name: "one"))
        #expect(file.load() == Sample(name: "one"))
        #expect(file.modificationDate() != nil)
    }

    @Test func unreadableFileIsDamagedAndCanBeSetAside() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: file.url)
        guard case .damaged = file.read() else {
            Issue.record("Expected .damaged")
            return
        }

        let backup = try file.backUp(label: "damaged", removingOriginal: true)
        #expect(backup.lastPathComponent.hasPrefix("sample.damaged-"))
        #expect(backup.pathExtension == "json")
        #expect(try Data(contentsOf: backup) == Data("{ not json".utf8))
        #expect(!FileManager.default.fileExists(atPath: file.url.path))
    }

    @Test func backupCanKeepTheOriginal() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try file.save(Sample(name: "kept"))
        let backup = try file.backUp(label: "newer", removingOriginal: false)
        #expect(FileManager.default.fileExists(atPath: backup.path))
        #expect(file.load() == Sample(name: "kept"))
    }
}

@Suite("Settings version")
struct SchemaVersionTests {
    @Test func filesWithoutAVersionAreVersionOne() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data("{}".utf8))
        #expect(config.schemaVersion == 1)
        #expect(!config.isFromNewerVersion)
    }

    @Test func theVersionIsWritten() throws {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppConfig())) as? [String: Any]
        #expect(object?["schemaVersion"] as? Int == AppConfig.currentSchemaVersion)
    }

    @Test func filesFromANewerVersionAreRecognised() throws {
        let json = #"{ "schemaVersion": \#(AppConfig.currentSchemaVersion + 1), "futureSetting": true }"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(config.isFromNewerVersion)
    }
}

@Suite("Home folder")
struct UserHomeTests {
    @Test func abbreviatesOnlyTheWholeHomeFolder() {
        #expect(UserHome.abbreviate("/Users/me/Docs/a.txt", home: "/Users/me") == "~/Docs/a.txt")
        #expect(UserHome.abbreviate("/Users/me", home: "/Users/me") == "~")
        #expect(UserHome.abbreviate("/Users/meg/a", home: "/Users/me") == "/Users/meg/a")
        #expect(UserHome.abbreviate("/Volumes/Drive", home: "/Users/me/") == "/Volumes/Drive")
    }

    @Test func pointsAtTheRealHomeFolder() {
        #expect(UserHome.path.hasPrefix("/"))
        #expect(!UserHome.path.contains("/Library/Containers/"))
    }
}
