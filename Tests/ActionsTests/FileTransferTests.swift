import Foundation
@testable import RightShortcutsActions
import Testing

@Suite("Copy and move")
struct FileTransferTests {
    private let box: Sandbox
    private let destination: String

    init() throws {
        box = try Sandbox()
        destination = try box.folder("Destination")
    }

    private func transfer(_ paths: [String], move: Bool = false, control: OperationControl = OperationControl(),
                          progress: @escaping (TransferProgress) -> Void = { _ in }) throws -> Int {
        try FileTransfer.run(paths, to: destination, move: move, homeDirectory: box.path("Home"),
                             control: control, progress: progress)
    }

    @Test func copiesFilesAndWholeFolders() throws {
        let file = try box.file("Source/notes.txt", "hello")
        let folder = try box.folder("Source/Project")
        try box.file("Source/Project/a.txt", "A")
        try box.file("Source/Project/Deep/b.txt", "B")
        try box.file("Source/Project/run.sh", "#!/bin/sh\n", permissions: 0o755)
        try FileManager.default.createSymbolicLink(atPath: box.path("Source/Project/link"), withDestinationPath: "a.txt")

        #expect(try transfer([file, folder]) == 2)

        #expect(box.text("Destination/notes.txt") == "hello")
        #expect(box.text("Destination/Project/a.txt") == "A")
        #expect(box.text("Destination/Project/Deep/b.txt") == "B")
        #expect(box.permissions("Destination/Project/run.sh") == 0o755)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: box.path("Destination/Project/link")) == "a.txt")
        #expect(box.exists("Source/notes.txt"), "copying leaves the original")
    }

    @Test func neverOverwrites() throws {
        try box.file("Destination/notes.txt", "old")
        try box.folder("Destination/Photos")
        try box.folder("Destination/Tool.app")
        let file = try box.file("Source/notes.txt", "new")
        let folder = try box.folder("Source/Photos")
        let package = try box.folder("Source/Tool.app")

        #expect(try transfer([file, folder, package]) == 3)

        #expect(box.text("Destination/notes.txt") == "old")
        #expect(box.text("Destination/notes 2.txt") == "new")
        #expect(box.names("Destination") == ["Photos", "Photos 2", "Tool 2.app", "Tool.app", "notes 2.txt", "notes.txt"])
    }

    @Test func itemsWithTheSameNameBothArrive() throws {
        let first = try box.file("One/report.txt", "1")
        let second = try box.file("Two/report.txt", "2")
        #expect(try transfer([first, second]) == 2)
        #expect(box.text("Destination/report.txt") == "1")
        #expect(box.text("Destination/report 2.txt") == "2")
    }

    @Test func movingRemovesTheOriginal() throws {
        let file = try box.file("Source/notes.txt", "hello")
        #expect(try transfer([file], move: true) == 1)
        #expect(box.text("Destination/notes.txt") == "hello")
        #expect(!box.exists("Source/notes.txt"))
    }

    @Test func movingToTheFolderItIsAlreadyInDoesNothing() throws {
        let file = try box.file("Destination/notes.txt", "hello")
        #expect(try transfer([file], move: true) == 0)
        #expect(box.names("Destination") == ["notes.txt"])
    }

    @Test func refusesToPutAFolderInsideItself() throws {
        let outer = try box.folder("Outer")
        #expect(throws: FileOperations.Failure.intoItself("Outer")) {
            try FileTransfer.run([outer], to: box.folder("Outer/Inner"), move: false, homeDirectory: box.path("Home"))
        }
    }

    @Test func refusesToMoveProtectedFoldersButCopiesThem() throws {
        let documents = try box.folder("Home/Documents")
        try box.file("Home/Documents/a.txt")
        #expect(throws: FileOperations.Failure.protected("Documents")) {
            try transfer([documents], move: true)
        }
        #expect(box.exists("Home/Documents/a.txt"))
        #expect(try transfer([documents]) == 1)
    }

    @Test func aProblemIsFoundBeforeAnythingMoves() throws {
        let file = try box.file("Source/notes.txt")
        let documents = try box.folder("Home/Documents")
        #expect(throws: FileOperations.Failure.self) { try transfer([file, documents], move: true) }
        #expect(box.exists("Source/notes.txt"))
        #expect(box.names("Destination").isEmpty)
    }

    @Test func progressEndsAtTheTotal() throws {
        var bytes = [UInt8](repeating: 0, count: 3_000_000)
        for index in bytes.indices { bytes[index] = UInt8(truncatingIfNeeded: index &* 31 &+ 7) }
        let big = try box.file("Source/big.bin", data: Data(bytes))
        let small = try box.file("Source/Folder/small.txt", "12345")
        var reports: [TransferProgress] = []

        try transfer([big, (small as NSString).deletingLastPathComponent]) { reports.append($0) }

        let last = try #require(reports.last)
        #expect(last.totalBytes == 3_000_005)
        #expect(last.completedBytes == last.totalBytes)
        #expect(last.fraction == 1)
        #expect(reports.map(\.completedBytes) == reports.map(\.completedBytes).sorted(), "progress never goes backwards")
    }

    @Test func cancellingBeforeTheStartCopiesNothing() throws {
        let file = try box.file("Source/notes.txt")
        let control = OperationControl()
        control.cancel()
        #expect(throws: CancellationError.self) { try transfer([file], control: control) }
        #expect(box.names("Destination").isEmpty)
    }

    @Test func cancellingPartWayRemovesTheUnfinishedItem() throws {
        let first = try box.file("Source/first.txt", "1")
        let folder = try box.folder("Source/Big")
        for index in 0..<40 { try box.file("Source/Big/\(index).bin", data: Data(count: 200_000)) }
        let control = OperationControl()
        var stoppedInsideBig = false

        #expect(throws: CancellationError.self) {
            try transfer([first, folder], control: control) { progress in
                // More than first.txt's single byte means Big is being copied right now.
                guard progress.completedBytes > 1_000_000, progress.completedBytes < progress.totalBytes else { return }
                stoppedInsideBig = true
                control.cancel()
            }
        }
        #expect(stoppedInsideBig)
        #expect(box.names("Destination") == ["first.txt"], "finished items stay, the unfinished one is removed")
        #expect(box.names("Source/Big").count == 40)
    }

    @Test func aNameTakenWhileCopyingIsLeftAlone() throws {
        let source = try box.file("Source/big.bin", data: Data(count: 2_500_000))
        var othersWrote = false

        // Another app creates the same name while the copy is still running.
        try transfer([source]) { [box] _ in
            guard !othersWrote else { return }
            othersWrote = true
            try? Data("theirs".utf8).write(to: URL(fileURLWithPath: box.path("Destination/big.bin")))
        }

        #expect(othersWrote)
        #expect(box.text("Destination/big.bin") == "theirs")
        #expect(box.names("Destination") == ["big 2.bin", "big.bin"])
        #expect(try Data(contentsOf: URL(fileURLWithPath: box.path("Destination/big 2.bin"))).count == 2_500_000)
    }

    @Test func nothingIsVisibleUnderTheRealNameUntilTheCopyIsComplete() throws {
        let folder = try box.folder("Source/Album")
        for index in 0..<12 { try box.file("Source/Album/\(index).bin", data: Data(count: 300_000)) }
        var namesSeenDuringCopy: Set<String> = []

        try transfer([folder]) { [box] progress in
            guard progress.completedBytes < progress.totalBytes else { return }
            namesSeenDuringCopy.formUnion(box.names("Destination").filter { !$0.hasPrefix(".") })
        }

        #expect(namesSeenDuringCopy.isEmpty, "a half-copied folder never shows up as the real thing")
        #expect(box.names("Destination") == ["Album"])
        #expect(box.names("Destination/Album").count == 12)
    }

    @Test func aBrokenLinkWithTheSameNameIsSteppedAround() throws {
        let file = try box.file("Source/notes.txt", "mine")
        try FileManager.default.createSymbolicLink(atPath: box.path("Destination/notes.txt"), withDestinationPath: "/nowhere/at/all")

        #expect(try transfer([file]) == 1)

        #expect(box.text("Destination/notes 2.txt") == "mine")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: box.path("Destination/notes.txt")) == "/nowhere/at/all")
    }

    @Test func readOnlyFoldersAreCopiedWithTheirContents() throws {
        let folder = try box.folder("Source/Vendor")
        try box.file("Source/Vendor/Inner/lib.txt", "code")
        for path in ["Source/Vendor/Inner", "Source/Vendor"] {
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: box.path(path))
        }

        #expect(try transfer([folder]) == 1)

        #expect(box.text("Destination/Vendor/Inner/lib.txt") == "code")
        #expect(box.permissions("Destination/Vendor") == 0o555)
        #expect(box.permissions("Destination/Vendor/Inner") == 0o555)
    }

    @Test func lockedItemsAreCopiedAndStayLocked() throws {
        let file = try box.file("Source/contract.txt", "signed")
        let folder = try box.folder("Source/Archive")
        try box.file("Source/Archive/old.txt", "old")
        box.setLocked(true, box.path("Source/Archive/old.txt"))
        box.setLocked(true, file)
        box.setLocked(true, folder)

        #expect(try transfer([file, folder]) == 2)

        #expect(box.text("Destination/contract.txt") == "signed")
        #expect(box.isLocked("Destination/contract.txt"))
        #expect(box.text("Destination/Archive/old.txt") == "old")
        #expect(box.isLocked("Destination/Archive"))
        #expect(box.isLocked("Destination/Archive/old.txt"))
    }

    @Test func aLockedItemIsNotMoved() throws {
        let file = try box.file("Source/contract.txt", "signed")
        box.setLocked(true, file)
        #expect(throws: FileOperations.Failure.locked("contract.txt")) { try transfer([file], move: true) }
        #expect(box.exists("Source/contract.txt"))
        #expect(box.names("Destination").isEmpty)
    }

    @Test func cancellingLeavesNothingEvenWhenLockedFilesWereAlreadyCopied() throws {
        let folder = try box.folder("Source/Big")
        for index in 0..<30 { try box.file("Source/Big/\(index).bin", data: Data(count: 200_000)) }
        for index in 0..<30 { box.setLocked(true, box.path("Source/Big/\(index).bin")) }
        let control = OperationControl()

        #expect(throws: CancellationError.self) {
            try transfer([folder], control: control) { progress in
                if progress.completedBytes > 1_000_000 { control.cancel() }
            }
        }
        #expect(box.names("Destination").isEmpty)
    }

    @Test func aFailedCopyLeavesNoPartialItemAndNamesTheCulprit() throws {
        let folder = try box.folder("Source/Mixed")
        try box.file("Source/Mixed/fine.txt")
        try box.file("Source/Mixed/locked.txt", "secret", permissions: 0o000)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: box.path("Source/Mixed/locked.txt")) }

        #expect {
            try transfer([folder])
        } throws: { error in
            guard case FileOperations.Failure.couldNotCopy(let name, _) = error else { return false }
            return name == "locked.txt"
        }
        #expect(box.names("Destination").isEmpty)
    }
}
