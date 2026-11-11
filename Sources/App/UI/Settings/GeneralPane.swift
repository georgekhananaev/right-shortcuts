import AppKit
import RightShortcutsCore
import SwiftUI

/// Startup, appearance and maintenance settings.
struct GeneralPane: View {
    @Environment(AppModel.self) private var model
    @Environment(ExtensionController.self) private var extensionController
    @Environment(LoginItemController.self) private var loginItem
    @Environment(AccessController.self) private var access
    @State private var isConfirmingReset = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            PaneHeader(title: "General", subtitle: "How Right Shortcuts starts, looks and behaves.")
            Form {
                Section("Startup") {
                    Toggle("Open at login", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) }))
                    if loginItem.needsApproval {
                        LabeledContent("Allow Right Shortcuts in Login Items to finish turning this on.") {
                            Button("Open Login Items…") { loginItem.openSystemSettings() }
                        }
                        .foregroundStyle(.orange)
                    }
                    if let error = loginItem.lastError {
                        Text(error).foregroundStyle(.red)
                    }
                    Toggle(isOn: $model.showMenuBarIcon) {
                        Text("Show in the menu bar")
                        Text("When it’s hidden, open Right Shortcuts from Applications to get back here.")
                    }
                }

                Section("Finder menu") {
                    Picker("Layout", selection: $model.config.menuLayout) {
                        ForEach(MenuLayout.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Show icons next to items", isOn: $model.config.showIcons)
                    Toggle("Confirm each action with a short message", isOn: $model.config.showConfirmations)
                }

                Section("Finder extension") {
                    LabeledContent("Status") {
                        Label(extensionController.isEnabled ? "On" : "Off",
                              systemImage: extensionController.isEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(extensionController.isEnabled ? .green : .red)
                    }
                    Button("Open Extension Settings…") { extensionController.openSystemSettings() }
                }

                Section {
                    LabeledContent("Command helper") {
                        Label(helperStatus.text, systemImage: helperStatus.symbol)
                            .foregroundStyle(helperStatus.color)
                    }
                    Button(access.helperState == .missing ? "Install Helper…" : "Install Helper Again…") {
                        access.installHelperFromSettings()
                    }
                    if access.helperState != .missing, let folder = access.scriptsFolder {
                        Button("Show Helper in Finder") { NSWorkspace.shared.open(folder) }
                    }
                } header: {
                    Text("Custom commands")
                } footer: {
                    FooterText("Your shell commands run through a small script that macOS keeps in a folder only you can add to. Right Shortcuts asks before putting it there.")
                }

                Section {
                    Button("Show Settings File in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([SharedContainer.configURL])
                    }
                    Button("Export Diagnostics…") {
                        Diagnostics.export(model: model, access: access, extensionIsOn: extensionController.isEnabled)
                    }
                    Button("Restore Default Menu…", role: .destructive) { isConfirmingReset = true }
                } header: {
                    Text("Maintenance")
                } footer: {
                    if let error = model.saveError {
                        FooterText("Settings couldn’t be saved: \(error)").foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .confirmationDialog("Restore the default menu?", isPresented: $isConfirmingReset) {
            Button("Restore Defaults", role: .destructive) { model.resetToDefaults() }
        } message: {
            Text("Your menu items, templates, folders and custom commands are replaced with the originals.")
        }
        .task { loginItem.refresh() }
    }

    private var helperStatus: (text: String, symbol: String, color: Color) {
        switch access.helperState {
        case .installed: ("Installed", "checkmark.circle.fill", .green)
        case .outdated: ("Needs an update", "exclamationmark.triangle.fill", .orange)
        case .missing: ("Not installed", "minus.circle.fill", .secondary)
        }
    }
}
