import AppKit
import Combine
import CoreGraphics
import Foundation

private func postCommandVPasteEvent() -> Bool {
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

enum PasteAutomationResult: Equatable {
    case pastedAutomatically
    case copiedForManualPaste
}

@MainActor
final class PasteAutomationController: ObservableObject {
    struct TargetApplication {
        let processIdentifier: pid_t
        let bundleIdentifier: String?
        let isTerminated: () -> Bool
        let activate: () -> Bool
    }

    @Published private(set) var isPostEventAuthorized: Bool

    private let preflightPostEventAccess: () -> Bool
    private let requestPostEventAccess: () -> Bool
    private let frontmostApplication: () -> TargetApplication?
    private let isApplicationFrontmost: (pid_t) -> Bool
    private let postCommandV: () -> Bool
    private let waitBeforePosting: () async -> Void
    private var previousApplication: TargetApplication?

    init(
        preflightPostEventAccess: @escaping () -> Bool = {
            CGPreflightPostEventAccess()
        },
        requestPostEventAccess: @escaping () -> Bool = {
            CGRequestPostEventAccess()
        },
        frontmostApplication: @escaping () -> TargetApplication? = {
            guard let application = NSWorkspace.shared.frontmostApplication else {
                return nil
            }
            return TargetApplication(
                processIdentifier: application.processIdentifier,
                bundleIdentifier: application.bundleIdentifier,
                isTerminated: { application.isTerminated },
                activate: {
                    application.activate(options: [.activateIgnoringOtherApps])
                }
            )
        },
        isApplicationFrontmost: @escaping (pid_t) -> Bool = { processIdentifier in
            NSWorkspace.shared.frontmostApplication?.processIdentifier == processIdentifier
        },
        postCommandV: @escaping () -> Bool = postCommandVPasteEvent,
        waitBeforePosting: @escaping () async -> Void = {
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
    ) {
        self.preflightPostEventAccess = preflightPostEventAccess
        self.requestPostEventAccess = requestPostEventAccess
        self.frontmostApplication = frontmostApplication
        self.isApplicationFrontmost = isApplicationFrontmost
        self.postCommandV = postCommandV
        self.waitBeforePosting = waitBeforePosting
        isPostEventAuthorized = preflightPostEventAccess()
    }

    func rememberFrontmostApplication() {
        guard
            let application = frontmostApplication(),
            application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
            application.bundleIdentifier != AppConfiguration.bundleIdentifier
        else {
            return
        }
        previousApplication = application
    }

    func refreshAuthorization() {
        isPostEventAuthorized = preflightPostEventAccess()
    }

    /// This is the only method that may display the system PostEvent prompt.
    /// Call it exclusively from an explicit user action.
    func requestAuthorization() {
        isPostEventAuthorized = requestPostEventAccess()
    }

    func openPostEventSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func pasteIntoPreviousApplication() async -> PasteAutomationResult {
        guard
            let application = previousApplication,
            !application.isTerminated(),
            application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
            application.bundleIdentifier != AppConfiguration.bundleIdentifier
        else {
            return .copiedForManualPaste
        }

        guard application.activate() else {
            return .copiedForManualPaste
        }
        refreshAuthorization()
        guard isPostEventAuthorized else {
            return .copiedForManualPaste
        }

        await waitBeforePosting()
        guard isApplicationFrontmost(application.processIdentifier) else {
            return .copiedForManualPaste
        }
        return postCommandV()
            ? .pastedAutomatically
            : .copiedForManualPaste
    }
}
