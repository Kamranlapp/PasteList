import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    static let popoverSize = NSSize(width: 420, height: 560)

    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let actionsPopover: NSPopover
    private let accessibilityController: AccessibilityController
    private let onOpenSettings: () -> Void

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
        self.accessibilityController = accessibilityController
        self.onOpenSettings = onOpenSettings
        super.init()

        configureStatusItem()
        configurePopover(
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
                }
            )
        )
    }

    func showPopover() {
        guard let button = statusItem.button else {
            return
        }

        actionsPopover.performClose(nil)
        accessibilityController.rememberFrontmostApplication()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
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
