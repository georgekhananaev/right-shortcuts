import RightShortcutsCore
import SwiftUI

/// A live mock of Finder's right-click menu, built with the same resolver the extension uses.
struct MenuPreviewPanel: View {
    @Environment(AppModel.self) private var model
    @State private var scenario: PreviewScenario = .file
    @State private var sampleFileName = "Report.pdf"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Preview")
                .font(.headline)
            Picker("Right-click on", selection: $scenario) {
                ForEach(PreviewScenario.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if scenario == .file {
                TextField("Sample file name", text: $sampleFileName, prompt: Text("Report.pdf"))
                    .textFieldStyle(.roundedBorder)
                    .help("Try a different name to check file type rules.")
            }

            ScrollView {
                VStack(alignment: .leading) {
                    if model.config.isPaused {
                        notice("Your menu is paused, so Finder shows none of these items right now.")
                    }
                    MockMenu(rows: finderRows, ours: nodes, style: model.config.menuLayout, showIcons: model.config.showIcons)
                        .padding(.bottom, 12)
                    if nodes.isEmpty {
                        notice("No items show here yet. Switch on “\(scenario.contextName)” for an item to add it.")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.background.secondary)
    }

    private var nodes: [MenuNode] {
        var config = model.config
        config.isPaused = false
        config.excludedFolders = []
        return MenuResolver.menu(for: config, scenario: scenario.menuScenario(fileName: sampleFileName))
    }

    private var finderRows: [String] {
        switch scenario {
        case .file: ["Open", "Open With", "Move to Trash", "", "Get Info", "Rename", "Duplicate"]
        case .folder: ["Open", "Open in New Tab", "Move to Trash", "", "Get Info", "Rename", "Compress"]
        case .background: ["New Folder", "", "Get Info", "View Options"]
        case .toolbar: []
        }
    }

    private var caption: String {
        switch model.config.menuLayout {
        case .submenu: "These items sit inside a “\(AppIdentity.displayName)” submenu. You can change that in General."
        case .inline: "These items appear directly in Finder’s menu. You can group them in General."
        }
    }

    private func notice(_ text: String) -> some View {
        Label(text, systemImage: "info.circle")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

enum PreviewScenario: String, CaseIterable, Identifiable {
    case file
    case folder
    case background
    case toolbar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .file: "File"
        case .folder: "Folder"
        case .background: "Background"
        case .toolbar: "Toolbar"
        }
    }

    var contextName: String {
        switch self {
        case .file: MenuContext.files.title
        case .folder: MenuContext.folders.title
        case .background: MenuContext.background.title
        case .toolbar: MenuContext.toolbar.title
        }
    }

    func menuScenario(fileName: String) -> MenuScenario {
        let folder = "/Users/Shared/Preview"
        let name = fileName.trimmingCharacters(in: .whitespaces).isEmpty ? "Report.pdf" : fileName
        switch self {
        case .file:
            return MenuScenario(location: .items, targetPath: folder,
                                items: [SelectedItem(path: "\(folder)/\(name)", isDirectory: false, isHidden: false)])
        case .folder:
            return MenuScenario(location: .items, targetPath: folder,
                                items: [SelectedItem(path: "\(folder)/Projects", isDirectory: true, isHidden: false)])
        case .background:
            return MenuScenario(location: .container, targetPath: folder, items: [])
        case .toolbar:
            return MenuScenario(location: .toolbar, targetPath: folder, items: [])
        }
    }
}

/// Finder's own items (dimmed) followed by ours, cascading like a real submenu.
private struct MockMenu: View {
    let rows: [String]
    let ours: [MenuNode]
    let style: MenuLayout
    let showIcons: Bool

    var body: some View {
        let root = style == .submenu ? ours.first : nil
        VStack(alignment: .leading, spacing: 0) {
            MenuPanel {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, title in
                    if title.isEmpty {
                        MenuDivider()
                    } else {
                        MockRow(title: title, symbol: nil, appPath: nil, hasSubmenu: title == "Open With",
                                isHighlighted: false, isDimmed: true, showIcons: false)
                    }
                }
                if !rows.isEmpty && !ours.isEmpty { MenuDivider() }
                if let root {
                    MockRow(title: root.title, symbol: root.symbol, appPath: nil, hasSubmenu: true,
                            isHighlighted: true, isDimmed: false, showIcons: showIcons)
                } else {
                    NodeRows(nodes: ours, showIcons: showIcons)
                }
            }
            if let root, case .submenu(let children) = root.content {
                MenuPanel {
                    NodeRows(nodes: children, showIcons: showIcons)
                }
                .padding(.leading, 36)
                .padding(.top, -6)
            }
        }
        .animation(.snappy(duration: 0.2), value: ours)
    }
}

/// Our nodes. Submenus expand in place when clicked.
private struct NodeRows: View {
    let nodes: [MenuNode]
    let showIcons: Bool
    @State private var expanded: Set<String> = []

    var body: some View {
        ForEach(nodes) { node in
            switch node.content {
            case .separator:
                MenuDivider()
            case .action:
                MockRow(title: node.title, symbol: node.symbol, appPath: node.appPath, hasSubmenu: false,
                        isHighlighted: false, isDimmed: false, showIcons: showIcons)
            case .submenu(let children):
                let isOpen = expanded.contains(node.id)
                Button {
                    if isOpen { expanded.remove(node.id) } else { expanded.insert(node.id) }
                } label: {
                    MockRow(title: node.title, symbol: node.symbol, appPath: node.appPath, hasSubmenu: true,
                            isHighlighted: isOpen, isDimmed: false, showIcons: showIcons)
                }
                .buttonStyle(.plain)
                .help(isOpen ? "Hide submenu" : "Show submenu")
                if isOpen {
                    VStack(alignment: .leading, spacing: 0) {
                        NodeRows(nodes: children, showIcons: showIcons)
                    }
                    .padding(.leading, 14)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Color.brand.opacity(0.35)).frame(width: 2).padding(.leading, 8)
                    }
                }
            }
        }
    }
}

private struct MenuPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(5)
        .frame(width: 250, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
    }
}

private struct MockRow: View {
    let title: String
    let symbol: String?
    let appPath: String?
    let hasSubmenu: Bool
    let isHighlighted: Bool
    let isDimmed: Bool
    let showIcons: Bool

    var body: some View {
        HStack(spacing: 7) {
            if showIcons {
                Group {
                    if let appPath {
                        AppIconView(path: appPath, size: 15)
                    } else if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 12))
                    }
                }
                .frame(width: 16)
            }
            Text(title)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer(minLength: 8)
            if hasSubmenu {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
            }
        }
        .foregroundStyle(isHighlighted ? AnyShapeStyle(.white) : isDimmed ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
        .padding(.horizontal, 9)
        .frame(height: 23)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHighlighted ? Color.brand : .clear)
        )
        .contentShape(Rectangle())
    }
}

private struct MenuDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(height: 1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
    }
}
