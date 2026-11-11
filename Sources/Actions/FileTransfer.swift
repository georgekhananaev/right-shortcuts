import Darwin
import Foundation
import RightShortcutsCore

/// How far a copy or move has come.
public struct TransferProgress: Equatable, Sendable {
    public var completedBytes: Int64
    public var totalBytes: Int64

    /// Between 0 and 1, or nil when there is nothing to measure, such as a move on the same disk.
    public var fraction: Double? {
        totalBytes > 0 ? min(1, Double(completedBytes) / Double(totalBytes)) : nil
    }
}

/// Copies and moves items with progress and the option to stop part-way.
public enum FileTransfer {
    /// Copies or moves items into `folder`. Never overwrites: clashing names get a number.
    /// An item that fails or is cancelled part-way is removed again, so nothing half-copied stays behind.
    /// Items already finished stay where they are.
    /// - Returns: The number of items handled.
    @discardableResult
    public static func run(
        _ paths: [String],
        to folder: String,
        move: Bool,
        homeDirectory: String = UserHome.path,
        control: OperationControl = OperationControl(),
        progress: @escaping (TransferProgress) -> Void = { _ in }
    ) throws -> Int {
        let manager = FileManager.default
        let destination = URL(fileURLWithPath: folder, isDirectory: true)
        // Check everything first so a problem never leaves a move half done.
        if move { try FileOperations.ensureUnprotected(paths, homeDirectory: homeDirectory) }
        if let nested = paths.first(where: { PathMatching.isPath(folder, inside: $0) }) {
            throw FileOperations.Failure.intoItself((nested as NSString).lastPathComponent)
        }
        try control.checkCancelled()

        let sources = paths.map { URL(fileURLWithPath: $0) }.filter { source in
            // Moving an item to the folder it is already in changes nothing.
            !(move && source.deletingLastPathComponent().standardizedFileURL == destination.standardizedFileURL)
        }
        let steps = try sources.map { source in
            let renames = move && isSameVolume(source, destination)
            if renames {
                // A locked item can't be renamed.
                if FileOperations.isLocked(source) { throw FileOperations.Failure.locked(source.lastPathComponent) }
            } else if move {
                // Moving to another disk copies, then deletes the original, which would stop at a locked item.
                try FileOperations.ensureNothingLocked([source.path], control: control)
            }
            return Step(source: source, renames: renames, bytes: renames ? 0 : try byteCount(of: source, control: control))
        }
        let total = steps.reduce(0) { $0 + $1.bytes }

        var done: Int64 = 0
        for step in steps {
            try control.checkCancelled()
            let name = step.source.lastPathComponent
            // Packages keep their extension: "App 2.app", not "App.app 2".
            let isFolder = FileOperations.isFolder(step.source.path)
            if step.renames {
                try place(step.source, in: destination, named: name, isFolder: isFolder)
            } else {
                // Copied under a hidden temporary name first. A half-copied item never shows up as
                // the real thing, and cleaning up can only ever remove what this copy created.
                let staging = destination.appendingPathComponent(".\(UUID().uuidString).partial", isDirectory: isFolder)
                let base = done
                do {
                    try copy(step.source, to: staging, control: control) { bytes in
                        progress(TransferProgress(completedBytes: min(total, base + bytes), totalBytes: total))
                    }
                    try placeCopy(staging, in: destination, named: name, isFolder: isFolder)
                } catch {
                    discard(staging)
                    throw error
                }
                if move { try manager.removeItem(at: step.source) }
                done += step.bytes
                progress(TransferProgress(completedBytes: done, totalBytes: total))
            }
        }
        return steps.count
    }

    /// Gives a finished copy its real name. A copy of a locked item is locked too and can't be
    /// renamed, so the lock comes off for the rename and goes back on afterwards.
    private static func placeCopy(_ staging: URL, in folder: URL, named name: String, isFolder: Bool) throws {
        let isLocked = FileOperations.isLocked(staging)
        if isLocked { setLocked(false, staging) }
        let placed = try place(staging, in: folder, named: name, isFolder: isFolder)
        if isLocked { setLocked(true, placed) }
    }

    /// Renames `item` to the first free "name", "name 2", … in `folder`. The rename itself refuses
    /// to replace anything, so a name another app takes at the last moment is skipped, not overwritten.
    @discardableResult
    private static func place(_ item: URL, in folder: URL, named name: String, isFolder: Bool) throws -> URL {
        var attempt = 1
        while true {
            let candidate = FileNaming.candidateName(name, isDirectory: isFolder, attempt: attempt)
            let target = folder.appendingPathComponent(candidate, isDirectory: isFolder)
            attempt += 1
            if renamex_np(item.path, target.path, UInt32(RENAME_EXCL)) == 0 { return target }
            switch errno {
            case EEXIST:
                continue
            case ENOTSUP:
                // This disk can't rename exclusively. FileManager still refuses to replace an existing item.
                if FileNaming.itemExists(target) { continue }
                try FileManager.default.moveItem(at: item, to: target)
                return target
            case let code:
                throw FileOperations.Failure.couldNotMove(name: name, reason: String(cString: strerror(code)))
            }
        }
    }

    /// Removes a copy this transfer made and gave up on. Locked and read-only parts would
    /// stop a plain delete, so they are opened up first.
    private static func discard(_ staging: URL) {
        guard FileNaming.itemExists(staging) else { return }
        unlock(staging.path)
        let enumerator = FileManager.default.enumerator(at: staging, includingPropertiesForKeys: nil)
        while let item = enumerator?.nextObject() as? URL { unlock(item.path) }
        do {
            try FileManager.default.removeItem(at: staging)
        } catch {
            Log.app.error("Couldn’t remove an unfinished copy at \(staging.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Clears every flag on an item and lets its owner change it.
    fileprivate static func unlock(_ path: String) {
        lchflags(path, 0)
        var info = stat()
        if lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR { chmod(path, info.st_mode | S_IRWXU) }
    }

    private static func setLocked(_ locked: Bool, _ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isUserImmutable = locked
        try? url.setResourceValues(values)
    }

    private struct Step {
        let source: URL
        /// A move within one disk only renames; nothing is copied.
        let renames: Bool
        let bytes: Int64
    }

    private static func isSameVolume(_ first: URL, _ second: URL) -> Bool {
        guard let one = try? first.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier,
              let other = try? second.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier else { return false }
        return one.isEqual(other)
    }

    /// The size of a file, or of every file inside a folder.
    private static func byteCount(of url: URL, control: OperationControl) throws -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey]
        let values = try url.resourceValues(forKeys: keys)
        guard values.isDirectory == true else { return Int64(values.fileSize ?? 0) }

        var total: Int64 = 0
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))
        while let item = enumerator?.nextObject() as? URL {
            try control.checkCancelled()
            let itemValues = try? item.resourceValues(forKeys: keys)
            if itemValues?.isRegularFile == true { total += Int64(itemValues?.fileSize ?? 0) }
        }
        return total
    }

    /// Copies one item with `copyfile`, which clones instantly where the disk allows it,
    /// reports bytes as it goes and can be stopped between chunks. The caller removes what
    /// a failed copy left at `target`.
    private static func copy(
        _ source: URL,
        to target: URL,
        control: OperationControl,
        report: @escaping (Int64) -> Void
    ) throws {
        guard let state = copyfile_state_alloc() else { throw POSIXError(.ENOMEM) }
        defer { copyfile_state_free(state) }

        let observer = CopyObserver(control: control, report: report)
        let callback: copyfile_callback_t = { what, stage, state, sourcePath, targetPath, context in
            guard let context else { return COPYFILE_CONTINUE }
            return Unmanaged<CopyObserver>.fromOpaque(context).takeUnretainedValue()
                .handle(what: what, stage: stage, state: state, sourcePath: sourcePath, targetPath: targetPath)
        }
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(callback, to: UnsafeRawPointer.self))
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), Unmanaged.passUnretained(observer).toOpaque())

        // Links are copied as links, like Finder does, never followed.
        let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_CLONE | COPYFILE_NOFOLLOW)
        let status = withExtendedLifetime(observer) { copyfile(source.path, target.path, state, flags) }
        guard status != 0 else { return }

        let code = observer.failure?.code ?? errno
        try control.checkCancelled()
        throw FileOperations.Failure.couldNotCopy(
            name: observer.failure?.name ?? source.lastPathComponent,
            reason: String(cString: strerror(code))
        )
    }
}

/// Receives `copyfile`'s callbacks for one item.
private final class CopyObserver {
    private let control: OperationControl
    private let report: (Int64) -> Void
    private var finishedBytes: Int64 = 0
    private var reportedBytes: Int64 = 0
    private(set) var failure: (name: String, code: Int32)?

    /// Reporting every chunk would flood the interface; this is often enough for a smooth bar.
    private static let reportStep: Int64 = 1_048_576

    init(control: OperationControl, report: @escaping (Int64) -> Void) {
        self.control = control
        self.report = report
    }

    func handle(
        what: Int32,
        stage: Int32,
        state: copyfile_state_t?,
        sourcePath: UnsafePointer<CChar>?,
        targetPath: UnsafePointer<CChar>?
    ) -> Int32 {
        if control.isCancelled { return COPYFILE_QUIT }
        switch (what, stage) {
        case (COPYFILE_RECURSE_DIR, COPYFILE_FINISH):
            // The new folder already has its final permissions and lock, before anything is in it.
            // Open it up so a read-only or locked folder can be filled; copyfile restores both at the end.
            if let targetPath { FileTransfer.unlock(String(cString: targetPath)) }
        case (COPYFILE_COPY_DATA, COPYFILE_PROGRESS):
            var copied: off_t = 0
            copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied)
            announce(finishedBytes + Int64(copied))
        case (COPYFILE_RECURSE_FILE, COPYFILE_FINISH):
            var info = stat()
            if let sourcePath, lstat(sourcePath, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG {
                finishedBytes += Int64(info.st_size)
            }
            announce(finishedBytes)
        case (COPYFILE_COPY_XATTR, COPYFILE_ERR):
            // Extra attributes the destination disk can't store are not worth failing the copy for.
            return COPYFILE_SKIP
        case (_, COPYFILE_ERR):
            let code = errno
            let name = sourcePath.map { URL(fileURLWithPath: String(cString: $0)).lastPathComponent }
            failure = (name ?? "", code)
            return COPYFILE_QUIT
        default:
            break
        }
        return COPYFILE_CONTINUE
    }

    private func announce(_ bytes: Int64) {
        guard bytes - reportedBytes >= Self.reportStep else { return }
        reportedBytes = bytes
        report(bytes)
    }
}
