import RightShortcutsCore
import SwiftUI

/// Where the app may work, where the menu appears and never appears, and the quick folders.
struct LocationsPane: View {
    @Environment(AppModel.self) private var model
    @Environment(AccessController.self) private var access
    @State private var cloudFolders: [String] = []

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            PaneHeader(title: "Folders", subtitle: "Decide where Right Shortcuts may work, where your menu appears and which folders Copy To and Move To offer.")
            Form {
                accessSection

                Section {
                    Picker("Show the menu", selection: $model.config.coverage) {
                        Text("Everywhere on this Mac").tag(Coverage.everywhere)
                        Text("Only in folders I choose").tag(Coverage.selectedFolders)
                    }
                    .pickerStyle(.radioGroup)

                    if model.config.coverage == .selectedFolders {
                        ForEach(model.config.watchedFolders, id: \.self) { path in
                            FolderRow(path: path) { model.config.watchedFolders.removeAll { $0 == path } }
                        }
                        if model.config.watchedFolders.isEmpty {
                            Text("Add at least one folder. The menu also works in every folder inside it.")
                                .foregroundStyle(.secondary)
                        }
                        addButton("Add Folder…") {
                            add(Pickers.folders(message: "Choose folders where the menu should appear."),
                                to: \.watchedFolders)
                        }
                    }
                } header: {
                    Text("Where the menu appears")
                } footer: {
                    if model.config.coverage == .everywhere {
                        FooterText(everywhereNote)
                    }
                }

                Section {
                    ForEach(model.config.excludedFolders, id: \.self) { path in
                        FolderRow(path: path) { model.config.excludedFolders.removeAll { $0 == path } }
                    }
                    if model.config.excludedFolders.isEmpty {
                        Text("No exceptions.")
                            .foregroundStyle(.secondary)
                    }
                    addButton("Add Exception…") {
                        add(Pickers.folders(message: "Choose folders where the menu should never appear."),
                            to: \.excludedFolders)
                    }
                } header: {
                    Text("Never show the menu in")
                } footer: {
                    FooterText("The menu stays hidden in these folders and everything inside them.")
                }

                Section {
                    ForEach(Array(model.config.quickFolders.enumerated()), id: \.element.id) { index, folder in
                        FolderRow(path: folder.path, name: folder.name) {
                            model.config.quickFolders.removeAll { $0.id == folder.id }
                        }
                        .contextMenu {
                            Button("Move Up") { model.config.quickFolders.shift(at: index, by: -1) }
                                .disabled(index == 0)
                            Button("Move Down") { model.config.quickFolders.shift(at: index, by: 1) }
                                .disabled(index == model.config.quickFolders.count - 1)
                        }
                    }
                    if model.config.quickFolders.isEmpty {
                        Text("No quick folders. Copy To and Move To will only offer Choose Folder.")
                            .foregroundStyle(.secondary)
                    }
                    addButton("Add Quick Folder…") {
                        let existing = Set(model.config.quickFolders.map(\.path))
                        let picked = Pickers.folders(message: "Choose folders to offer in Copy To, Move To and Go To.")
                        // Picking a folder here is permission enough to copy and move into it later.
                        picked.forEach { access.remember(URL(fileURLWithPath: $0, isDirectory: true)) }
                        model.config.quickFolders += picked.filter { !existing.contains($0) }.map { QuickFolder(path: $0) }
                    }
                } header: {
                    Text("Quick folders")
                } footer: {
                    FooterText("Offered in Copy To, Move To and Go To. Right-click a folder to reorder it.")
                }
            }
            .formStyle(.grouped)
        }
        .task { cloudFolders = AccessController.cloudSyncedHomeFolders() }
    }

    private var accessSection: some View {
        Section {
            ForEach(access.folders, id: \.self) { path in
                let name = FileManager.default.displayName(atPath: path)
                FolderRow(path: path, name: access.unavailableFolders.contains(path) ? "\(name) (not connected)" : name) {
                    access.revoke(path)
                }
            }
            if access.folders.isEmpty {
                Text("Nothing allowed yet. Right Shortcuts asks the first time an action needs your files.")
                    .foregroundStyle(.secondary)
            }
            // With the whole disk allowed there is nothing left to add.
            if !access.worksEverywhere {
                addButton("Allow Every Folder…") { access.allowEverywhere() }
                addButton("Allow a Folder…") { access.allowAnotherFolder() }
            }
        } header: {
            Text("Where Right Shortcuts can work")
        } footer: {
            FooterText("macOS asks before any app may use your files. Allowing your disk covers every folder and drive. Only copying a path or a name never needs this.")
        }
    }

    private var everywhereNote: String {
        let base = "Includes external drives and network volumes. Finder doesn’t show menus from extensions in iCloud Drive or other cloud-synced folders"
        guard !cloudFolders.isEmpty else { return base + "." }
        return base + ", which on this Mac includes \(cloudFolders.formatted(.list(type: .and)))."
    }

    private func addButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "plus")
        }
        .buttonStyle(.borderless)
    }

    private func add(_ paths: [String], to keyPath: WritableKeyPath<AppConfig, [String]>) {
        let existing = Set(model.config[keyPath: keyPath])
        model.config[keyPath: keyPath] += paths.filter { !existing.contains($0) }
    }
}
