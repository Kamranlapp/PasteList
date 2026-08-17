import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowController: NSWindowController {
    private weak var pasteAutomationController: PasteAutomationController?

    init(services: AppServices) {
        pasteAutomationController = services.pasteAutomationController
        let contentViewController = NSHostingController(
            rootView: PreferencesContainerView(services: services)
        )
        let window = PreferencesWindow(contentViewController: contentViewController)
        window.title = "\(AppConfiguration.name) Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.setContentSize(NSSize(width: 560, height: 720))
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)

        // The glass surface fills the title-bar area, so the native traffic
        // lights do not receive reliable hits. Closing lives inside the panel.
        for buttonType in [
            NSWindow.ButtonType.closeButton,
            .miniaturizeButton,
            .zoomButton,
        ] {
            window.standardWindowButton(buttonType)?.isHidden = true
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsWindowWillClose),
            name: NSWindow.willCloseNotification,
            object: window
        )
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        pasteAutomationController?.setSettingsVisible(true)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func settingsWindowWillClose() {
        pasteAutomationController?.setSettingsVisible(false)
    }
}

private final class PreferencesWindow: NSWindow {}
