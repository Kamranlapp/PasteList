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
    static let cursorBulkPasteRailWidth: CGFloat = 113
    static let cursorBulkPasteRailSpacing: CGFloat = 8
    static let cursorWindowControlDiameter: CGFloat = 24
    static let cursorWindowControlSpacing: CGFloat = 8
    static let cursorWindowTooltipHeight: CGFloat = 18
    static let cursorPanelFadeDuration: TimeInterval = 0.3
    static let cursorWindowControlAreaHeight = cursorWindowTooltipHeight
        + cursorWindowControlDiameter
    static let cursorPanelSize = NSSize(
        width: cursorScrollBarWidth
            + cursorScrollBarSpacing
            + cursorPanelSurfaceSize.width
            + cursorBulkPasteRailSpacing
            + cursorBulkPasteRailWidth,
        height: cursorWindowControlAreaHeight
            + cursorWindowControlSpacing
            + cursorPanelSurfaceSize.height
    )
    static let cursorPanelMinimumSize = NSSize(
        width: 276 + cursorBulkPasteRailSpacing + cursorBulkPasteRailWidth,
        height: 332
    )
    static let cursorHorizontalAnchor = 0.75
    static let cursorFirstRowCenterFromTop: CGFloat = 56
    private static let screenEdgePadding: CGFloat = 8
    private static let cursorPanelWidthDefaultsKey = "cursorPanelWidth"
    private static let cursorPanelHeightDefaultsKey = "cursorPanelHeight"
    private static let cursorPanelLayoutVersionDefaultsKey = "cursorPanelLayoutVersion"
    private static let cursorPanelLayoutVersion = 2

    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let actionsPopover: NSPopover
    private let cursorPanel: CursorHistoryPanel
    private let selectionResetController: HistorySelectionResetController
    private let accessibilityController: AccessibilityController
    private let onOpenSettings: () -> Void
    private var isCursorPanelPinned = false
    private var isCursorPanelResizeModeEnabled = false
    private var isCursorPanelFilterMenuPresented = false
    private var isCursorPanelClearConfirmationPresented = false
    private var localResizeExitMonitor: Any?
    private var globalResizeExitMonitor: Any?
    private var cursorPanelFadeGeneration = 0
    private var isCursorPanelFadingOut = false

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
            styleMask: [.borderless, .fullSizeContentView],
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

        let image = NSImage(named: "BarIcon")
            ?? NSImage(
                systemSymbolName: "doc.on.clipboard",
                accessibilityDescription: "KPaste"
            )
        image?.size = NSSize(width: 22, height: 22)
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
        cursorPanel.hidesOnDeactivate = false
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
        cursorPanel.cancelResizeMode = { [weak self] in
            self?.finishCursorPanelResizeMode()
        }
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
                onCursorPanelResizeModeChanged: { [weak self] isEnabled in
                    self?.setCursorPanelResizeMode(isEnabled)
                },
                onCursorPanelFilterMenuPresentationChanged: { [weak self] isPresented in
                    self?.isCursorPanelFilterMenuPresented = isPresented
                },
                onCursorPanelClearConfirmationChanged: { [weak self] isPresented in
                    self?.isCursorPanelClearConfirmationPresented = isPresented
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
        if cursorPanel.isVisible && !isCursorPanelFadingOut {
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
        cursorPanelFadeGeneration += 1
        isCursorPanelFadingOut = false
        cursorPanel.alphaValue = 0
        cursorPanel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.cursorPanelFadeDuration
            context.timingFunction = CAMediaTimingFunction(
                name: .easeInEaseOut
            )
            cursorPanel.animator().alphaValue = 1
        }
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
                    - cursorBulkPasteRailSpacing
                    - cursorBulkPasteRailWidth
                    - cursorPanelPadding * 2)
                    * cursorHorizontalAnchor,
            y: pointerLocation.y
                - (
                    size.height
                        - cursorWindowControlAreaHeight
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
        let storedLayoutVersion = userDefaults.integer(
            forKey: cursorPanelLayoutVersionDefaultsKey
        )
        let migratedWidth = storedLayoutVersion < cursorPanelLayoutVersion
            ? CGFloat(width) + cursorBulkPasteRailSpacing + cursorBulkPasteRailWidth
            : CGFloat(width)
        if storedLayoutVersion < cursorPanelLayoutVersion {
            userDefaults.set(
                cursorPanelLayoutVersion,
                forKey: cursorPanelLayoutVersionDefaultsKey
            )
        }
        return NSSize(
            width: max(migratedWidth, cursorPanelMinimumSize.width),
            height: max(CGFloat(height), cursorPanelMinimumSize.height)
        )
    }

    static func saveCursorPanelSize(
        _ size: NSSize,
        in userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(size.width, forKey: cursorPanelWidthDefaultsKey)
        userDefaults.set(size.height, forKey: cursorPanelHeightDefaultsKey)
        userDefaults.set(
            cursorPanelLayoutVersion,
            forKey: cursorPanelLayoutVersionDefaultsKey
        )
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
        closeCursorPanel()
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
        cursorPanel.level = .popUpMenu
        cursorPanel.hidesOnDeactivate = false
        cursorPanel.collectionBehavior = isPinned
            ? [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            : [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
    }

    private func setCursorPanelResizeMode(_ isEnabled: Bool) {
        guard isCursorPanelResizeModeEnabled != isEnabled else {
            return
        }
        isCursorPanelResizeModeEnabled = isEnabled
        if isEnabled {
            installResizeExitMonitors()
        } else {
            removeResizeExitMonitors()
            saveCursorPanelSize()
        }
    }

    private func finishCursorPanelResizeMode() {
        guard isCursorPanelResizeModeEnabled else {
            return
        }
        setCursorPanelResizeMode(false)
        selectionResetController.reset()
    }

    private func installResizeExitMonitors() {
        removeResizeExitMonitors()
        localResizeExitMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .leftMouseDown
        ) { [weak self] event in
            self?.finishResizeModeIfClickIsFarFromEdge()
            return event
        }
        globalResizeExitMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .leftMouseDown
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.finishResizeModeIfClickIsFarFromEdge()
            }
        }
    }

    private func removeResizeExitMonitors() {
        if let localResizeExitMonitor {
            NSEvent.removeMonitor(localResizeExitMonitor)
            self.localResizeExitMonitor = nil
        }
        if let globalResizeExitMonitor {
            NSEvent.removeMonitor(globalResizeExitMonitor)
            self.globalResizeExitMonitor = nil
        }
    }

    private func finishResizeModeIfClickIsFarFromEdge() {
        guard isCursorPanelResizeModeEnabled else {
            return
        }
        let point = NSEvent.mouseLocation
        let frame = cursorPanel.frame
        let distance: CGFloat
        if frame.contains(point) {
            distance = min(
                point.x - frame.minX,
                frame.maxX - point.x,
                point.y - frame.minY,
                frame.maxY - point.y
            )
        } else {
            let horizontalDistance = max(
                frame.minX - point.x,
                0,
                point.x - frame.maxX
            )
            let verticalDistance = max(
                frame.minY - point.y,
                0,
                point.y - frame.maxY
            )
            distance = hypot(horizontalDistance, verticalDistance)
        }
        if distance > 100 {
            finishCursorPanelResizeMode()
        }
    }

    private func closeCursorPanel(force: Bool = false) {
        guard force || !isCursorPanelPinned else {
            return
        }
        setCursorPanelResizeMode(false)
        guard cursorPanel.isVisible else {
            return
        }
        guard !isCursorPanelFadingOut else {
            return
        }
        cursorPanelFadeGeneration += 1
        let fadeGeneration = cursorPanelFadeGeneration
        isCursorPanelFadingOut = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.cursorPanelFadeDuration
            context.timingFunction = CAMediaTimingFunction(
                name: .easeInEaseOut
            )
            cursorPanel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard
                    let self,
                    cursorPanelFadeGeneration == fadeGeneration
                else {
                    return
                }
                cursorPanel.orderOut(nil)
                cursorPanel.alphaValue = 1
                isCursorPanelFadingOut = false
                selectionResetController.reset()
            }
        }
    }
}

extension StatusItemController: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        guard notification.object as? NSWindow === cursorPanel else {
            return
        }
        guard
            !isCursorPanelFilterMenuPresented,
            !isCursorPanelClearConfirmationPresented
        else {
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
    var cancelResizeMode: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        cancelResizeMode?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            cancelResizeMode?()
        } else {
            super.keyDown(with: event)
        }
    }

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
