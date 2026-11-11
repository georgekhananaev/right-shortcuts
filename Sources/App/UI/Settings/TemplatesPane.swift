import RightShortcutsActions
import RightShortcutsCore
import SwiftUI

/// The file types offered in the New File submenu.
struct TemplatesPane: View {
    @Environment(AppModel.self) private var model
    @State private var editing: EditTarget?
    @State private var importError: String?

    private struct EditTarget: Identifiable {
        let id: String
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            PaneHeader(
                title: "New File",
                subtitle: "Pick the kinds of files you can create from the New File submenu. Drag to reorder."
            ) {
                Button {
                    addTemplate()
                } label: {
                    Label("Add Template…", systemImage: "plus")
                }
            }

            HStack(spacing: 24) {
                Toggle("Ask for a name first", isOn: $model.config.askForFileName)
                Toggle("Open the file after creating it", isOn: $model.config.openCreatedFile)
                Spacer()
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal, 24)
            .padding(.bottom, 10)

            if let importError {
                Label(importError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }

            List {
                ForEach($model.config.templates) { $template in
                    TemplateRow(template: $template) {
                        editing = EditTarget(id: template.id)
                    }
                    .contextMenu {
                        Button("Edit…") { editing = EditTarget(id: template.id) }
                        if !template.isBuiltin {
                            Button("Remove", role: .destructive) { remove(template.id) }
                        }
                    }
                }
                .onMove { model.config.templates.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.inset)

            Text("To create Pages, Numbers or Keynote files, save an empty document and add it with Add Template.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
        }
        .sheet(item: $editing) { target in
            if let template = model.config.templates.first(where: { $0.id == target.id }) {
                TemplateEditor(template: template) { updated in
                    if let index = model.config.templates.firstIndex(where: { $0.id == updated.id }) {
                        model.config.templates[index] = updated
                    }
                } onRemove: {
                    remove(target.id)
                }
            }
        }
    }

    private func addTemplate() {
        guard let url = Pickers.templateFile() else { return }
        do {
            let template = try TemplateWriter.importTemplate(from: url, into: SharedContainer.templatesURL)
            model.config.templates.append(template)
            importError = nil
            editing = EditTarget(id: template.id)
        } catch {
            importError = "Couldn’t add “\(url.lastPathComponent)”: \(error.localizedDescription)"
        }
    }

    private func remove(_ id: String) {
        guard let template = model.config.templates.first(where: { $0.id == id }), !template.isBuiltin else { return }
        TemplateWriter.removeStoredFile(of: template, in: SharedContainer.templatesURL)
        model.config.templates.removeAll { $0.id == id }
    }
}

private struct TemplateRow: View {
    @Binding var template: FileTemplate
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                FileTypeIcon(fileExtension: template.fileExtension, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .fontWeight(.medium)
                    Text("Creates \(template.defaultFileName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .opacity(template.isEnabled ? 1 : 0.5)
            Spacer()
            Button(action: onEdit) {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .help("Edit")
            .accessibilityLabel("Edit \(template.name)")
            Toggle("Show \(template.name)", isOn: $template.isEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
    }
}

/// Edits a template's name, default file name and, for text templates, its content.
private struct TemplateEditor: View {
    @State private var draft: FileTemplate
    let onSave: (FileTemplate) -> Void
    let onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss

    init(template: FileTemplate, onSave: @escaping (FileTemplate) -> Void, onRemove: @escaping () -> Void) {
        _draft = State(initialValue: template)
        self.onSave = onSave
        self.onRemove = onRemove
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                FileTypeIcon(fileExtension: draft.fileExtension, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.name.isEmpty ? "Template" : draft.name)
                        .font(.system(size: 18, weight: .semibold))
                    Text("New files are named \(draft.defaultFileName)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)

            Form {
                Section {
                    TextField("Menu title", text: $draft.name)
                    TextField("File name", text: $draft.baseName)
                    if draft.isTextBased {
                        TextField("Extension", text: $draft.fileExtension)
                    } else {
                        LabeledContent("Extension", value: draft.fileExtension.isEmpty ? "None" : draft.fileExtension)
                    }
                    Toggle("Make the file executable", isOn: $draft.makesExecutable)
                }
                if case .text(let content) = draft.source {
                    Section("Starts with") {
                        TextEditor(text: Binding(
                            get: { content },
                            set: { draft.source = .text(content: $0) }
                        ))
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 140)
                        .accessibilityLabel("Template content")
                    }
                }
                Section("Icon in menu") {
                    SymbolPicker(selection: symbolBinding, defaultSymbol: "doc")
                }
            }
            .formStyle(.grouped)

            HStack {
                if !draft.isBuiltin {
                    Button("Remove Template", role: .destructive) {
                        onRemove()
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Done") {
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isInvalid)
            }
            .padding(16)
        }
        .frame(width: 520, height: 540)
    }

    private var isInvalid: Bool {
        draft.name.trimmingCharacters(in: .whitespaces).isEmpty
            || FileNaming.problem(with: draft.defaultFileName) != nil
    }

    private var symbolBinding: Binding<String?> {
        Binding(
            get: { draft.symbol == "doc" ? nil : draft.symbol },
            set: { draft.symbol = $0 ?? "doc" }
        )
    }
}
