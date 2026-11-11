import AppKit
import MetricKit
import OSLog
import RightShortcutsCore

/// Keeps the crash and hang reports macOS hands to the app, and writes a report the user
/// can read or send along when something goes wrong. Nothing leaves the Mac on its own.
@MainActor
enum Diagnostics {
    private static let subscriber = Subscriber()

    static func start() {
        MXMetricManager.shared.add(subscriber)
    }

    /// Asks where to save and writes the report there.
    static func export(model: AppModel, access: AccessController, extensionIsOn: Bool) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Right Shortcuts Diagnostics.txt"
        // Otherwise the panel reopens wherever the last picker was, which can be an odd place.
        panel.directoryURL = URL(fileURLWithPath: UserHome.path, isDirectory: true).appendingPathComponent("Desktop")
        panel.message = "The report lists your settings and recent activity. It can include names of files from error messages."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(report(model: model, access: access, extensionIsOn: extensionIsOn).utf8).write(to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            ToastCenter.shared.show("The report couldn’t be saved: \(error.localizedDescription)",
                                    symbol: "exclamationmark.triangle.fill", style: .failure)
        }
    }

    private static func report(model: AppModel, access: AccessController, extensionIsOn: Bool) -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let config = model.config
        let enabled = config.items.filter { $0.isEnabled && !$0.isSeparator }

        var lines = [
            "Right Shortcuts diagnostics, \(Date().formatted(.iso8601))",
            "",
            "App: \(version) (\(build))",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Finder extension: \(extensionIsOn ? "on" : "off")",
            "Paused: \(config.isPaused ? "yes" : "no")",
            "Menu appears: \(config.coverage == .everywhere ? "everywhere" : "in \(config.watchedFolders.count) chosen folder(s)")",
            "Exceptions: \(config.excludedFolders.count)",
            "Layout: \(config.menuLayout.rawValue)",
            "Menu items on: \(enabled.count) of \(config.items.filter { !$0.isSeparator }.count)",
            "Templates on: \(config.templates.filter(\.isEnabled).count) of \(config.templates.count)",
            "Allowed folders: \(access.folders.isEmpty ? "none" : access.folders.joined(separator: ", "))",
            "Not reachable now: \(access.unavailableFolders.isEmpty ? "none" : access.unavailableFolders.joined(separator: ", "))",
            "Command helper: \(access.helperState)",
            "Last save error: \(model.saveError ?? "none")",
            "",
            "Recent activity (this session)",
        ]
        let activity = recentActivity()
        lines += activity.isEmpty ? ["  nothing logged"] : activity.map { "  " + $0 }

        let reports = Subscriber.storedReports()
        lines += ["", "Crash and hang reports from macOS: \(reports.count)"]
        for url in reports {
            lines += ["", "--- \(url.lastPathComponent)", (try? String(contentsOf: url, encoding: .utf8)) ?? "(unreadable)"]
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// What this app logged in the last hour. Only this process's own entries can be read.
    private static func recentActivity() -> [String] {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier),
              let entries = try? store.getEntries(
                  at: store.position(date: Date().addingTimeInterval(-3600)),
                  matching: NSPredicate(format: "subsystem == %@", AppIdentity.hostBundleID)
              ) else { return [] }
        return entries.compactMap { $0 as? OSLogEntryLog }.suffix(300).map { entry in
            "\(entry.date.formatted(date: .omitted, time: .standard)) \(entry.composedMessage)"
        }
    }
}

/// Receives the reports. macOS calls in on a background queue, usually the day after a crash.
private final class Subscriber: NSObject, MXMetricManagerSubscriber {
    private static let limit = 5

    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Diagnostics", isDirectory: true)
    }

    /// Newest first.
    static func storedReports() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let manager = FileManager.default
        try? manager.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        for payload in payloads {
            let name = "\(payload.timeStampEnd.formatted(.iso8601.timeSeparator(.omitted)))-\(UUID().uuidString.prefix(6)).json"
            try? payload.jsonRepresentation().write(to: Self.folder.appendingPathComponent(name))
        }
        for old in Self.storedReports().dropFirst(Self.limit) {
            try? manager.removeItem(at: old)
        }
        Log.app.info("Stored \(payloads.count) diagnostic report(s) from macOS")
    }
}
