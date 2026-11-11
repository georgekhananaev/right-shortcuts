import AppKit
import RightShortcutsActions
import RightShortcutsCore

/// Carries out the clicks the Finder extension forwards, in the order they arrive.
@MainActor
final class ActionRunner {
    struct ActionError: LocalizedError {
        let errorDescription: String?

        init(_ message: String) {
            errorDescription = message
        }
    }

    private let model: AppModel
    private let access: AccessController
    private var queue: [ActionRequest] = []
    private var isRunning = false

    init(model: AppModel, access: AccessController) {
        self.model = model
        self.access = access
    }

    /// Picks up every waiting request from the shared inbox.
    func drainInbox() {
        queue.append(contentsOf: ActionInbox.drain())
        // While a picker is open the clicks behind it wait their turn.
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        while !queue.isEmpty {
            perform(queue.removeFirst())
        }
    }

    private func perform(_ request: ActionRequest) {
        guard let item = model.config.items.first(where: { $0.id == request.target.itemID }) else {
            fail(ActionError("That menu item was removed. Right-click again to see the current menu."))
            return
        }
        Log.app.info("Running “\(item.title, privacy: .public)” on \(request.operandPaths.count) item(s)")
        do {
            // The sandbox only lets the app touch folders the user allowed; ask before the first use.
            try access.ensureAccess(to: model.config.pathsNeedingAccess(for: request, isDirectory: FileOperations.isFolder))
            switch item.kind {
            case .builtin(let action):
                try run(action, option: request.target.option, request: request)
            case .openWith(let app):
                open(request, with: app)
            case .command(let command):
                run(command, with: try access.ensureHelper(), title: item.title, request: request)
            case .separator:
                break
            }
        } catch {
            report(error)
        }
    }

    // MARK: - Built-in actions

    private func run(_ action: BuiltinAction, option: String?, request: ActionRequest) throws {
        let paths = request.operands(for: action)
        guard !paths.isEmpty || action == .newFile || action == .goTo else { return }
        switch action {
        case .newFile:
            guard let template = model.config.templates.first(where: { $0.id == option }),
                  let directory = workingDirectory(of: request) else { return }
            runBeside { try await self.createFile(from: template, in: directory) }

        case .copyPath:
            copy(.fullPath, paths, message: paths.count == 1 ? "Path copied" : "\(paths.count) paths copied")
        case .copyName:
            copy(.name, paths, message: paths.count == 1 ? "Name copied" : "\(paths.count) names copied")
        case .copyPathAs:
            let format = option.flatMap(CopyFormat.init(rawValue:)) ?? .fullPath
            copy(format, paths, message: "\(format.title) copied")
        case .copyContents:
            setPasteboard(try FileOperations.readText(paths))
            confirm(paths.count == 1 ? "Contents copied" : "Contents of \(paths.count) files copied",
                    symbol: "doc.on.clipboard.fill")

        case .copyTo, .moveTo:
            let isMove = action == .moveTo
            guard let folder = destinationFolder(option: option, isMove: isMove, near: request.targetPath) else { return }
            transfer(paths, to: folder, move: isMove)
        case .goTo:
            guard let folder = quickFolder(option) else { return }
            guard NSWorkspace.shared.open(URL(fileURLWithPath: folder.path, isDirectory: true)) else {
                throw ActionError("“\(folder.name)” couldn’t be opened. It may have been moved or deleted.")
            }

        case .makeExecutable:
            try FileOperations.makeExecutable(paths)
            confirm(paths.count == 1 ? "“\(name(of: paths[0]))” can now run" : "\(paths.count) files can now run",
                    symbol: "terminal.fill")
        case .hide:
            try FileOperations.setHidden(true, paths: paths)
            confirm(paths.count == 1 ? "“\(name(of: paths[0]))” is now hidden" : "\(paths.count) items are now hidden",
                    symbol: "eye.slash.fill")
        case .unhide:
            try FileOperations.setHidden(false, paths: paths)
            confirm(paths.count == 1 ? "“\(name(of: paths[0]))” is visible again" : "\(paths.count) items are visible again",
                    symbol: "eye.fill")

        case .airDrop:
            let urls = paths.map { URL(fileURLWithPath: $0) }
            guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
                throw ActionError("AirDrop isn’t available. Check that Wi-Fi and Bluetooth are on.")
            }
            NSApp.activate()
            service.perform(withItems: urls)

        case .deletePermanently:
            try FileOperations.ensureUnprotected(paths)
            runBeside {
                guard await Prompts.confirmPermanentDeletion(of: paths) else { return }
                self.delete(paths)
            }
        }
    }

    /// Work that waits, on a prompt, another app or a script, runs beside the queue,
    /// so an unanswered prompt or a slow script never holds up later clicks.
    private func runBeside(_ work: @escaping @MainActor () async throws -> Void) {
        Task {
            do {
                try await work()
            } catch {
                report(error)
            }
        }
    }

    private func createFile(from template: FileTemplate, in directory: String) async throws {
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        var destination = FileNaming.availableURL(in: folder, name: template.defaultFileName)
        if model.config.askForFileName {
            let chosen = await Prompts.fileName(for: template, in: folder, suggestedName: destination.lastPathComponent)
            guard let chosen else { return }
            destination = folder.appendingPathComponent(chosen)
        }
        try TemplateWriter.write(template, to: destination,
                                 bundledTemplates: Bundle.main.resourceURL?.appendingPathComponent("Templates"))
        if model.config.openCreatedFile {
            NSWorkspace.shared.open(destination)
        } else {
            confirm("Created “\(destination.lastPathComponent)”", symbol: "doc.badge.plus")
        }
    }

    // MARK: - Long operations

    /// Copies and moves run beside the queue with a progress bar, so a large one never holds up other clicks.
    private func transfer(_ paths: [String], to folder: String, move: Bool) {
        let place = FileManager.default.displayName(atPath: folder)
        let subject = describe(paths, count: paths.count)
        runInBackground("\(move ? "Moving" : "Copying") \(subject) to \(place)") { job in
            try FileTransfer.run(paths, to: folder, move: move, control: job.control) { progress in
                Task { @MainActor in job.update(progress) }
            }
        } finished: { [weak self] count in
            guard let self, count > 0 else { return }
            confirm("\(move ? "Moved" : "Copied") \(describe(paths, count: count)) to \(place)",
                    symbol: move ? "folder.fill" : "doc.on.doc.fill")
        }
    }

    private func delete(_ paths: [String]) {
        let subject = describe(paths, count: paths.count)
        runInBackground("Deleting \(subject)") { job in
            try FileOperations.deletePermanently(paths, control: job.control)
            return paths.count
        } finished: { [weak self] _ in
            self?.confirm("Deleted \(subject)", symbol: "xmark.bin.fill")
        }
    }

    private func runInBackground(
        _ title: String,
        work: @escaping @Sendable (OperationJob) throws -> Int,
        finished: @escaping (Int) -> Void
    ) {
        let job = ProgressCenter.shared.begin(title)
        runBeside {
            defer { ProgressCenter.shared.end(job) }
            finished(try await Task.detached(priority: .userInitiated) { try work(job) }.value)
        }
    }

    // MARK: - Open with an app

    private func open(_ request: ActionRequest, with app: OpenWithApp) {
        let paths = request.pathsToOpen(with: app, isDirectory: FileOperations.isFolder)
        guard !paths.isEmpty else { return }
        runBeside {
            guard FileManager.default.fileExists(atPath: app.appPath) else {
                throw ActionError("\(app.appName) isn’t installed anymore. Pick it again in Right Shortcuts settings.")
            }
            _ = try await NSWorkspace.shared.open(
                paths.map { URL(fileURLWithPath: $0) },
                withApplicationAt: URL(fileURLWithPath: app.appPath),
                configuration: NSWorkspace.OpenConfiguration()
            )
        }
    }

    // MARK: - Custom commands

    private func run(_ command: CustomCommand, with helper: HelperScript, title: String, request: ActionRequest) {
        let paths = request.operandPaths
        let directory = workingDirectory(of: request)
        runBeside {
            try await helper.run(command, paths: paths, directory: directory, targetPath: request.targetPath)
            if command.runMode == .background { self.confirm("\(title) finished", symbol: "checkmark.circle.fill") }
        }
    }

    // MARK: - Helpers

    private func workingDirectory(of request: ActionRequest) -> String? {
        request.workingDirectory(isDirectory: FileOperations.isFolder)
    }

    private func quickFolder(_ option: String?) -> QuickFolder? {
        model.config.quickFolders.first { $0.id.uuidString == option }
    }

    /// - Parameter start: Where the picker opens: the folder the click came from.
    private func destinationFolder(option: String?, isMove: Bool, near start: String?) -> String? {
        guard option == ActionTarget.chooseFolderOption else { return quickFolder(option)?.path }
        let panel = Panels.folderPicker(
            message: isMove ? "Choose where to move the items." : "Choose where to copy the items.",
            prompt: isMove ? "Move Here" : "Copy Here",
            startingAt: start.map { URL(fileURLWithPath: $0, isDirectory: true) },
            canCreateFolders: true
        )
        return Panels.run(panel, forFinderClick: true)?.path
    }

    private func copy(_ format: CopyFormat, _ paths: [String], message: String) {
        setPasteboard(format.string(for: paths, homeDirectory: UserHome.path))
        confirm(message, symbol: "doc.on.clipboard.fill")
    }

    private func setPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private func name(of path: String) -> String {
        (path as NSString).lastPathComponent
    }

    private func describe(_ paths: [String], count: Int) -> String {
        count == 1 && paths.count == 1 ? "“\(name(of: paths[0]))”" : "\(count) items"
    }

    private func confirm(_ message: String, symbol: String) {
        guard model.config.showConfirmations else { return }
        ToastCenter.shared.show(message, symbol: symbol)
    }

    /// Shows what went wrong. A picker or prompt the user closed, or an operation they stopped,
    /// is no failure: nothing was done and nothing needs saying.
    private func report(_ error: Error) {
        if error is CancellationError { return }
        fail(error)
    }

    private func fail(_ error: Error) {
        Log.app.error("Action failed: \(error.localizedDescription, privacy: .public)")
        ToastCenter.shared.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill", style: .failure)
    }
}
