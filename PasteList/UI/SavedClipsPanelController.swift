import AppKit
import SwiftUI

enum SavedClipsPlacement {
    static let defaultGap: CGFloat = 16
    static let widthRatio: CGFloat = 0.66

    /// Two thirds the width of the history panel's visible surface, exactly
    /// half its height, sharing its top edge.
    static func frame(
        panelSurfaceFrame: NSRect,
        visibleFrame: NSRect,
        gap: CGFloat = defaultGap
    ) -> NSRect {
        let size = NSSize(
            width: (panelSurfaceFrame.width * widthRatio).rounded(),
            height: (panelSurfaceFrame.height / 2).rounded()
        )
        let rightOrigin = panelSurfaceFrame.maxX + gap
        let leftOrigin = panelSurfaceFrame.minX - gap - size.width
        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - size.width)
        let originX: CGFloat
        if leftOrigin >= visibleFrame.minX {
            originX = leftOrigin
        } else if rightOrigin + size.width <= visibleFrame.maxX {
            originX = rightOrigin
        } else {
            originX = min(max(leftOrigin, visibleFrame.minX), maximumX)
        }

        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - size.height)
        let originY = min(
            max(panelSurfaceFrame.maxY - size.height, visibleFrame.minY),
            maximumY
        )
        return NSRect(origin: NSPoint(x: originX, y: originY), size: size)
    }
}

@MainActor
final class SavedClipsPanelController {
    private static let fadeDuration: TimeInterval = 0.15
    private static let visibilityDefaultsKey = "savedPanelVisible"

    private let panel: SavedClipsPanel
    private let userDefaults: UserDefaults
    private var fadeGeneration = 0

    private(set) var isEnabled: Bool

    static func storedVisibility(in userDefaults: UserDefaults = .standard) -> Bool {
        userDefaults.bool(forKey: visibilityDefaultsKey)
    }

    static func saveVisibility(
        _ isVisible: Bool,
        in userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(isVisible, forKey: visibilityDefaultsKey)
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        isEnabled = Self.storedVisibility(in: userDefaults)
        panel = SavedClipsPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 334, height: 208)),
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
        panel.collectionBehavior = [
            .transient,
            .moveToActiveSpace,
            .fullScreenAuxiliary,
        ]
    }

    func configure<Content: View>(rootView: Content) {
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.sizingOptions = []
        panel.contentViewController = hostingController
    }

    func setEnabled(_ isEnabled: Bool, relativeTo historyPanel: NSWindow) {
        self.isEnabled = isEnabled
        Self.saveVisibility(isEnabled, in: userDefaults)
        if isEnabled {
            show(relativeTo: historyPanel)
        } else {
            hide()
        }
    }

    func show(relativeTo historyPanel: NSWindow) {
        guard isEnabled, let frame = frame(relativeTo: historyPanel) else {
            return
        }
        panel.setFrame(frame, display: false)
        guard !panel.isVisible else {
            return
        }
        fadeGeneration += 1
        panel.alphaValue = 0
        // A child window rides along when the user drags the history panel, and
        // is always ordered above it.
        historyPanel.addChildWindow(panel, ordered: .above)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
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
                panel.parent?.removeChildWindow(panel)
                panel.orderOut(nil)
                panel.alphaValue = 1
            }
        }
    }

    /// Child windows follow the parent when it moves but not when it resizes.
    func layout(relativeTo historyPanel: NSWindow) {
        guard panel.isVisible, let frame = frame(relativeTo: historyPanel) else {
            return
        }
        panel.setFrame(frame, display: true)
    }

    /// The rectangle an image preview should sit to the right of: the history
    /// panel alone, or the two windows together when Saved is open.
    func anchorFrame(surfaceFrame: NSRect) -> NSRect {
        panel.isVisible ? surfaceFrame.union(panel.frame) : surfaceFrame
    }

    private func frame(relativeTo historyPanel: NSWindow) -> NSRect? {
        guard let screen = historyPanel.screen ?? NSScreen.main else {
            return nil
        }
        return SavedClipsPlacement.frame(
            panelSurfaceFrame: StatusItemController.cursorPanelSurfaceFrame(
                in: historyPanel.frame
            ),
            visibleFrame: screen.visibleFrame
        )
    }
}

/// Must never become key: the history panel closes itself on
/// `windowDidResignKey`, and clicks here would otherwise dismiss it.
private final class SavedClipsPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
