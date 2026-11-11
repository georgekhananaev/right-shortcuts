import Foundation

/// Turns the configuration into the menu for one situation.
/// The Finder extension and the settings preview both use it, so they always agree.
public enum MenuResolver {
    public static func menu(for config: AppConfig, scenario: MenuScenario) -> [MenuNode] {
        guard !config.isPaused, !isExcluded(scenario, config: config) else { return [] }

        let nodes = tidySeparators(config.items.compactMap { node(for: $0, config: config, scenario: scenario) })
        guard nodes.contains(where: { !$0.isSeparator }) else { return [] }

        switch config.menuLayout {
        case .inline:
            return nodes
        case .submenu:
            return [MenuNode(id: "root", title: AppIdentity.displayName, symbol: AppIdentity.menuSymbol, content: .submenu(nodes))]
        }
    }

    /// Whether the item belongs in the menu for this scenario.
    public static func isVisible(_ item: MenuItem, in scenario: MenuScenario) -> Bool {
        guard item.isEnabled else { return false }
        if item.isSeparator { return true }

        let contexts = item.effectiveContexts
        let extensions = item.normalizedExtensions
        let supported = item.kind.supportedContexts

        let isSelectionVisible: Bool
        switch scenario.location {
        case .container:
            guard contexts.contains(.background) else { return false }
            return extensions.isEmpty && !item.kind.requiresSelection
        case .toolbar:
            guard contexts.contains(.toolbar) else { return false }
            if scenario.items.isEmpty {
                return extensions.isEmpty && !item.kind.requiresSelection
            }
            isSelectionVisible = selection(
                scenario.items,
                allowsFiles: supported.contains(.files),
                allowsFolders: supported.contains(.folders),
                extensions: extensions
            )
        case .sidebar:
            // Sidebar entries are favorites and drives: offer only actions that leave them in place.
            guard !scenario.items.isEmpty, !item.kind.requiresSelection else { return false }
            isSelectionVisible = selection(
                scenario.items,
                allowsFiles: contexts.contains(.files),
                allowsFolders: contexts.contains(.folders),
                extensions: extensions
            )
        case .items:
            guard !scenario.items.isEmpty else { return false }
            isSelectionVisible = selection(
                scenario.items,
                allowsFiles: contexts.contains(.files),
                allowsFolders: contexts.contains(.folders),
                extensions: extensions
            )
        }
        return isSelectionVisible && matchesHiddenState(item, items: scenario.items)
    }

    // MARK: - Building nodes

    private static func node(for item: MenuItem, config: AppConfig, scenario: MenuScenario) -> MenuNode? {
        guard isVisible(item, in: scenario) else { return nil }
        let id = item.id.uuidString
        let symbol = item.symbol

        switch item.kind {
        case .separator:
            return .separator(id: id)
        case .openWith(let app):
            return MenuNode(id: id, title: item.title, symbol: symbol, appPath: app.appPath,
                            content: .action(ActionTarget(itemID: item.id)))
        case .command:
            return MenuNode(id: id, title: item.title, symbol: symbol, content: .action(ActionTarget(itemID: item.id)))
        case .builtin(let action):
            guard action.opensSubmenu else {
                return MenuNode(id: id, title: item.title, symbol: symbol, content: .action(ActionTarget(itemID: item.id)))
            }
            let children = submenu(for: action, item: item, config: config)
            guard !children.isEmpty else { return nil }
            return MenuNode(id: id, title: item.title, symbol: symbol, content: .submenu(children))
        }
    }

    private static func submenu(for action: BuiltinAction, item: MenuItem, config: AppConfig) -> [MenuNode] {
        let prefix = item.id.uuidString
        func entry(_ option: String, _ title: String, _ symbol: String?) -> MenuNode {
            MenuNode(id: "\(prefix).\(option)", title: title, symbol: symbol,
                     content: .action(ActionTarget(itemID: item.id, option: option)))
        }

        switch action {
        case .newFile:
            return config.templates.filter(\.isEnabled).map { entry($0.id, $0.name, $0.symbol) }
        case .copyPathAs:
            return CopyFormat.allCases.map { entry($0.rawValue, $0.title, nil) }
        case .goTo:
            return config.quickFolders.map { entry($0.id.uuidString, $0.name, "folder") }
        case .copyTo, .moveTo:
            let folders = config.quickFolders.map { entry($0.id.uuidString, $0.name, "folder") }
            let choose = entry(ActionTarget.chooseFolderOption, "Choose Folder…", "folder.badge.questionmark")
            return folders.isEmpty ? [choose] : folders + [.separator(id: "\(prefix).sep"), choose]
        default:
            return []
        }
    }

    // MARK: - Rules

    private static func selection(
        _ items: [SelectedItem],
        allowsFiles: Bool,
        allowsFolders: Bool,
        extensions: Set<String>
    ) -> Bool {
        items.allSatisfy { item in
            if item.isDirectory { return allowsFolders && extensions.isEmpty }
            return allowsFiles && (extensions.isEmpty || extensions.contains(item.pathExtension))
        }
    }

    /// Hide only shows for visible items and Unhide only for hidden ones. Unknown state shows both.
    private static func matchesHiddenState(_ item: MenuItem, items: [SelectedItem]) -> Bool {
        switch item.builtinAction {
        case .hide: items.contains { $0.isHidden != true }
        case .unhide: items.contains { $0.isHidden != false }
        default: true
        }
    }

    private static func isExcluded(_ scenario: MenuScenario, config: AppConfig) -> Bool {
        guard !config.excludedFolders.isEmpty else { return false }
        if let target = scenario.targetPath { return config.isExcluded(target) }
        return scenario.items.contains { config.isExcluded($0.path) }
    }

    /// Removes leading, trailing and repeated separators.
    static func tidySeparators(_ nodes: [MenuNode]) -> [MenuNode] {
        var result: [MenuNode] = []
        for node in nodes {
            if node.isSeparator && (result.isEmpty || result.last?.isSeparator == true) { continue }
            result.append(node)
        }
        while result.last?.isSeparator == true { result.removeLast() }
        return result
    }
}
