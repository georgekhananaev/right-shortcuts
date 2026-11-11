import AppKit
import RightShortcutsCore
import SwiftUI

/// The heart of the app: the list of menu items next to a live preview.
struct MenuItemsPane: View {
    @Environment(AppModel.self) private var model
    @State private var editing: EditTarget?

    /// The item being edited. New items join the list only when the editor is confirmed.
    private struct EditTarget: Identifiable {
        let item: MenuItem
        var isNew = false
        var id: UUID { item.id }
    }

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                PaneHeader(
                    title: "Menu Items",
                    subtitle: "Choose what appears when you right-click in Finder. Drag items to reorder them."
                ) {
                    AddItemMenu { item, openEditor in
                        if openEditor {
                            editing = EditTarget(item: item, isNew: true)
                        } else {
                            model.config.items.append(item)
                        }
                    }
                }
                List {
                    ForEach($model.config.items) { $item in
                        MenuItemRow(item: $item) {
                            editing = EditTarget(item: item)
                        } onRemove: {
                            remove(item.id)
                        }
                    }
                    .onMove { model.config.items.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.inset)
            }
            Divider()
            MenuPreviewPanel()
                .frame(width: 330)
        }
        .sheet(item: $editing) { target in
            MenuItemEditor(item: target.item, isNew: target.isNew) { updated in
                if let index = model.config.items.firstIndex(where: { $0.id == updated.id }) {
                    model.config.items[index] = updated
                } else {
                    model.config.items.append(updated)
                }
            } onRemove: {
                remove(target.id)
            }
        }
    }

    private func remove(_ id: UUID) {
        model.config.items.removeAll { $0.id == id }
    }
}

/// One row in the menu item list.
private struct MenuItemRow: View {
    @Binding var item: MenuItem
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Group {
            if item.isSeparator {
                separatorRow
            } else {
                itemRow
            }
        }
        .contextMenu {
            if !item.isSeparator {
                Button("Edit…", action: onEdit)
            }
            Button("Remove", role: .destructive, action: onRemove)
        }
    }

    private var itemRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                MenuItemIcon(item: item, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .fontWeight(.medium)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .opacity(item.isEnabled ? 1 : 0.5)
            Spacer(minLength: 8)
            ContextIcons(item: item)
            Button(action: onEdit) {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .help("Edit")
            .accessibilityLabel("Edit \(item.title)")
            Toggle("Show \(item.title)", isOn: $item.isEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
    }

    private var separatorRow: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(.separator)
                .frame(height: 1)
            Text("Separator")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Rectangle()
                .fill(.separator)
                .frame(height: 1)
            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .help("Remove separator")
            .accessibilityLabel("Remove separator")
        }
        .padding(.vertical, 2)
        .padding(.leading, 40)
    }

    private var detail: String {
        var text: String
        switch item.kind {
        case .builtin(let action):
            text = action.summary
        case .openWith(let app):
            text = switch app.target {
            case .automatic where KnownApps.isTerminal(bundleID: app.bundleID): "Opens the folder in \(app.appName)."
            case .folder: "Opens the enclosing folder in \(app.appName)."
            default: "Opens the selected items in \(app.appName)."
            }
        case .command(let command):
            text = command.script.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Empty script"
        case .separator:
            text = ""
        }
        let extensions = item.normalizedExtensions.sorted()
        if !extensions.isEmpty {
            text = "Only \(extensions.joined(separator: ", ")) files. " + text
        }
        return text
    }
}

/// Small icons showing where an item appears.
private struct ContextIcons: View {
    let item: MenuItem

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MenuContext.allCases) { context in
                let supported = item.kind.supportedContexts.contains(context)
                let active = item.effectiveContexts.contains(context)
                Image(systemName: context.symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(active ? AnyShapeStyle(.secondary) : AnyShapeStyle(.quaternary))
                    .opacity(supported ? 1 : 0)
                    .help(active ? "Shows on \(context.title.lowercased())" : "Hidden on \(context.title.lowercased())")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shows on " + item.effectiveContexts.map(\.title).sorted().joined(separator: ", "))
    }
}

/// The "Add Item" button and its menu.
private struct AddItemMenu: View {
    @Environment(AppModel.self) private var model
    /// Called with the new item and whether to open its editor right away.
    let onAdd: (MenuItem, Bool) -> Void

    var body: some View {
        Menu {
            Section("Open With") {
                ForEach(suggestedApps, id: \.appPath) { app in
                    Button {
                        onAdd(MenuItem(kind: .openWith(app: app)), false)
                    } label: {
                        Label {
                            Text(app.appName)
                        } icon: {
                            Image(nsImage: smallIcon(for: app.appPath))
                        }
                    }
                }
                Button("Choose App…") {
                    if let url = Pickers.application() {
                        onAdd(MenuItem(kind: .openWith(app: AppCatalog.makeApp(at: url))), false)
                    }
                }
            }
            Section {
                Button("Custom Command…") {
                    let command = CustomCommand(name: "New Command", script: #"echo "$@""#)
                    onAdd(MenuItem(kind: .command(command: command)), true)
                }
                Button("Separator") {
                    onAdd(.separator(), false)
                }
            }
            if !missingBuiltins.isEmpty {
                Section("Built-in Actions") {
                    ForEach(missingBuiltins) { action in
                        Button(action.title) {
                            var item = MenuItem.builtin(action)
                            item.isEnabled = true
                            onAdd(item, false)
                        }
                    }
                }
            }
        } label: {
            Label("Add Item", systemImage: "plus")
        }
        .fixedSize()
    }

    private var suggestedApps: [OpenWithApp] {
        let present = Set(model.config.items.compactMap { item -> String? in
            if case .openWith(let app) = item.kind { app.appPath } else { nil }
        })
        return AppCatalog.installed().filter { !present.contains($0.appPath) }
    }

    private var missingBuiltins: [BuiltinAction] {
        let present = Set(model.config.items.compactMap(\.builtinAction))
        return BuiltinAction.allCases.filter { !present.contains($0) }
    }

    private func smallIcon(for path: String) -> NSImage {
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}
