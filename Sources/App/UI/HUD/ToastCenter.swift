import AppKit
import SwiftUI

/// Short confirmation messages near the bottom of the screen, like "Path copied".
@MainActor
final class ToastCenter {
    enum Style {
        case success
        case failure
    }

    static let shared = ToastCenter()

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, symbol: String, style: Style = .success) {
        let panel = panel ?? makePanel()
        self.panel = panel

        let content = NSHostingView(rootView: ToastView(message: message, symbol: symbol, style: style))
        let size = content.fittingSize
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = .roundedMask(radius: size.height / 2)
        content.frame = effect.bounds
        content.autoresizingMask = [.width, .height]
        effect.addSubview(content)
        panel.contentView = effect

        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.minY + 96,
                                  width: size.width, height: size.height), display: true)
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }

        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(style == .failure ? 4 : 1.6))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func dismiss() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                if panel.alphaValue == 0 { panel.orderOut(nil) }
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }
}

private struct ToastView: View {
    let message: String
    let symbol: String
    let style: ToastCenter.Style

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(style == .failure ? Color.red : Color.brand)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(3)
                .frame(maxWidth: 420, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }
}

extension NSImage {
    /// A stretchable rounded rectangle, used to clip visual effect views.
    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
