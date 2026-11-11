import AppKit
import FinderSync
import RightShortcutsCore

/// Finder's entry point. Finder calls in on arbitrary threads, so every call hops to the main
/// thread, where `FinderMenuController` keeps all state.
@objc(RightShortcutsFinderSync)
final class FinderSyncExtension: FIFinderSync {
    private let controller: FinderMenuController

    override init() {
        controller = Self.onMain { FinderMenuController() }
        super.init()
    }

    override var toolbarItemName: String { AppIdentity.displayName }
    override var toolbarItemToolTip: String { "Your Right Shortcuts actions" }
    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: AppIdentity.menuSymbol, accessibilityDescription: AppIdentity.displayName) ?? NSImage()
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let controller = controller
        let action = #selector(performAction(_:))
        return Self.onMain { Unchecked(controller.menu(for: menuKind, action: action)) }.value
    }

    @objc private func performAction(_ sender: Any?) {
        let controller = controller
        let item = Unchecked(sender as? NSMenuItem)
        Self.onMain { controller.perform(tag: item.value?.tag) }
    }

    private static func onMain<T: Sendable>(_ work: @MainActor () -> T) -> T {
        if Thread.isMainThread { return MainActor.assumeIsolated(work) }
        return DispatchQueue.main.sync { MainActor.assumeIsolated(work) }
    }
}

/// Carries AppKit objects across the hop to the main thread, where they are used exclusively.
private struct Unchecked<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

/// Builds menus from the shared settings and forwards clicks to the app.
@MainActor
final class FinderMenuController: NSObject {
    private var config = AppConfig()
    private var access = HostAccess()
    /// When the shared files last changed, to skip re-reading them for every menu.
    private var stamps: [Date?] = []
    /// Maps menu item tags to actions for the menu that is currently open.
    private var actions: [Int: ActionTarget] = [:]
    private var menuLocation: MenuLocation = .items

    override init() {
        super.init()
        reloadConfig(force: true)
        ConfigNotifier.observe { [weak self] in
            MainActor.assumeIsolated { self?.reloadConfig(force: true) }
        }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(volumesChanged(_:)), name: NSWorkspace.didMountNotification, object: nil)
        center.addObserver(self, selector: #selector(volumesChanged(_:)), name: NSWorkspace.didUnmountNotification, object: nil)
    }

    func menu(for menuKind: FIMenuKind, action: Selector) -> NSMenu? {
        reloadConfig(force: false)
        let scenario = makeScenario(for: menuKind)
        let nodes = MenuResolver.menu(for: config, scenario: scenario)
        Log.finder.debug("Menu for \(scenario.location.rawValue, privacy: .public) with \(scenario.items.count) selected: \(nodes.count) entries")
        guard !nodes.isEmpty else { return nil }

        menuLocation = scenario.location
        let result = MenuFactory.makeMenu(from: nodes, showIcons: config.showIcons, action: action)
        actions = result.actions
        return result.menu
    }

    func perform(tag: Int?) {
        guard let tag, let target = actions[tag] else {
            Log.finder.error("Clicked an item with unknown tag \(tag ?? -1)")
            return
        }
        let controller = FIFinderSyncController.default()
        let request = ActionRequest(
            target: target,
            location: menuLocation,
            targetPath: controller.targetedURL()?.path,
            selectedPaths: controller.selectedItemURLs()?.map(\.path) ?? []
        )
        // Asking for permission needs the app in front, so find out now whether it will have to.
        let activate = config.needsActivation(request, access: access) { Self.describe(URL(fileURLWithPath: $0)).isDirectory }
        Log.finder.debug("Forwarding a click; bringing the app forward: \(activate)")
        HostBridge.send(request, activateApp: activate)
    }

    // MARK: - Scenario

    private func makeScenario(for menuKind: FIMenuKind) -> MenuScenario {
        let controller = FIFinderSyncController.default()
        let target = controller.targetedURL()
        var selected = controller.selectedItemURLs() ?? []

        let location: MenuLocation
        switch menuKind {
        case .contextualMenuForContainer:
            location = .container
            selected = []
        case .contextualMenuForSidebar:
            location = .sidebar
            if selected.isEmpty, let target { selected = [target] }
        case .toolbarItemMenu:
            location = .toolbar
        default:
            location = .items
        }
        return MenuScenario(location: location, targetPath: target?.path, items: selected.map(Self.describe))
    }

    private static func describe(_ url: URL) -> SelectedItem {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isHiddenKey])
        let isDirectory = values?.isDirectory ?? url.hasDirectoryPath
        let isPackage = values?.isPackage ?? false
        return SelectedItem(path: url.path, isDirectory: isDirectory && !isPackage, isHidden: values?.isHidden)
    }

    // MARK: - Settings

    private func reloadConfig(force: Bool) {
        let current = [SharedFiles.config.modificationDate(), SharedFiles.hostAccess.modificationDate()]
        guard force || current != stamps else { return }
        stamps = current
        let stored = SharedFiles.config.load()
        config = stored ?? AppConfig()
        access = SharedFiles.hostAccess.load() ?? HostAccess()
        Log.finder.info("Loaded settings: \(stored == nil ? "none found" : "\(self.config.items.count) items", privacy: .public)")
        applyCoverage()
    }

    private func applyCoverage() {
        let urls: Set<URL>
        if config.isPaused {
            urls = []
        } else {
            switch config.coverage {
            case .everywhere:
                let volumes = FileManager.default.mountedVolumeURLs(
                    includingResourceValuesForKeys: nil,
                    options: [.skipHiddenVolumes]
                ) ?? []
                urls = Set([URL(fileURLWithPath: "/")] + volumes)
            case .selectedFolders:
                urls = Set(config.watchedFolders.map { URL(fileURLWithPath: $0, isDirectory: true) })
            }
        }
        FIFinderSyncController.default().directoryURLs = urls
        Log.finder.info("Watching \(urls.count) location(s)")
    }

    @objc private func volumesChanged(_ notification: Notification) {
        if config.coverage == .everywhere { applyCoverage() }
    }
}
