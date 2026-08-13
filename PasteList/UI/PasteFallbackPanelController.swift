import AppKit
import SwiftUI

@MainActor
final class PasteFallbackPanelController {
    static let title = "Copied — press ⌘V to paste"
    static let message = "For automatic and quick paste, allow PasteList in Settings."

    private static let panelSize = NSSize(width: 500, height: 96)

    private let panel: NSPanel
    private var dismissalTask: Task<Void, Never>?
    private let openSettings: () -> Void

    init(openSettings: @escaping () -> Void) {
        self.openSettings = openSettings
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentViewController = NSHostingController(
            rootView: PasteFallbackView(
                openSettings: { [weak self] in
                    self?.hide()
                    self?.openSettings()
                }
            )
        )
    }

    func show() {
        dismissalTask?.cancel()
        let pointer = NSEvent.mouseLocation
        let visibleFrame = NSScreen.screens.first { $0.frame.contains(pointer) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? .zero
        let origin = NSPoint(
            x: min(
                max(pointer.x - Self.panelSize.width / 2, visibleFrame.minX + 8),
                visibleFrame.maxX - Self.panelSize.width - 8
            ),
            y: min(
                max(pointer.y + 20, visibleFrame.minY + 8),
                visibleFrame.maxY - Self.panelSize.height - 8
            )
        )
        panel.setFrameOrigin(origin)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        dismissalTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else {
                return
            }
            self?.panel.orderOut(nil)
        }
    }

    private func hide() {
        dismissalTask?.cancel()
        panel.orderOut(nil)
    }
}

private struct PasteFallbackView: View {
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 4) {
                Text(PasteFallbackPanelController.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(PasteFallbackPanelController.message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Open Settings", action: openSettings)
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                    .fixedSize()
            }
        }
        .padding(.horizontal, 18)
        .frame(width: 500, height: 96)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.separator.opacity(0.65), lineWidth: 1)
        }
    }
}
