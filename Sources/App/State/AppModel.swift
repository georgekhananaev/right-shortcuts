import Foundation
import Observation
import RightShortcutsCore

/// The app's single source of truth. Changes to `config` are saved and pushed to the extension.
@MainActor
@Observable
final class AppModel {
    var config: AppConfig {
        didSet { if config != oldValue { scheduleSave() } }
    }

    var showMenuBarIcon: Bool {
        didSet {
            defaults.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon)
            onMenuBarIconChange?()
        }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    var selectedPane: SettingsPane = .overview
    private(set) var saveError: String?
    /// Something to tell the user once the app has started, such as a settings file that couldn't be read.
    private(set) var startupNotice: String?

    @ObservationIgnored var onMenuBarIconChange: (() -> Void)?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum Keys {
        static let showMenuBarIcon = "showMenuBarIcon"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    init() {
        showMenuBarIcon = defaults.object(forKey: Keys.showMenuBarIcon) as? Bool ?? true
        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        switch SharedFiles.config.read() {
        case .valid(let stored):
            if stored.isFromNewerVersion {
                // Saving from this version would drop the newer settings, so keep a copy of them first.
                let backup = try? SharedFiles.config.backUp(label: "newer", removingOriginal: false)
                startupNotice = "Your settings come from a newer version of Right Shortcuts. "
                    + "A copy is saved as \(backup?.lastPathComponent ?? "a backup") next to the settings file."
            }
            var updated = stored.reconciled()
            updated.schemaVersion = AppConfig.currentSchemaVersion
            config = updated
            // Write only when something changed; otherwise leave the file untouched.
            if config != stored { saveNow() }
        case .damaged:
            let backup = try? SharedFiles.config.backUp(label: "damaged", removingOriginal: true)
            config = Self.freshConfig()
            saveNow()
            startupNotice = "Your settings file couldn’t be read, so Right Shortcuts started with the defaults. "
                + "The old file is saved as \(backup?.lastPathComponent ?? "a backup") next to the new one."
        case .none:
            config = Self.freshConfig()
            saveNow()
        }
    }

    static func freshConfig() -> AppConfig {
        AppConfig.makeDefault(homeDirectory: UserHome.path, apps: AppCatalog.defaultApps())
    }

    func resetToDefaults() {
        config = Self.freshConfig()
    }

    /// Writes immediately, for example right before quitting.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        do {
            try SharedFiles.config.save(config)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    func flushPendingSave() {
        if saveTask != nil { saveNow() }
    }

    /// Coalesces quick successive edits, like typing a title, into one write.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }
}
