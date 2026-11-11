import Foundation
@testable import RightShortcutsActions
import RightShortcutsCore
import Testing

/// Runs a composed line the way the helper script does: with /bin/sh.
private func shell(_ line: String) throws -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", line]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

@Suite("Custom commands")
struct CommandComposerTests {
    private let box: Sandbox
    private let trickyPaths: [String]

    init() throws {
        box = try Sandbox()
        trickyPaths = [try box.file("it's here.txt"), try box.file("two  spaces & $HOME.txt")]
    }

    private func command(_ script: String, mode: RunMode = .background) -> CustomCommand {
        CustomCommand(name: "Test", script: script, runMode: mode)
    }

    @Test func backgroundCommandsGetThePathsExactly() throws {
        let line = CommandComposer.backgroundLine(command(#"printf '<%s>' "$@""#), paths: trickyPaths,
                                                  directory: box.root.path, targetPath: box.root.path)
        let result = try shell(line)
        #expect(result.status == 0)
        #expect(result.output.hasSuffix("<\(trickyPaths[0])><\(trickyPaths[1])>"))
    }

    @Test func backgroundCommandsRunInTheFolderWithTheVariablesSet() throws {
        let script = #"printf 'dir=%s|pwd=%s|target=%s|paths=%s' "$RS_DIR" "$PWD" "$RS_TARGET" "$RS_PATHS""#
        let line = CommandComposer.backgroundLine(command(script), paths: trickyPaths, directory: box.root.path,
                                                  targetPath: trickyPaths[0])
        let output = try shell(line).output
        let expected = "dir=\(box.root.path)|pwd=\(box.root.path)|target=\(trickyPaths[0])|paths=\(trickyPaths.joined(separator: "\n"))"
        #expect(output.hasSuffix(expected))
    }

    @Test func aFailingCommandReportsItsStatusAndErrorText() throws {
        let line = CommandComposer.backgroundLine(command("echo broken >&2; exit 7"), paths: [], directory: nil, targetPath: nil)
        let result = try shell(line)
        #expect(result.status == 7)
        #expect(result.output.contains("broken"))
    }

    @Test func aMissingFolderStopsTheCommand() throws {
        let line = CommandComposer.backgroundLine(command("echo should-not-run"), paths: [], directory: box.path("gone"),
                                                  targetPath: nil)
        let result = try shell(line)
        #expect(result.status != 0)
        #expect(!result.output.contains("should-not-run"))
    }

    @Test func terminalCommandsRunFromAThrowawayFileThatRemovesItself() throws {
        let marker = box.path("ran.txt")
        let script = #"printf '%s|%s|%s' "$PWD" "$1" "$RS_DIR" > "$MARKER"; printf '%s' "$0" > "$MARKER.self""#
        // "env MARKER=… /bin/zsh" stands in for Terminal, which would run the file the same way.
        let line = CommandComposer.terminalLine(command(script, mode: .terminal), paths: trickyPaths,
                                                directory: box.root.path, targetPath: nil,
                                                opener: "/usr/bin/env MARKER=\(ShellQuoting.quote(marker)) /bin/zsh")
        let result = try shell(line)
        #expect(result.status == 0, "\(result.output)")
        #expect(box.text("ran.txt") == "\(box.root.path)|\(trickyPaths[0])|\(box.root.path)")

        let scriptFile = try #require(box.text("ran.txt.self"))
        #expect(scriptFile.hasSuffix(".command"))
        #expect(!FileManager.default.fileExists(atPath: scriptFile), "the script removes itself")
        #expect(!FileManager.default.fileExists(atPath: (scriptFile as NSString).deletingLastPathComponent))
    }

    @Test func failuresNameTheCommandAndQuoteItsLastLine() {
        let failure = CommandComposer.Failure.failed(name: "Convert", status: 3, output: "step one\nno such file\n")
        #expect(failure.errorDescription == "Convert failed: no such file")
        let silent = CommandComposer.Failure.failed(name: "Convert", status: 3, output: "")
        #expect(silent.errorDescription == "Convert failed: exit code 3")
    }
}

@Suite("Command helper")
struct HelperScriptTests {
    private let box: Sandbox
    private let helper: HelperScript

    init() throws {
        box = try Sandbox()
        helper = HelperScript(bundled: URL(fileURLWithPath: try box.file("Bundle/Helper.scpt", "version 2")),
                              installed: box.root.appendingPathComponent("Scripts/Helper.scpt"))
    }

    @Test func startsOutMissing() {
        #expect(helper.state == .missing)
    }

    @Test func installingCopiesTheScript() throws {
        try helper.install()
        #expect(helper.state == .installed)
        #expect(box.text("Scripts/Helper.scpt") == "version 2")
    }

    @Test func anOlderCopyIsOutdatedAndGetsReplaced() throws {
        try box.file("Scripts/Helper.scpt", "version 1")
        #expect(helper.state == .outdated)
        try helper.install()
        #expect(helper.state == .installed)
        #expect(box.text("Scripts/Helper.scpt") == "version 2")
    }
}

@Suite("Folder permissions")
struct FolderGrantsTests {
    private let box: Sandbox
    private let suite = "RightShortcutsTests-\(UUID().uuidString)"
    private var defaults: UserDefaults { UserDefaults(suiteName: suite)! }

    init() throws {
        box = try Sandbox()
    }

    private func cleanUp() {
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func remembersAllowedFolders() throws {
        defer { cleanUp() }
        let projects = try box.folder("Projects")
        let grants = FolderGrants(defaults: defaults)
        #expect(grants.folders.isEmpty)

        try grants.add(URL(fileURLWithPath: projects, isDirectory: true))
        #expect(grants.folders == [projects])
        #expect(grants.covers(projects + "/app/main.swift"))
        #expect(!grants.covers(box.path("Elsewhere")))

        let reloaded = FolderGrants(defaults: defaults)
        #expect(reloaded.folders == [projects], "permissions survive a restart")
    }

    @Test func aWiderFolderReplacesTheOnesInsideIt() throws {
        defer { cleanUp() }
        let inner = try box.folder("Projects/App")
        let outer = box.path("Projects")
        let grants = FolderGrants(defaults: defaults)
        try grants.add(URL(fileURLWithPath: inner, isDirectory: true))
        try grants.add(URL(fileURLWithPath: outer, isDirectory: true))
        #expect(grants.folders == [outer])

        try grants.add(URL(fileURLWithPath: inner, isDirectory: true))
        #expect(grants.folders == [outer], "already covered, nothing to add")
    }

    @Test func removingAFolderForgetsIt() throws {
        defer { cleanUp() }
        let projects = try box.folder("Projects")
        let grants = FolderGrants(defaults: defaults)
        try grants.add(URL(fileURLWithPath: projects, isDirectory: true))
        grants.remove(projects)
        #expect(grants.folders.isEmpty)
        #expect(FolderGrants(defaults: defaults).folders.isEmpty)
    }

    @Test func aFolderThatWentAwayIsKeptButNotUsable() throws {
        defer { cleanUp() }
        let drive = try box.folder("Drive")
        let grants = FolderGrants(defaults: defaults)
        try grants.add(URL(fileURLWithPath: drive, isDirectory: true))
        try FileManager.default.removeItem(atPath: drive)

        let later = FolderGrants(defaults: defaults)
        #expect(later.folders == [drive], "still listed, so it works again when the drive returns")
        #expect(later.unavailableFolders == [drive])
        #expect(!later.covers(drive + "/file.txt"))

        try box.folder("Drive")
        later.refresh()
        #expect(later.unavailableFolders.isEmpty)
        #expect(later.covers(drive + "/file.txt"))
    }
}
