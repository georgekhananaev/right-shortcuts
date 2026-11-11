import AppKit
import RightShortcutsCore
import SwiftUI
import UniformTypeIdentifiers

extension Color {
    /// The app's accent: a cursor-blue violet taken from the app icon.
    static let brand = Color(red: 0.416, green: 0.353, blue: 0.976)
}

/// A rounded square with a white symbol, in the style of System Settings.
struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The real icon of an app on disk.
struct AppIconView: View {
    let path: String
    var size: CGFloat = 24

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The system icon for a file type, like the one Finder shows.
struct FileTypeIcon: View {
    let fileExtension: String
    var size: CGFloat = 24

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: fileExtension) ?? .data))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The icon for a menu item: the app's own icon for "Open in …", otherwise a tinted tile.
struct MenuItemIcon: View {
    let item: MenuItem
    var size: CGFloat = 28

    var body: some View {
        if case .openWith(let app) = item.kind {
            AppIconView(path: app.appPath, size: size)
        } else {
            IconTile(symbol: item.symbol, color: item.tint, size: size)
        }
    }
}

extension MenuItem {
    var tint: Color {
        switch kind {
        case .builtin(let action):
            switch action {
            case .newFile: .orange
            case .copyPath, .copyName, .copyPathAs, .copyContents: .blue
            case .copyTo, .moveTo, .goTo: .teal
            case .makeExecutable: .green
            case .hide, .unhide: .gray
            case .airDrop: .cyan
            case .deletePermanently: .red
            }
        case .command: .indigo
        case .openWith, .separator: .secondary
        }
    }
}

/// Title, explanation and an optional trailing control at the top of a pane.
struct PaneHeader<Accessory: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            accessory
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }
}

extension PaneHeader where Accessory == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// A folder shown with its icon, name and path.
struct FolderRow: View {
    let path: String
    var name: String?
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(path: path, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(name ?? (path as NSString).lastPathComponent)
                Text(UserHome.abbreviate(path))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove")
            .accessibilityLabel("Remove \(name ?? (path as NSString).lastPathComponent)")
        }
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
            Button("Remove", role: .destructive, action: onRemove)
        }
    }
}

@MainActor
enum Pickers {
    /// Pickers start in the home folder instead of wherever the previous one ended up.
    private static var home: URL { URL(fileURLWithPath: UserHome.path, isDirectory: true) }

    /// Asks for one or more folders.
    static func folders(message: String) -> [String] {
        let panel = Panels.folderPicker(message: message, prompt: "Add", startingAt: home,
                                        allowsMultiple: true, canCreateFolders: true)
        return panel.runModal() == .OK ? panel.urls.map(\.path) : []
    }

    /// Asks for an application.
    static func application() -> URL? {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose an app to open files and folders with."
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Asks for any file to use as a template.
    static func templateFile() -> URL? {
        let panel = NSOpenPanel()
        panel.directoryURL = home
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.message = "Choose a file. New files will start as a copy of it."
        panel.prompt = "Add Template"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Section footer text, aligned with the rows above it.
struct FooterText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .multilineTextAlignment(.leading)
            .padding(.leading, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension Array {
    /// Moves the element at `index` one step up or down, if possible.
    mutating func shift(at index: Int, by offset: Int) {
        let target = index + offset
        guard indices.contains(index), indices.contains(target) else { return }
        swapAt(index, target)
    }
}
