import AppKit
import SwiftUI

enum ImagePreviewPlacement {
    static let maximumDisplaySize = NSSize(width: 420, height: 420)
    static let minimumLongSide: CGFloat = 120
    static let padding: CGFloat = 8
    static let defaultGap: CGFloat = 16

    static func displaySize(
        pixelSize: NSSize,
        scale: CGFloat,
        maximum: NSSize = maximumDisplaySize,
        minimumLongSide: CGFloat = minimumLongSide
    ) -> NSSize {
        let safeScale = scale > 0 ? scale : 1
        let width = max(pixelSize.width, 1) / safeScale
        let height = max(pixelSize.height, 1) / safeScale
        let longSide = max(width, height)
        let fittingFactor = min(maximum.width / width, maximum.height / height)
        var factor = min(fittingFactor, 1)
        if longSide * factor < minimumLongSide {
            factor = min(minimumLongSide / longSide, fittingFactor)
        }
        return NSSize(
            width: max((width * factor).rounded(), 1),
            height: max((height * factor).rounded(), 1)
        )
    }

    /// - Parameters:
    ///   - previewSize: full window size, image plus `padding` on every side.
    ///   - anchorFrame: what the preview sits next to — the history panel's
    ///     *visible* rounded surface (its window frame also covers the hidden
    ///     bulk-paste rail and the control strip, which would inflate the gap),
    ///     unioned with the Saved panel when that one is open.
    static func frame(
        previewSize: NSSize,
        anchorFrame: NSRect,
        visibleFrame: NSRect,
        gap: CGFloat = defaultGap
    ) -> NSRect {
        let rightOrigin = anchorFrame.maxX + gap
        let leftOrigin = anchorFrame.minX - gap - previewSize.width
        let maximumX = max(
            visibleFrame.minX,
            visibleFrame.maxX - previewSize.width
        )
        let originX: CGFloat
        if rightOrigin + previewSize.width <= visibleFrame.maxX {
            originX = rightOrigin
        } else if leftOrigin >= visibleFrame.minX {
            originX = leftOrigin
        } else {
            originX = min(max(rightOrigin, visibleFrame.minX), maximumX)
        }

        let maximumY = max(
            visibleFrame.minY,
            visibleFrame.maxY - previewSize.height
        )
        // Both rounded cards share one top line.
        let originY = min(
            max(anchorFrame.maxY - previewSize.height, visibleFrame.minY),
            maximumY
        )
        return NSRect(
            x: originX,
            y: originY,
            width: previewSize.width,
            height: previewSize.height
        )
    }
}

@MainActor
final class ImagePreviewPanelController {
    private static let fadeDuration: TimeInterval = 0.12
    private static let maximumPixelSize = 840

    private let cache: ImageThumbnailCache
    private let panel: ImagePreviewPanel
    private var loadTask: Task<Void, Never>?
    private var fadeGeneration = 0
    private var visibleClipID: Int64?

    init(blobStorage: BlobStorage) {
        cache = ImageThumbnailCache(blobStorage: blobStorage, maximumEntryCount: 8)
        panel = ImagePreviewPanel(
            contentRect: NSRect(origin: .zero, size: ImagePreviewPlacement.maximumDisplaySize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        // The preview must never take key away from the history panel, which
        // closes itself on windowDidResignKey, and must not swallow the hover
        // events that keep the preview alive.
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [
            .transient,
            .moveToActiveSpace,
            .fullScreenAuxiliary,
        ]
    }

    func show(clipID: Int64, relativeTo historyPanel: NSWindow, anchorFrame: NSRect) {
        guard visibleClipID != clipID else {
            return
        }
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else {
                return
            }
            let image = try? await cache.thumbnail(
                for: clipID,
                maximumPixelSize: Self.maximumPixelSize
            )
            guard let image, !Task.isCancelled else {
                return
            }
            present(
                image: image,
                clipID: clipID,
                relativeTo: historyPanel,
                anchorFrame: anchorFrame
            )
        }
    }

    func hide() {
        loadTask?.cancel()
        loadTask = nil
        visibleClipID = nil
        guard panel.isVisible else {
            return
        }
        fadeGeneration += 1
        let fadeGeneration = fadeGeneration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard
                    let self,
                    self.fadeGeneration == fadeGeneration
                else {
                    return
                }
                panel.orderOut(nil)
                panel.alphaValue = 1
            }
        }
    }

    private func present(
        image: CGImage,
        clipID: Int64,
        relativeTo historyPanel: NSWindow,
        anchorFrame: NSRect
    ) {
        guard let screen = historyPanel.screen ?? NSScreen.main else {
            return
        }
        let displaySize = ImagePreviewPlacement.displaySize(
            pixelSize: NSSize(width: image.width, height: image.height),
            scale: screen.backingScaleFactor
        )
        let hostingController = NSHostingController(
            rootView: ImagePreviewView(image: image, displaySize: displaySize)
        )
        hostingController.sizingOptions = []
        panel.contentViewController = hostingController
        panel.setFrame(
            ImagePreviewPlacement.frame(
                previewSize: NSSize(
                    width: displaySize.width + ImagePreviewPlacement.padding * 2,
                    height: displaySize.height + ImagePreviewPlacement.padding * 2
                ),
                anchorFrame: anchorFrame,
                visibleFrame: screen.visibleFrame
            ),
            display: false
        )

        visibleClipID = clipID
        fadeGeneration += 1
        panel.alphaValue = 0
        panel.order(.above, relativeTo: historyPanel.windowNumber)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 1
        }
    }
}

private final class ImagePreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct ImagePreviewView: View {
    let image: CGImage
    let displaySize: NSSize

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: displaySize.width, height: displaySize.height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(ImagePreviewPlacement.padding)
            .background {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .blur(radius: 15)
                    Color.black.opacity(0.2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
