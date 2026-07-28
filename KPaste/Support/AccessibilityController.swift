import AppKit
@preconcurrency import ApplicationServices
import Combine
import Foundation

@MainActor
final class AccessibilityController: ObservableObject {
    @Published private(set) var isTrusted: Bool

    private var previousApplication: NSRunningApplication?

    init() {
        isTrusted = AXIsProcessTrusted()
    }

    func rememberFrontmostApplication() {
        guard
            let application = NSWorkspace.shared.frontmostApplication,
            application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
            application.bundleIdentifier != AppConfiguration.bundleIdentifier
        else {
            return
        }

        previousApplication = application
    }

    func refreshTrust() {
        isTrusted = AXIsProcessTrusted()
    }

    func requestAccess() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
        ] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @discardableResult
    func pasteIntoPreviousApplication() async -> Bool {
        refreshTrust()
        guard isTrusted else {
            requestAccess()
            return false
        }

        guard
            let application = previousApplication,
            !application.isTerminated,
            application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
            application.bundleIdentifier != AppConfiguration.bundleIdentifier
        else {
            return false
        }

        application.activate(options: [.activateIgnoringOtherApps])
        try? await Task.sleep(nanoseconds: 150_000_000)

        guard
            let source = CGEventSource(stateID: .hidSystemState),
            let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: 9,
                keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: 9,
                keyDown: false
            )
        else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
