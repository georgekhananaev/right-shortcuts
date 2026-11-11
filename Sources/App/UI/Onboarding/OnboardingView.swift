import AppKit
import RightShortcutsCore
import SwiftUI

/// First-run setup: turn on the extension, allow file access, choose where the menu shows, finish.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(ExtensionController.self) private var extensionController
    @Environment(LoginItemController.self) private var loginItem
    @Environment(AccessController.self) private var access
    let onFinish: () -> Void

    @State private var step: Step = .welcome

    enum Step: Int, CaseIterable {
        case welcome
        case finderExtension
        case fileAccess
        case coverage
        case finish
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: welcome
                case .finderExtension: extensionStep
                case .fileAccess: accessStep
                case .coverage: coverageStep
                case .finish: finishStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 48)
            .padding(.top, 36)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .id(step)

            bottomBar
        }
        .frame(width: 620, height: 540)
        .tint(.brand)
        .task {
            while !Task.isCancelled {
                extensionController.refresh()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)
            Text("Welcome to Right Shortcuts")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text("Put the actions you use most into Finder’s right-click menu, and leave out the rest.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            VStack(alignment: .leading, spacing: 14) {
                feature("doc.badge.plus", .orange, "New files in a click", "Text, Markdown, Word, Excel, scripts or your own templates.")
                feature("terminal", .indigo, "Open in your tools", "Terminal, VS Code, Cursor, Zed or any app you like.")
                feature("doc.on.clipboard", .blue, "Copy, move and more", "Copy paths, send to favorite folders, hide items or run scripts.")
            }
            .padding(.top, 10)
        }
    }

    private var extensionStep: some View {
        VStack(spacing: 18) {
            IconTile(symbol: "puzzlepiece.extension.fill", color: .brand, size: 72)
            Text("Turn on the Finder extension")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Finder only shows Right Shortcuts once its extension is on. The extension runs in a sandbox and only draws the menu. Right Shortcuts does the work when you pick an item.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .fixedSize(horizontal: false, vertical: true)

            if extensionController.isEnabled {
                Label("The extension is on", systemImage: "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.top, 8)
            } else {
                Button {
                    extensionController.openSystemSettings()
                } label: {
                    Text("Open System Settings").frame(minWidth: 180)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
                Text("Switch on Right Shortcuts in the list of Finder extensions, then come back here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var accessStep: some View {
        VStack(spacing: 16) {
            IconTile(symbol: "lock.open.fill", color: .orange, size: 72)
            Text("Allow access to your files")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("macOS keeps every app out of your files until you say otherwise. Right Shortcuts only touches files when you pick one of its menu items.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 470)
                .fixedSize(horizontal: false, vertical: true)

            if access.folders.isEmpty {
                Button {
                    access.allowEverywhere()
                } label: {
                    Text("Allow Every Folder…").frame(minWidth: 200)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .padding(.top, 6)
                Text("Choose your disk in the window that opens. One step, and it works on every folder and drive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Choose Specific Folders…") { access.allowAnotherFolder() }
                    .buttonStyle(.link)
                Text("Or skip this. Right Shortcuts then asks for each folder the first time you use it there.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            } else {
                Label(access.worksEverywhere ? "Right Shortcuts can work in every folder" : allowedSummary,
                      systemImage: "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.green)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                if !access.worksEverywhere {
                    Button("Allow Another Folder…") { access.allowAnotherFolder() }
                        .buttonStyle(.link)
                    Button("Allow Every Folder Instead…") { access.allowEverywhere() }
                        .buttonStyle(.link)
                }
            }
        }
    }

    private var allowedSummary: String {
        let names = access.folders.map { FileManager.default.displayName(atPath: $0) }
        return "Allowed: " + names.joined(separator: ", ")
    }

    private var coverageStep: some View {
        @Bindable var model = model
        return VStack(spacing: 18) {
            Text("Where should the menu appear?")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("You can change this anytime in Folders.")
                .foregroundStyle(.secondary)
            HStack(spacing: 14) {
                coverageCard(.everywhere, symbol: "globe", title: "Everywhere",
                             detail: "Every folder, the desktop and all your drives.")
                coverageCard(.selectedFolders, symbol: "folder.badge.plus", title: "Only some folders",
                             detail: "Just the folders you pick, and the folders inside them.")
            }
            .padding(.top, 8)

            if model.config.coverage == .selectedFolders {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.config.watchedFolders, id: \.self) { path in
                        FolderRow(path: path) { model.config.watchedFolders.removeAll { $0 == path } }
                    }
                    Button {
                        let picked = Pickers.folders(message: "Choose folders where the menu should appear.")
                        let existing = Set(model.config.watchedFolders)
                        model.config.watchedFolders += picked.filter { !existing.contains($0) }
                    } label: {
                        Label("Add Folder…", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
                .frame(maxWidth: 440, alignment: .leading)
            }
        }
    }

    private var finishStep: some View {
        @Bindable var model = model
        return VStack(spacing: 18) {
            IconTile(symbol: "checkmark", color: .green, size: 72)
            Text("You’re all set")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text("Right-click any file, folder or empty space in Finder to try it.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 12) {
                switchRow("Open Right Shortcuts at login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))
                Divider()
                switchRow("Show Right Shortcuts in the menu bar", isOn: $model.showMenuBarIcon)
            }
            .padding(18)
            .frame(maxWidth: 420, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.top, 6)
            Text("Next, pick your menu items. The preview shows exactly what Finder will display.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
    }

    // MARK: - Pieces

    private func switchRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private var bottomBar: some View {
        HStack {
            if step != .welcome {
                Button("Back") { move(by: -1) }
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
            HStack(spacing: 7) {
                ForEach(Step.allCases, id: \.self) { item in
                    Circle()
                        .fill(item == step ? Color.brand : Color.primary.opacity(0.18))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
            Spacer()
            Button(primaryTitle) {
                if step == .finish {
                    onFinish()
                } else {
                    move(by: 1)
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(step == .coverage && model.config.coverage == .selectedFolders && model.config.watchedFolders.isEmpty)
        }
        .padding(20)
        .background(.bar)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: "Get Started"
        case .finderExtension: extensionController.isEnabled ? "Continue" : "Skip for Now"
        case .fileAccess: access.folders.isEmpty ? "Ask When Needed" : "Continue"
        case .coverage: "Continue"
        case .finish: "Choose Menu Items"
        }
    }

    private func move(by offset: Int) {
        guard let next = Step(rawValue: step.rawValue + offset) else { return }
        withAnimation(.snappy(duration: 0.3)) { step = next }
    }

    private func feature(_ symbol: String, _ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 14) {
            IconTile(symbol: symbol, color: color, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func coverageCard(_ coverage: Coverage, symbol: String, title: String, detail: String) -> some View {
        let isSelected = model.config.coverage == coverage
        return Button {
            model.config.coverage = coverage
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(isSelected ? Color.brand : .secondary)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.brand : Color.secondary)
                }
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: 220, height: 140, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.brand.opacity(0.1) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Color.brand : Color.primary.opacity(0.1), lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
