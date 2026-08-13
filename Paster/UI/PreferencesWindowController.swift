import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowController: NSWindowController {
    init(services: AppServices) {
        let contentViewController = NSHostingController(
            rootView: PreferencesContainerView(services: services)
        )
        let window = NSWindow(contentViewController: contentViewController)
        window.title = "PasteList Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.setContentSize(NSSize(width: 560, height: 720))
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
