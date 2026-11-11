import AppKit
import Observation
import RightShortcutsActions
import SwiftUI

/// One long-running file operation, shown with a progress bar and a way to stop it.
@MainActor
@Observable
final class OperationJob: Identifiable {
    let id = UUID()
    let title: String
    /// Between 0 and 1, or nil while the amount of work isn't known.
    private(set) var fraction: Double?
    @ObservationIgnored let control = OperationControl()

    init(title: String) {
        self.title = title
    }

    func update(_ progress: TransferProgress) {
        // Updates hop over from another thread and may arrive out of order; never step back.
        guard let next = progress.fraction, next >= fraction ?? 0 else { return }
        fraction = next
    }
}

/// Shows running copies, moves and deletions near the bottom of the screen.
/// Quick operations finish before anything appears.
@MainActor
@Observable
final class ProgressCenter {
    static let shared = ProgressCenter()

    /// The jobs that have run long enough to be worth showing.
    private(set) var jobs: [OperationJob] = []
    /// Every job that has started and not ended, shown or not.
    @ObservationIgnored private var running: [OperationJob] = []
    @ObservationIgnored private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var panel: NSPanel?
    private static let appearanceDelay = Duration.milliseconds(450)

    var isBusy: Bool { !running.isEmpty }

    func begin(_ title: String) -> OperationJob {
        let job = OperationJob(title: title)
        running.append(job)
        Task {
            try? await Task.sleep(for: Self.appearanceDelay)
            guard running.contains(where: { $0.id == job.id }) else { return }
            jobs.append(job)
            layout()
        }
        return job
    }

    func end(_ job: OperationJob) {
        running.removeAll { $0.id == job.id }
        jobs.removeAll { $0.id == job.id }
        layout()
        if running.isEmpty {
            idleWaiters.forEach { $0.resume() }
            idleWaiters = []
        }
    }

    /// Stops every operation and returns once each has cleaned up after itself.
    func stopAll() async {
        running.forEach { $0.control.cancel() }
        guard isBusy else { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    private func layout() {
        guard !jobs.isEmpty else {
            panel?.orderOut(nil)
            return
        }
        let panel = panel ?? makePanel()
        self.panel = panel
        let size = NSSize(width: ProgressList.width, height: ProgressList.height(rows: jobs.count))
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            // Just above where confirmations appear.
            panel.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.minY + 150,
                                  width: size.width, height: size.height), display: true)
        }
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = .roundedMask(radius: 16)
        let content = NSHostingView(rootView: ProgressList(center: self))
        content.frame = effect.bounds
        content.autoresizingMask = [.width, .height]
        effect.addSubview(content)
        panel.contentView = effect
        return panel
    }
}

private struct ProgressList: View {
    let center: ProgressCenter

    static let width: CGFloat = 380
    private static let rowHeight: CGFloat = 46
    private static let padding: CGFloat = 12

    static func height(rows: Int) -> CGFloat {
        CGFloat(rows) * rowHeight + padding * 2
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(center.jobs) { job in
                ProgressRow(job: job)
                    .frame(height: Self.rowHeight)
            }
        }
        .padding(Self.padding)
        .frame(width: Self.width)
    }
}

private struct ProgressRow: View {
    let job: OperationJob

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(job.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let fraction = job.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
            }
            .tint(.brand)
            Button {
                job.control.cancel()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Stop")
            .accessibilityLabel("Stop \(job.title)")
        }
    }
}
