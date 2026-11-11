import AppKit
import RightShortcutsCore
import SwiftUI

/// Questions asked right after a Finder click: a file name or a delete confirmation.
@MainActor
enum Prompts {
    /// - Returns: The chosen file name including extension, or nil if cancelled.
    static func fileName(for template: FileTemplate, in directory: URL, suggestedName: String) async -> String? {
        await PromptPresenter.present(dismissValue: nil) { finish in
            NamePromptView(template: template, directory: directory, name: suggestedName, onFinish: finish)
        }
    }

    static func confirmPermanentDeletion(of paths: [String]) async -> Bool {
        await PromptPresenter.present(dismissValue: false) { finish in
            DeletePromptView(names: paths.map { ($0 as NSString).lastPathComponent }, onFinish: finish)
        }
    }
}

/// Shows SwiftUI content in a floating panel that takes typing without activating the app.
/// macOS won't let a background app take focus from Finder, and it doesn't need to.
/// One prompt shows at a time: a newer click closes the prompt of an older one, as if cancelled.
@MainActor
private enum PromptPresenter {
    private static var dismissActive: (() -> Void)?

    static func present<Result: Sendable, Content: View>(
        dismissValue: Result,
        content: (_ finish: @escaping (Result) -> Void) -> Content
    ) async -> Result {
        dismissActive?()
        let panel = PromptPanel()
        return await withCheckedContinuation { continuation in
            var isFinished = false
            let finish: (Result) -> Void = { value in
                guard !isFinished else { return }
                isFinished = true
                panel.orderOut(nil)
                // The content holds this closure, which holds the panel; release it once the event is done.
                Task { panel.contentViewController = nil }
                dismissActive = nil
                continuation.resume(returning: value)
            }
            dismissActive = { finish(dismissValue) }
            panel.show(content(finish))
        }
    }
}

private final class PromptPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .floating
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { standardWindowButton($0)?.isHidden = true }
    }

    override var canBecomeKey: Bool { true }

    func show<Content: View>(_ content: Content) {
        contentViewController = NSHostingController(rootView: content)
        layoutIfNeeded()
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2, y: visible.midY + visible.height * 0.1))
        }
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }
}

// MARK: - File name

private struct NamePromptView: View {
    let template: FileTemplate
    let directory: URL
    @State var name: String
    let onFinish: (String?) -> Void

    private var problem: String? {
        if let problem = FileNaming.problem(with: name) { return problem }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if FileNaming.itemExists(directory.appendingPathComponent(trimmed)) {
            return "There’s already an item named “\(trimmed)” here."
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                FileTypeIcon(fileExtension: template.fileExtension, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("New \(template.name)")
                        .font(.headline)
                    Label(directory.lastPathComponent, systemImage: "folder")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                FileNameField(text: $name, onSubmit: submit, onCancel: { onFinish(nil) })
                    .frame(height: 24)
                Text(problem ?? " ")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .opacity(problem == nil ? 0 : 1)
            }

            HStack {
                Spacer()
                Button("Cancel") { onFinish(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil)
            }
        }
        .padding(20)
        .frame(width: 400)
        .tint(.brand)
    }

    private func submit() {
        guard problem == nil else { return }
        onFinish(name.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// A text field that selects the name without its extension when it appears, like Finder's rename.
private struct FileNameField: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.delegate = context.coordinator
        field.bezelStyle = .roundedBezel
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.lineBreakMode = .byTruncatingMiddle
        field.setAccessibilityLabel("File name")
        DispatchQueue.main.async {
            guard let window = field.window, window.makeFirstResponder(field) else { return }
            let baseLength = ((field.stringValue as NSString).deletingPathExtension as NSString).length
            field.currentEditor()?.selectedRange = NSRange(location: 0, length: baseLength)
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        private let parent: FileNameField

        init(_ parent: FileNameField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }
    }
}

// MARK: - Delete confirmation

private struct DeletePromptView: View {
    let names: [String]
    let onFinish: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                IconTile(symbol: "xmark.bin.fill", color: .red, size: 44)
                VStack(alignment: .leading, spacing: 6) {
                    Text(names.count == 1 ? "Delete “\(names[0])” permanently?" : "Delete \(names.count) items permanently?")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("This can’t be undone. Nothing goes to the Trash.")
                        .foregroundStyle(.secondary)
                    if names.count > 1 {
                        Text(summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
            }
            HStack {
                Spacer()
                // Return and Escape both cancel, so deleting always takes a deliberate click.
                Button("Cancel") { onFinish(false) }
                    .keyboardShortcut(.defaultAction)
                Button(role: .destructive) {
                    onFinish(true)
                } label: {
                    Text("Delete Permanently").foregroundStyle(.red)
                }
            }
        }
        .padding(20)
        .frame(width: 420)
        .onExitCommand { onFinish(false) }
    }

    private var summary: String {
        let shown = names.prefix(4).map { "“\($0)”" }.joined(separator: ", ")
        return names.count > 4 ? "\(shown) and \(names.count - 4) more" : shown
    }
}
