import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    static let popoverSize = NSSize(width: 294, height: 392)
    static let cursorPanelPadding: CGFloat = 12
    static let cursorPanelContentSize = popoverSize
    static let cursorPanelSurfaceSize = NSSize(
        width: cursorPanelContentSize.width + cursorPanelPadding * 2,
        height: cursorPanelContentSize.height + cursorPanelPadding * 2
    )
    static let cursorScrollBarWidth: CGFloat = 8
    static let cursorScrollBarSpacing: CGFloat = 8
    static let cursorWindowControlDiameter: CGFloat = 24
    static let cursorWindowControlSpacing: CGFloat = 8
    static let cursorPanelSize = NSSize(
        width: cursorScrollBarWidth
            + cursorScrollBarSpacing
            + cursorPanelSurfaceSize.width,
        height: cursorWindowControlDiameter
            + cursorWindowControlSpacing
            + cursorPanelSurfaceSize.height
    )
    static let cursorPanelMinimumSize = NSSize(width: 276, height: 332)
    static let cursorHorizontalAnchor = 0.75
    static let cursorFirstRowCenterFromTop: CGFloat = 56
    private static let screenEdgePadding: CGFloat = 8
    private static let cursorPanelWidthDefaultsKey = "cursorPanelWidth"
    private static let cursorPanelHeightDefaultsKey = "cursorPanelHeight"

    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let actionsPopover: NSPopover
    private let cursorPanel: CursorHistoryPanel
    private let selectionResetController: HistorySelectionResetController
    private let accessibilityController: AccessibilityController
    private let onOpenSettings: () -> Void
    private var isCursorPanelPinned = false

    init(
        repository: ClipRepository,
        blobStorage: BlobStorage,
        pasteboardMonitor: PasteboardMonitor,
        accessibilityController: AccessibilityController,
        onOpenSettings: @escaping () -> Void
    ) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        actionsPopover = NSPopover()
        selectionResetController = HistorySelectionResetController()
        let initialCursorPanelSize = Self.storedCursorPanelSize()
        cursorPanel = CursorHistoryPanel(
            contentRect: NSRect(origin: .zero, size: initialCursorPanelSize),
            styleMask: [.borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.accessibilityController = accessibilityController
        self.onOpenSettings = onOpenSettings
        super.init()

        configureStatusItem()
        configurePopover(
            repository: repository,
            blobStorage: blobStorage,
            pasteboardMonitor: pasteboardMonitor
        )
        configureCursorPanel(
            repository: repository,
            blobStorage: blobStorage,
            pasteboardMonitor: pasteboardMonitor
        )
        configureActionsPopover()
    }

    func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        let image = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "KPaste"
        )
        image?.isTemplate = true
        button.image = image
        button.toolTip = "KPaste"
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configureActionsPopover() {
        actionsPopover.behavior = .transient
        actionsPopover.animates = true
        actionsPopover.contentSize = NSSize(width: 220, height: 132)
        actionsPopover.contentViewController = NSHostingController(
            rootView: StatusActionsView(
                openSettings: { [weak self] in
                    self?.actionsPopover.performClose(nil)
                    self?.onOpenSettings()
                },
                restart: { [weak self] in
                    self?.restartApplication()
                },
                quit: {
                    NSApp.terminate(nil)
                }
            )
        )
    }

    private func configurePopover(
        repository: ClipRepository,
        blobStorage: BlobStorage,
        pasteboardMonitor: PasteboardMonitor
    ) {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = Self.popoverSize
        popover.contentViewController = NSHostingController(
            rootView: HistoryView(
                repository: repository,
                blobStorage: blobStorage,
                restorer: ClipRestorer(
                    repository: repository,
                    blobStorage: blobStorage,
                    monitor: pasteboardMonitor
                ),
                bulkPasteController: BulkPasteController(
                    repository: repository,
                    blobStorage: blobStorage,
                    monitor: pasteboardMonitor
                ),
                onRestored: { [weak self] in
                    self?.didRestoreClip()
                },
                selectionResetController: selectionResetController
            )
        )
    }

    private func configureCursorPanel(
        repository: ClipRepository,
        blobStorage: BlobStorage,
        pasteboardMonitor: PasteboardMonitor
    ) {
        cursorPanel.isReleasedWhenClosed = false
        cursorPanel.isFloatingPanel = true
        cursorPanel.level = .popUpMenu
        cursorPanel.backgroundColor = .clear
        cursorPanel.isOpaque = false
        cursorPanel.hasShadow = true
        cursorPanel.minSize = Self.cursorPanelMinimumSize
        cursorPanel.collectionBehavior = [
            .transient,
            .moveToActiveSpace,
            .fullScreenAuxiliary,
        ]
        cursorPanel.delegate = self
        cursorPanel.contentViewController = NSHostingController(
            rootView: HistoryView(
                repository: repository,
                blobStorage: blobStorage,
                restorer: ClipRestorer(
                    repository: repository,
                    blobStorage: blobStorage,
                    monitor: pasteboardMonitor
                ),
                bulkPasteController: BulkPasteController(
                    repository: repository,
                    blobStorage: blobStorage,
                    monitor: pasteboardMonitor
                ),
                onRestored: { [weak self] in
                    self?.didRestoreClip()
                },
                usesTransparentBackground: true,
                onCursorPanelPinChanged: { [weak self] isPinned in
                    self?.setCursorPanelPinned(isPinned)
                },
                selectionResetController: selectionResetController
            )
        )
    }

    func showPopover() {
        guard let button = statusItem.button else {
            return
        }

        actionsPopover.performClose(nil)
        closeCursorPanel(force: true)
        selectionResetController.reset()
        accessibilityController.rememberFrontmostApplication()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func toggleCursorPanelAtPointer() {
        if cursorPanel.isVisible {
            closeCursorPanel(force: true)
            return
        }

        popover.performClose(nil)
        actionsPopover.performClose(nil)
        selectionResetController.reset()
        accessibilityController.rememberFrontmostApplication()

        let pointerLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointerLocation) }
            ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            return
        }

        cursorPanel.setFrame(
            Self.cursorPanelFrame(
                pointerLocation: pointerLocation,
                visibleFrame: visibleFrame,
                size: cursorPanel.frame.size
            ),
            display: true
        )
        NSApp.activate(ignoringOtherApps: true)
        cursorPanel.makeKeyAndOrderFront(nil)
    }

    static func cursorPanelFrame(
        pointerLocation: NSPoint,
        visibleFrame: NSRect,
        size requestedSize: NSSize = cursorPanelSize
    ) -> NSRect {
        let availableFrame = visibleFrame.insetBy(
            dx: screenEdgePadding,
            dy: screenEdgePadding
        )
        let size = NSSize(
            width: min(max(requestedSize.width, cursorPanelMinimumSize.width), availableFrame.width),
            height: min(max(requestedSize.height, cursorPanelMinimumSize.height), availableFrame.height)
        )
        let desiredOrigin = NSPoint(
            x: pointerLocation.x
                - cursorScrollBarWidth
                - cursorScrollBarSpacing
                - cursorPanelPadding
                - (size.width
                    - cursorScrollBarWidth
                    - cursorScrollBarSpacing
                    - cursorPanelPadding * 2)
                    * cursorHorizontalAnchor,
            y: pointerLocation.y
                - (
                    size.height
                        - cursorWindowControlDiameter
                        - cursorWindowControlSpacing
                        - cursorPanelPadding
                        - cursorFirstRowCenterFromTop
                )
        )
        let maximumX = max(availableFrame.minX, availableFrame.maxX - size.width)
        let maximumY = max(availableFrame.minY, availableFrame.maxY - size.height)
        let origin = NSPoint(
            x: min(max(desiredOrigin.x, availableFrame.minX), maximumX),
            y: min(max(desiredOrigin.y, availableFrame.minY), maximumY)
        )
        return NSRect(origin: origin, size: size)
    }

    static func storedCursorPanelSize(
        in userDefaults: UserDefaults = .standard
    ) -> NSSize {
        let width = userDefaults.double(forKey: cursorPanelWidthDefaultsKey)
        let height = userDefaults.double(forKey: cursorPanelHeightDefaultsKey)
        guard width.isFinite, height.isFinite, width > 0, height > 0 else {
            return cursorPanelSize
        }
        return NSSize(
            width: max(CGFloat(width), cursorPanelMinimumSize.width),
            height: max(CGFloat(height), cursorPanelMinimumSize.height)
        )
    }

    static func saveCursorPanelSize(
        _ size: NSSize,
        in userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(size.width, forKey: cursorPanelWidthDefaultsKey)
        userDefaults.set(size.height, forKey: cursorPanelHeightDefaultsKey)
    }

    private func saveCursorPanelSize() {
        Self.saveCursorPanelSize(cursorPanel.frame.size)
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            toggleActionsPopover()
        } else {
            togglePopover()
        }
    }

    private func didRestoreClip() {
        popover.performClose(nil)
        closeCursorPanel(force: true)
        Task { [weak accessibilityController] in
            _ = await accessibilityController?.pasteIntoPreviousApplication()
        }
    }

    private func toggleActionsPopover() {
        if actionsPopover.isShown {
            actionsPopover.performClose(nil)
            return
        }

        popover.performClose(nil)
        closeCursorPanel(force: true)
        guard let button = statusItem.button else {
            return
        }
        actionsPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        actionsPopover.contentViewController?.view.window?.makeKey()
    }

    private func restartApplication() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundlePath]

        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            NSLog("KPaste failed to restart: %@", String(describing: error))
        }
    }

    private func setCursorPanelPinned(_ isPinned: Bool) {
        isCursorPanelPinned = isPinned
        cursorPanel.level = isPinned ? .floating : .popUpMenu
        cursorPanel.collectionBehavior = isPinned
            ? [.canJoinAllSpaces, .fullScreenAuxiliary]
            : [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
    }

    private func closeCursorPanel(force: Bool = false) {
        guard force || !isCursorPanelPinned else {
            return
        }
        guard cursorPanel.isVisible else {
            return
        }
        cursorPanel.orderOut(nil)
        selectionResetController.reset()
    }
}

extension StatusItemController: NSWindowDelegate {
    func windowDidResize(_ notification: Notification) {
        guard notification.object as? NSWindow === cursorPanel else {
            return
        }
        saveCursorPanelSize()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard notification.object as? NSWindow === cursorPanel else {
            return
        }
        closeCursorPanel()
    }
}

extension StatusItemController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        guard notification.object as? NSPopover === popover else {
            return
        }
        selectionResetController.reset()
    }
}

@MainActor
final class HistorySelectionResetController: ObservableObject {
    @Published private(set) var token = 0

    func reset() {
        token &+= 1
    }
}

private final class CursorHistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct StatusActionsView: View {
    let openSettings: () -> Void
    let restart: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            actionButton("Settings…", systemImage: "gearshape", action: openSettings)
            actionButton("Restart KPaste", systemImage: "arrow.clockwise", action: restart)
            Divider()
            actionButton("Quit KPaste", systemImage: "power", action: quit)
        }
        .padding(8)
        .frame(width: 220, height: 132)
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .frame(height: 30)
    }
}
