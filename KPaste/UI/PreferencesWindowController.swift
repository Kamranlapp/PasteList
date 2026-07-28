import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowController: NSWindowController {
    init(services: AppServices) {
        let contentViewController = NSHostingController(
            rootView: PreferencesContainerView(services: services)
        )
        let window = NSWindow(contentViewController: contentViewController)
        window.title = "KPaste Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 460, height: 360))
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
