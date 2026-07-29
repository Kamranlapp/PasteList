import AppKit
@preconcurrency import ApplicationServices
import Combine
import Foundation

enum AccessibilityPasteError: LocalizedError, Equatable {
    case accessRequired

    var errorDescription: String? {
        switch self {
        case .accessRequired:
            """
            KPaste needs Accessibility access to paste into other apps. \
            Grant access in System Settings → Privacy & Security → Accessibility.
            """
        }
    }
}

@MainActor
final class AccessibilityController: ObservableObject {
    @Published private(set) var isTrusted: Bool

    private static let didRequestAccessDefaultsKey = "accessibility.didRequestAccess"

    private let checkTrust: () -> Bool
    private let promptForAccess: () -> Bool
    private var previousApplication: NSRunningApplication?

    init(
        checkTrust: @escaping () -> Bool = { AXIsProcessTrusted() },
        promptForAccess: @escaping () -> Bool = {
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
            ] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
    ) {
        self.checkTrust = checkTrust
        self.promptForAccess = promptForAccess
        isTrusted = checkTrust()
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
        isTrusted = checkTrust()
    }

    func requestAccess() {
        isTrusted = promptForAccess()
    }

    @discardableResult
    func requestAccessOnFirstLaunchIfNeeded(
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        guard !userDefaults.bool(forKey: Self.didRequestAccessDefaultsKey) else {
            return false
        }

        userDefaults.set(true, forKey: Self.didRequestAccessDefaultsKey)
        refreshTrust()
        guard !isTrusted else {
            return false
        }

        requestAccess()
        return true
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
    func pasteIntoPreviousApplication() async throws -> Bool {
        refreshTrust()
        guard isTrusted else {
            throw AccessibilityPasteError.accessRequired
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
