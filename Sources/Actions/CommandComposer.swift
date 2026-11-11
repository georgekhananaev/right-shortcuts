import Foundation
import RightShortcutsCore

/// Turns a custom command into the /bin/sh line the helper script runs.
public enum CommandComposer {
    public enum Failure: LocalizedError, Equatable {
        case failed(name: String, status: Int32, output: String)

        public var errorDescription: String? {
            switch self {
            case .failed(let name, let status, let output):
                let detail = output.split(whereSeparator: \.isNewline).last.map(String.init) ?? "exit code \(status)"
                return "\(name) failed: \(detail)"
            }
        }
    }

    /// Runs the script out of sight. A login shell picks up the user's PATH, so tools from
    /// Homebrew and friends work. Output and errors come back together.
    public static func backgroundLine(
        _ command: CustomCommand,
        paths: [String],
        directory: String?,
        targetPath: String?
    ) -> String {
        var steps = setup(paths: paths, directory: directory, targetPath: targetPath)
        let arguments = (["right-shortcuts"] + paths).map(ShellQuoting.quote).joined(separator: " ")
        steps.append("exec /bin/zsh -l -c \(ShellQuoting.quote(command.script)) \(arguments) 2>&1")
        return steps.joined(separator: "; ")
    }

    /// Hands the script to Terminal in a throwaway .command file, so no Automation permission is needed.
    /// - Parameter opener: The command that runs the file. Terminal by default.
    public static func terminalLine(
        _ command: CustomCommand,
        paths: [String],
        directory: String?,
        targetPath: String?,
        opener: String = "/usr/bin/open -a Terminal"
    ) -> String {
        // The file removes itself and its folder first, so nothing is left behind however the script ends.
        var lines = ["#!/bin/zsh -l", #"rm -f -- "$0"; rmdir -- "${0:h}" 2>/dev/null"#]
        lines += setup(paths: paths, directory: directory, targetPath: targetPath)
        lines.append("set -- " + paths.map(ShellQuoting.quote).joined(separator: " "))
        lines.append(command.script)
        let contents = lines.joined(separator: "\n") + "\n"

        return [
            #"folder="$(/usr/bin/mktemp -d)" || exit 1"#,
            #"file="$folder/Right Shortcuts.command""#,
            #"/usr/bin/printf '%s' \#(ShellQuoting.quote(contents)) > "$file" || exit 1"#,
            #"/bin/chmod 700 "$file""#,
            #"\#(opener) "$file" 2>&1"#,
        ].joined(separator: "; ")
    }

    /// Changes into the folder and exports the variables scripts can rely on.
    private static func setup(paths: [String], directory: String?, targetPath: String?) -> [String] {
        var steps: [String] = []
        if let directory { steps.append("cd -- \(ShellQuoting.quote(directory)) || exit 1") }
        let variables = [
            ("RS_DIR", directory ?? ""),
            ("RS_PATHS", paths.joined(separator: "\n")),
            ("RS_TARGET", targetPath ?? ""),
        ]
        steps += variables.map { "export \($0.0)=\(ShellQuoting.quote($0.1))" }
        return steps
    }
}
