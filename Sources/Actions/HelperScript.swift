import CoreServices
import Foundation
import RightShortcutsCore

/// What a shell command produced.
public struct ShellResult: Equatable, Sendable {
    public let status: Int32
    public let output: String

    public var succeeded: Bool { status == 0 }
}

/// The script that runs custom commands. A sandboxed app can't start a shell that reaches the
/// user's files and tools, so macOS runs scripts kept in the app's scripts folder for it instead.
/// Only the user can put a script there, which is why installing asks first.
public struct HelperScript: Sendable {
    public enum State: Equatable, Sendable {
        case missing
        /// An older copy is installed; this version of the app ships a different one.
        case outdated
        case installed
    }

    public enum Failure: LocalizedError {
        case unreadableResult

        public var errorDescription: String? {
            "The command helper didn’t answer. Install it again in Right Shortcuts settings."
        }
    }

    /// The copy inside the app.
    public let bundled: URL
    /// Where macOS runs it from.
    public let installed: URL

    public init(bundled: URL, installed: URL) {
        self.bundled = bundled
        self.installed = installed
    }

    public var state: State {
        guard let current = try? Data(contentsOf: installed) else { return .missing }
        return current == (try? Data(contentsOf: bundled)) ? .installed : .outdated
    }

    /// Copies the script into place, replacing an older copy.
    public func install() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: installed.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: installed.path) { try manager.removeItem(at: installed) }
        try manager.copyItem(at: bundled, to: installed)
    }

    /// Runs a /bin/sh command line as the user, outside the sandbox, and waits for it to finish.
    public func run(_ commandLine: String) async throws -> ShellResult {
        let task = try NSUserAppleScriptTask(url: installed)
        // Calls the script's "run_shell" handler with the command line as its only parameter.
        let event = NSAppleEventDescriptor(
            eventClass: Code.appleScriptSuite,
            eventID: Code.subroutineEvent,
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setDescriptor(NSAppleEventDescriptor(string: "run_shell"), forKeyword: Code.subroutineName)
        let parameters = NSAppleEventDescriptor.list()
        parameters.insert(NSAppleEventDescriptor(string: commandLine), at: 1)
        event.setDescriptor(parameters, forKeyword: keyDirectObject)

        return try await withCheckedThrowingContinuation { continuation in
            task.execute(withAppleEvent: event) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result, result.numberOfItems == 2, let status = result.atIndex(1)?.int32Value {
                    continuation.resume(returning: ShellResult(status: status, output: result.atIndex(2)?.stringValue ?? ""))
                } else {
                    continuation.resume(throwing: Failure.unreadableResult)
                }
            }
        }
    }

    /// AppleScript's four-character codes for calling a handler by name.
    private enum Code {
        static let appleScriptSuite: AEEventClass = 0x6173_6372 // 'ascr'
        static let subroutineEvent: AEEventID = 0x7073_6272 // 'psbr'
        static let subroutineName: AEKeyword = 0x736E_616D // 'snam'
    }
}

extension HelperScript {
    /// Runs one of the user's custom commands and waits until it is done or handed to Terminal.
    public func run(_ command: CustomCommand, paths: [String], directory: String?, targetPath: String?) async throws {
        let line = switch command.runMode {
        case .background:
            CommandComposer.backgroundLine(command, paths: paths, directory: directory, targetPath: targetPath)
        case .terminal:
            CommandComposer.terminalLine(command, paths: paths, directory: directory, targetPath: targetPath)
        }
        let result = try await run(line)
        guard result.succeeded else {
            throw CommandComposer.Failure.failed(name: command.name, status: result.status, output: result.output)
        }
    }
}
