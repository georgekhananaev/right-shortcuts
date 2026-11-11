import RightShortcutsCore
import SwiftUI

/// Edits one menu item. Changes apply when the user clicks Done.
struct MenuItemEditor: View {
    @State private var draft: MenuItem
    let isNew: Bool
    let onSave: (MenuItem) -> Void
    let onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AccessController.self) private var access

    init(item: MenuItem, isNew: Bool, onSave: @escaping (MenuItem) -> Void, onRemove: @escaping () -> Void) {
        _draft = State(initialValue: item)
        self.isNew = isNew
        self.onSave = onSave
        self.onRemove = onRemove
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                contextsSection
                if draft.kind.supportedContexts.contains(.files) {
                    fileTypesSection
                }
                switch draft.kind {
                case .openWith(let app):
                    appSection(app)
                case .command(let command):
                    commandSection(command)
                case .builtin, .separator:
                    EmptyView()
                }
                if case .openWith = draft.kind {} else {
                    Section("Icon") {
                        SymbolPicker(selection: $draft.customSymbol, defaultSymbol: draft.kind.defaultSymbol)
                    }
                }
            }
            .formStyle(.grouped)
            footer
        }
        .frame(width: 540, height: 540)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 14) {
            MenuItemIcon(item: draft, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                TextField("Title", text: titleBinding, prompt: Text(draft.kind.defaultTitle))
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .semibold))
                Text(kindDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
    }

    private var contextsSection: some View {
        Section {
            ForEach(MenuContext.allCases.filter { draft.kind.supportedContexts.contains($0) }) { context in
                Toggle(isOn: contextBinding(context)) {
                    Label {
                        Text(context.title)
                        Text(context.explanation)
                    } icon: {
                        Image(systemName: context.symbol)
                    }
                }
            }
        } header: {
            Text("Show for")
        }
    }

    private var fileTypesSection: some View {
        Section {
            TextField("File types", text: extensionsBinding, prompt: Text("Any file"))
        } header: {
            Text("Only for these file types")
        } footer: {
            FooterText("Separate extensions with commas, like png, jpg, heic. Leave empty to show for every file.")
        }
    }

    private func appSection(_ app: OpenWithApp) -> some View {
        Section("App") {
            LabeledContent("App") {
                HStack(spacing: 8) {
                    AppIconView(path: app.appPath, size: 20)
                    Text(app.appName)
                    Button("Change…") {
                        if let url = Pickers.application() {
                            var updated = AppCatalog.makeApp(at: url)
                            updated.target = app.target
                            draft.kind = .openWith(app: updated)
                        }
                    }
                }
            }
            Picker("Open", selection: Binding(
                get: { app.target },
                set: { target in
                    var updated = app
                    updated.target = target
                    draft.kind = .openWith(app: updated)
                }
            )) {
                ForEach(OpenTarget.allCases) { Text($0.title).tag($0) }
            }
            if app.target == .automatic {
                Text(KnownApps.isTerminal(bundleID: app.bundleID)
                     ? "\(app.appName) is a terminal, so it gets the folder. Selected files open their enclosing folder."
                     : "\(app.appName) gets the selected items, or the current folder when nothing is selected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func commandSection(_ command: CustomCommand) -> some View {
        Section {
            TextEditor(text: Binding(
                get: { command.script },
                set: { script in
                    var updated = command
                    updated.script = script
                    draft.kind = .command(command: updated)
                }
            ))
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 120)
            .accessibilityLabel("Script")
            Picker("Run", selection: Binding(
                get: { command.runMode },
                set: { mode in
                    var updated = command
                    updated.runMode = mode
                    draft.kind = .command(command: updated)
                }
            )) {
                ForEach(RunMode.allCases) { Text($0.title).tag($0) }
            }
            if access.helperState != .installed {
                LabeledContent {
                    Button(access.helperState == .outdated ? "Update…" : "Install…") { access.installHelperFromSettings() }
                } label: {
                    Label("Commands need a small helper installed once before they can run.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Script")
        } footer: {
            FooterText("Runs with zsh in the current folder. Selected items arrive as \"$@\". $RS_DIR holds the folder and $RS_PATHS lists every path on its own line.")
        }
    }

    private var footer: some View {
        HStack {
            if !isNew {
                Button("Remove Item", role: .destructive) {
                    onRemove()
                    dismiss()
                }
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(isNew ? "Add Item" : "Done") {
                onSave(draft)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(draft.effectiveContexts.isEmpty)
        }
        .padding(16)
    }

    // MARK: - Bindings

    private var kindDescription: String {
        switch draft.kind {
        case .builtin(let action): action.summary
        case .openWith(let app): "Opens items with \(app.appName)."
        case .command: "Runs your own shell script."
        case .separator: "A line between groups of items."
        }
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: {
                if case .command(let command) = draft.kind { return command.name }
                return draft.customTitle ?? ""
            },
            set: { title in
                if case .command(var command) = draft.kind {
                    command.name = title
                    draft.kind = .command(command: command)
                } else {
                    draft.customTitle = title.isEmpty ? nil : title
                }
            }
        )
    }

    private func contextBinding(_ context: MenuContext) -> Binding<Bool> {
        Binding(
            get: { draft.contexts.contains(context) },
            set: { isOn in
                if isOn { draft.contexts.insert(context) } else { draft.contexts.remove(context) }
            }
        )
    }

    private var extensionsBinding: Binding<String> {
        Binding(
            get: { draft.fileExtensions.joined(separator: ", ") },
            set: { text in
                draft.fileExtensions = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            }
        )
    }
}

/// A grid of SF Symbols to pick a menu icon from.
struct SymbolPicker: View {
    @Binding var selection: String?
    let defaultSymbol: String

    private static let symbols = [
        "terminal", "chevron.left.forwardslash.chevron.right", "hammer", "wrench.and.screwdriver", "gearshape",
        "bolt", "sparkles", "wand.and.stars", "star", "heart", "flag", "tag", "bookmark", "paperplane",
        "tray.and.arrow.down", "arrow.down.circle", "arrow.up.circle", "arrow.triangle.2.circlepath", "link",
        "doc", "doc.text", "doc.on.doc", "folder", "archivebox", "externaldrive", "server.rack", "globe",
        "photo", "film", "music.note", "waveform", "number.square", "lock", "key", "eye", "trash",
    ]

    private let columns = Array(repeating: GridItem(.fixed(34), spacing: 6), count: 9)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            cell(symbol: defaultSymbol, value: nil, label: "Default icon")
            ForEach(Self.symbols.filter { $0 != defaultSymbol }, id: \.self) { symbol in
                cell(symbol: symbol, value: symbol, label: symbol)
            }
        }
        .padding(.vertical, 4)
    }

    private func cell(symbol: String, value: String?, label: String) -> some View {
        let isSelected = selection == value || (value == nil && selection?.isEmpty != false)
        return Button {
            selection = value
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .frame(width: 34, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? Color.brand.opacity(0.18) : Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(isSelected ? Color.brand : .clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
