import AppKit
import RightShortcutsCore

/// Converts resolved menu nodes into an NSMenu that Finder can show.
@MainActor
enum MenuFactory {
    struct Result {
        let menu: NSMenu
        let actions: [Int: ActionTarget]
    }

    /// Finder copies menu items before showing them and keeps only basic properties such as
    /// the tag, so each clickable item gets a tag that points into `actions`.
    static func makeMenu(from nodes: [MenuNode], showIcons: Bool, action: Selector) -> Result {
        var actions: [Int: ActionTarget] = [:]
        let menu = build(nodes, showIcons: showIcons, action: action, actions: &actions)
        return Result(menu: menu, actions: actions)
    }

    private static func build(
        _ nodes: [MenuNode],
        showIcons: Bool,
        action: Selector,
        actions: inout [Int: ActionTarget]
    ) -> NSMenu {
        let menu = NSMenu(title: "")
        for node in nodes {
            switch node.content {
            case .separator:
                menu.addItem(.separator())
            case .action(let target):
                let item = NSMenuItem(title: node.title, action: action, keyEquivalent: "")
                item.tag = actions.count + 1
                actions[item.tag] = target
                if showIcons { item.image = icon(for: node) }
                menu.addItem(item)
            case .submenu(let children):
                let item = NSMenuItem(title: node.title, action: nil, keyEquivalent: "")
                item.submenu = build(children, showIcons: showIcons, action: action, actions: &actions)
                if showIcons { item.image = icon(for: node) }
                menu.addItem(item)
            }
        }
        return menu
    }

    private static func icon(for node: MenuNode) -> NSImage? {
        let image: NSImage?
        if let appPath = node.appPath {
            image = NSWorkspace.shared.icon(forFile: appPath)
        } else if let symbol = node.symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        } else {
            image = nil
        }
        image?.size = NSSize(width: 16, height: 16)
        return image
    }
}
