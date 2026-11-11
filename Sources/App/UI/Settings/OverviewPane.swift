import AppKit
import RightShortcutsCore
import SwiftUI

/// Status at a glance and the few things needed to get going.
struct OverviewPane: View {
    @Environment(AppModel.self) private var model
    @Environment(ExtensionController.self) private var extensionController
    @Environment(LoginItemController.self) private var loginItem
    @Environment(AccessController.self) private var access
    @State private var cloudFolders: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            hero
            Form {
                Section("Setup") {
                    extensionRow
                    accessRow
                    if needsCommandHelper { helperRow }
                    Toggle(isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) })) {
                        rowLabel("Open at login", detail: "Keeps your menu ready after you restart.",
                                 symbol: "power", color: .green)
                    }
                    LabeledContent {
                        Button("Change…") { model.selectedPane = .locations }
                    } label: {
                        rowLabel("Menu appears in", detail: coverageText, symbol: "folder.fill", color: .teal)
                    }
                    if !cloudFolders.isEmpty {
                        rowLabel("\(cloudFolders.formatted(.list(type: .and))) \(cloudFolders.count == 1 ? "is" : "are") in iCloud Drive",
                                 detail: "Finder doesn’t show menus from extensions in cloud-synced folders, so your menu won’t appear there. It works everywhere else.",
                                 symbol: "icloud.fill", color: .cyan)
                    }
                }

                Section("Your menu") {
                    summaryRow("Menu items", value: "\(enabledItemCount) on", symbol: "contextualmenu.and.cursorarrow",
                               color: .blue, pane: .menu)
                    summaryRow("File templates", value: "\(model.config.templates.filter(\.isEnabled).count) on",
                               symbol: "doc.badge.plus", color: .orange, pane: .templates)
                    summaryRow("Quick folders", value: "\(model.config.quickFolders.count)",
                               symbol: "star.fill", color: .yellow, pane: .locations)
                }

                Section {
                    rowLabel("Add a toolbar button",
                             detail: "Right-click Finder’s toolbar, choose Customize Toolbar, and drag Right Shortcuts in.",
                             symbol: "menubar.rectangle", color: .gray)
                }
            }
            .formStyle(.grouped)
        }
        .task {
            while !Task.isCancelled {
                extensionController.refresh()
                loginItem.refresh()
                cloudFolders = AccessController.cloudSyncedHomeFolders()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var hero: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(AppIdentity.displayName)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(statusText)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle("Show menu in Finder", isOn: Binding(
                get: { !model.config.isPaused },
                set: { model.config.isPaused = !$0 }
            ))
            .toggleStyle(.switch)
            .controlSize(.large)
            .labelsHidden()
            .help(model.config.isPaused ? "Resume" : "Pause")
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 4)
    }

    private var extensionRow: some View {
        LabeledContent {
            if extensionController.isEnabled {
                HStack(spacing: 10) {
                    Label("On", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Button("Manage…") { extensionController.openSystemSettings() }
                }
            } else {
                Button("Turn On…") { extensionController.openSystemSettings() }
                    .buttonStyle(.borderedProminent)
            }
        } label: {
            rowLabel("Finder extension", detail: "Lets Finder show your menu.",
                     symbol: "puzzlepiece.extension.fill", color: .brand)
        }
    }

    private var accessRow: some View {
        LabeledContent {
            if access.worksEverywhere {
                Label("Every folder", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if access.folders.isEmpty {
                Button("Allow…") { access.allowEverywhere() }
                    .buttonStyle(.borderedProminent)
            } else {
                HStack(spacing: 10) {
                    Text(access.folders.count == 1 ? "1 folder" : "\(access.folders.count) folders")
                        .foregroundStyle(.secondary)
                    Button("Change…") { model.selectedPane = .locations }
                }
            }
        } label: {
            rowLabel("File access", detail: "Lets actions create, copy, move and delete where you right-click.",
                     symbol: "lock.open.fill", color: .orange)
        }
    }

    private var helperRow: some View {
        LabeledContent {
            Button(access.helperState == .outdated ? "Update…" : "Install…") { access.installHelperFromSettings() }
                .buttonStyle(.borderedProminent)
        } label: {
            rowLabel("Command helper", detail: "Your custom commands need it before they can run.",
                     symbol: "terminal.fill", color: .indigo)
        }
    }

    /// True while a custom command is switched on but nothing is installed to run it.
    private var needsCommandHelper: Bool {
        access.helperState != .installed && model.config.items.contains { item in
            if case .command = item.kind { item.isEnabled } else { false }
        }
    }

    private func rowLabel(_ title: String, detail: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, color: color, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func summaryRow(_ title: String, value: String, symbol: String, color: Color, pane: SettingsPane) -> some View {
        Button {
            model.selectedPane = pane
        } label: {
            HStack(spacing: 12) {
                IconTile(symbol: symbol, color: color, size: 28)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Text(value)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var enabledItemCount: Int {
        model.config.items.filter { $0.isEnabled && !$0.isSeparator }.count
    }

    private var coverageText: String {
        switch model.config.coverage {
        case .everywhere:
            return "Every folder and drive on this Mac."
        case .selectedFolders:
            let count = model.config.watchedFolders.count
            return count == 1 ? "1 folder you chose." : "\(count) folders you chose."
        }
    }

    private var statusText: String {
        if !extensionController.isEnabled {
            return "The Finder extension is off. Turn it on below to see your menu in Finder."
        }
        if model.config.isPaused {
            return "Paused. Your menu is hidden in Finder until you switch it back on."
        }
        if access.folders.isEmpty {
            return "Your menu is showing. Allow file access below so actions like New File and Copy To can do their work."
        }
        switch model.config.coverage {
        case .everywhere:
            return "Your menu is ready in every Finder window."
        case .selectedFolders where model.config.watchedFolders.isEmpty:
            return "Add a folder in Folders so the menu has somewhere to appear."
        case .selectedFolders:
            return "Your menu is ready in the folders you chose."
        }
    }
}
