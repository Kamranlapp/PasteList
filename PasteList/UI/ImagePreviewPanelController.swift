import AppKit
import SwiftUI

enum ClipPreviewTarget: Equatable {
    case image(Int64)
    case text(Int64)
}

@MainActor
enum ClipTextPreviewPolicy {
    private static let timestampWidth: CGFloat = 48
    private static let outerSpacing: CGFloat = 10
    private static let quickPasteWidth: CGFloat = 30
    private static let trailingPadding: CGFloat = 8
    private static let pinnedIconWidth: CGFloat = 16

    static func shouldShow(
        for clip: ClipRecord,
        rowWidth: CGFloat,
        hasQuickPasteKey: Bool
    ) -> Bool {
        guard
            let contentType = ClipContentType(rawValue: clip.type),
            contentType == .text || contentType == .rtf || contentType == .url
        else {
            return false
        }

        let reservedWidth = timestampWidth
            + outerSpacing
            + (hasQuickPasteKey ? quickPasteWidth : 0)
            + trailingPadding
            + (clip.pinned ? pinnedIconWidth : 0)
        let availableWidth = max(rowWidth - reservedWidth, 1)
        let text = clip.previewText.isEmpty ? "Untitled clip" : clip.previewText
        let textFont = NSFont.preferredFont(forTextStyle: .body)
        let textHeight = (text as NSString).boundingRect(
            with: NSSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: textFont]
        ).height
        return textHeight > NSLayoutManager().defaultLineHeight(for: textFont) * 2
    }
}

@MainActor
final class TextPreviewPanelController {
    private static let fadeDuration: TimeInterval = 0.12
    private static let defaultContentSize = NSSize(width: 360, height: 240)
    static let padding: CGFloat = 16

    private let blobStorage: BlobStorage
    private let panel: TextPreviewPanel
    private var visibleClipID: Int64?
    private var fadeGeneration = 0

    init(blobStorage: BlobStorage) {
        self.blobStorage = blobStorage
        panel = TextPreviewPanel(
            contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
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
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
    }

    func show(
        clip: ClipRecord,
        relativeTo historyPanel: NSWindow,
        anchorFrame: NSRect,
        contentHeight: CGFloat? = nil
    ) {
        guard visibleClipID != clip.id else {
            return
        }
        guard let text = text(for: clip), !text.isEmpty else {
            hide()
            return
        }
        guard let screen = historyPanel.screen ?? NSScreen.main else {
            return
        }
        let previewSize = NSSize(
            width: Self.defaultContentSize.width,
            height: max(contentHeight ?? Self.defaultContentSize.height, 1)
        )

        panel.contentViewController = NSHostingController(
            rootView: TextPreviewView(text: text)
        )
        panel.setFrame(
            ImagePreviewPlacement.frame(
                previewSize: previewSize,
                anchorFrame: anchorFrame,
                visibleFrame: screen.visibleFrame
            ),
            display: false
        )

        visibleClipID = clip.id
        fadeGeneration += 1
        panel.alphaValue = 0
        panel.order(.above, relativeTo: historyPanel.windowNumber)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
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
                guard let self, self.fadeGeneration == fadeGeneration else {
                    return
                }
                panel.orderOut(nil)
                panel.alphaValue = 1
            }
        }
    }

    private func text(for clip: ClipRecord) -> String? {
        switch ClipContentType(rawValue: clip.type) {
        case .text, .url:
            return clip.content
        case .rtf:
            guard let data = try? blobStorage.readData(atRelativePath: clip.content) else {
                return nil
            }
            return try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            ).string
        case .image, .file, nil:
            return nil
        }
    }
}

private final class TextPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct TextPreviewView: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(TextPreviewPanelController.padding)
        }
        .font(.body)
        .background {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .blur(radius: 15)
                Color.black.opacity(0.2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: CursorPanelStyle.cornerRadius, style: .continuous))
    }
}

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
