import AppKit
import SwiftUI

@MainActor
final class PasteFallbackPanelController {
    static let message = "Copied — press ⌘V to paste"

    private let panel: NSPanel
    private var dismissalTask: Task<Void, Never>?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 270, height: 52),
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
        panel.contentViewController = NSHostingController(rootView: PasteFallbackView())
    }

    func show() {
        dismissalTask?.cancel()
        let pointer = NSEvent.mouseLocation
        let visibleFrame = NSScreen.screens.first { $0.frame.contains(pointer) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? .zero
        let origin = NSPoint(
            x: min(max(pointer.x - 135, visibleFrame.minX + 8), visibleFrame.maxX - 278),
            y: min(max(pointer.y + 20, visibleFrame.minY + 8), visibleFrame.maxY - 60)
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
}

private struct PasteFallbackView: View {
    var body: some View {
        Label(PasteFallbackPanelController.message, systemImage: "doc.on.clipboard.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 18)
            .frame(width: 270, height: 52)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.separator.opacity(0.65), lineWidth: 1)
            }
    }
}
