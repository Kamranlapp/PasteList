import AppKit
import Combine
import CoreGraphics
import Foundation
import OSLog

enum EventPostingRoute: Equatable {
    case session
    case hid

    var tapLocation: CGEventTapLocation {
        switch self {
        case .session:
            return .cgSessionEventTap
        case .hid:
            return .cghidEventTap
        }
    }
}

enum PostEventPermissionState: Equatable {
    case granted
    case notGranted

    init(isGranted: Bool) {
        self = isGranted ? .granted : .notGranted
    }
}

enum PostEventPermissionRequestState: Equatable {
    case idle
    case requesting
    case awaitingSystemApproval
}

@MainActor
struct PostEventPermissionClient {
    let preflight: () -> Bool
    let request: () -> Bool
    let verifyPosting: () async -> EventPostingRoute?

    static let live = PostEventPermissionClient(
        preflight: { CGPreflightPostEventAccess() },
        request: { CGRequestPostEventAccess() },
        verifyPosting: verifyPostEventDelivery
    )
}

private enum PostEventDeliveryProbe {
    static let eventCount = 3
    static let resultDelayNanoseconds: UInt64 = 40_000_000
}

/// Verifies that WindowServer accepted synthetic session events instead of
/// trusting TCC's preflight value alone. macOS 26 can grant the permission in
/// the Accessibility UI while `CGPreflightPostEventAccess` remains false.
/// Both event types are no-ops; requiring both counters to advance prevents
/// normal pointer movement from being mistaken for a successful probe.
private let automaticPasteLogger = Logger(
    subsystem: AppConfiguration.bundleIdentifier,
    category: "AutomaticPaste"
)

private func verifyPostEventDelivery() async -> EventPostingRoute? {
    for route in [EventPostingRoute.session, .hid] {
        if await verifyPostEventDelivery(using: route) {
            automaticPasteLogger.notice("Verified event posting route: \(String(describing: route), privacy: .public)")
            return route
        }
    }
    automaticPasteLogger.notice("No event posting route is currently accepted")
    return nil
}

private func verifyPostEventDelivery(using route: EventPostingRoute) async -> Bool {
    let mouseBefore = CGEventSource.counterForEventType(
        .combinedSessionState,
        eventType: .mouseMoved
    )
    let scrollBefore = CGEventSource.counterForEventType(
        .combinedSessionState,
        eventType: .scrollWheel
    )

    guard let source = CGEventSource(stateID: .hidSystemState) else {
        return false
    }

    for _ in 0..<PostEventDeliveryProbe.eventCount {
        guard
            let mouseEvent = CGEvent(
                mouseEventSource: source,
                mouseType: .mouseMoved,
                mouseCursorPosition: NSEvent.mouseLocation,
                mouseButton: .left
            ),
            let scrollEvent = CGEvent(
                scrollWheelEvent2Source: source,
                units: .pixel,
                wheelCount: 1,
                wheel1: 0,
                wheel2: 0,
                wheel3: 0
            )
        else {
            return false
        }

        mouseEvent.post(tap: route.tapLocation)
        scrollEvent.post(tap: route.tapLocation)
    }

    try? await Task.sleep(nanoseconds: PostEventDeliveryProbe.resultDelayNanoseconds)

    let mouseAfter = CGEventSource.counterForEventType(
        .combinedSessionState,
        eventType: .mouseMoved
    )
    let scrollAfter = CGEventSource.counterForEventType(
        .combinedSessionState,
        eventType: .scrollWheel
    )
    return mouseAfter &- mouseBefore >= PostEventDeliveryProbe.eventCount
        && scrollAfter &- scrollBefore >= PostEventDeliveryProbe.eventCount
}

private func postCommandVPasteEvent(using route: EventPostingRoute) -> Bool {
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
    keyDown.post(tap: route.tapLocation)
    keyUp.post(tap: route.tapLocation)
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

    @Published private(set) var permissionState: PostEventPermissionState
    @Published private(set) var permissionRequestState: PostEventPermissionRequestState = .idle

    var isPostEventAuthorized: Bool {
        permissionState == .granted
    }

    private let permissionClient: PostEventPermissionClient
    private let frontmostApplication: () -> TargetApplication?
    private let isApplicationFrontmost: (pid_t) -> Bool
    private let postCommandV: (EventPostingRoute) -> Bool
    private let waitBeforePosting: () async -> Void
    private let waitAfterPromptProbe: () async -> Void
    private let recordPermissionRequest: () -> Void
    private let backgroundRefreshInterval: TimeInterval
    private let settingsRefreshInterval: TimeInterval
    private var previousApplication: TargetApplication?
    private var authorizationRefreshTask: Task<Void, Never>?
    private var authorizationVerificationTask: Task<EventPostingRoute?, Never>?
    private var applicationDidBecomeActiveCancellable: AnyCancellable?
    private(set) var authorizationRefreshInterval: TimeInterval
    private(set) var authorizationMonitorGeneration = 0
    private var permissionWasRequested: Bool
    private var activePostingRoute: EventPostingRoute?

    init(
        permissionClient: PostEventPermissionClient = .live,
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
        postCommandV: @escaping (EventPostingRoute) -> Bool = postCommandVPasteEvent,
        waitBeforePosting: @escaping () async -> Void = {
            try? await Task.sleep(nanoseconds: 150_000_000)
        },
        waitAfterPromptProbe: @escaping () async -> Void = {
            try? await Task.sleep(nanoseconds: 300_000_000)
        },
        permissionWasRequested: Bool? = nil,
        recordPermissionRequest: @escaping () -> Void = {
            UserDefaults.standard.set(
                true,
                forKey: "postEventPermissionWasRequested"
            )
        },
        backgroundRefreshInterval: TimeInterval = 60,
        settingsRefreshInterval: TimeInterval = 1
    ) {
        self.permissionClient = permissionClient
        self.frontmostApplication = frontmostApplication
        self.isApplicationFrontmost = isApplicationFrontmost
        self.postCommandV = postCommandV
        self.waitBeforePosting = waitBeforePosting
        self.waitAfterPromptProbe = waitAfterPromptProbe
        self.recordPermissionRequest = recordPermissionRequest
        self.backgroundRefreshInterval = backgroundRefreshInterval
        self.settingsRefreshInterval = settingsRefreshInterval
        authorizationRefreshInterval = backgroundRefreshInterval
        self.permissionWasRequested = permissionWasRequested
            ?? UserDefaults.standard.bool(forKey: "postEventPermissionWasRequested")
        let preflightGranted = permissionClient.preflight()
        activePostingRoute = preflightGranted ? .session : nil
        permissionState = PostEventPermissionState(isGranted: preflightGranted)
        applicationDidBecomeActiveCancellable = NotificationCenter.default
            .publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.refreshAuthorizationNow()
                }
            }
        scheduleAuthorizationRefresh(every: authorizationRefreshInterval)
        if permissionWasRequested == nil && self.permissionWasRequested {
            Task { @MainActor [weak self] in
                await self?.refreshAuthorizationNow()
            }
        }
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
        if permissionClient.preflight() {
            applyAuthorization(route: .session)
        } else if permissionWasRequested {
            Task { @MainActor [weak self] in
                await self?.refreshAuthorizationNow()
            }
        } else {
            applyAuthorization(route: nil)
        }
    }

    @discardableResult
    func refreshAuthorizationNow() async -> Bool {
        if permissionClient.preflight() {
            applyAuthorization(route: .session)
            return true
        }
        guard permissionWasRequested else {
            applyAuthorization(route: nil)
            return false
        }

        if let authorizationVerificationTask {
            let route = await authorizationVerificationTask.value
            applyAuthorization(route: route)
            return route != nil
        }

        let verificationTask = Task { @MainActor [permissionClient] in
            await permissionClient.verifyPosting()
        }
        authorizationVerificationTask = verificationTask
        let route = await verificationTask.value
        authorizationVerificationTask = nil
        applyAuthorization(route: route)
        return route != nil
    }

    private func applyAuthorization(route: EventPostingRoute?) {
        activePostingRoute = route
        permissionState = PostEventPermissionState(isGranted: route != nil)
        if route != nil {
            permissionRequestState = .idle
        }
    }

    func setSettingsVisible(_ isVisible: Bool) {
        if isVisible {
            Task { @MainActor [weak self] in
                await self?.refreshAuthorizationNow()
            }
        }
        let interval = isVisible
            ? settingsRefreshInterval
            : backgroundRefreshInterval
        guard interval != authorizationRefreshInterval else { return }
        authorizationRefreshInterval = interval
        scheduleAuthorizationRefresh(every: interval)
    }

    private func scheduleAuthorizationRefresh(every interval: TimeInterval) {
        authorizationRefreshTask?.cancel()
        authorizationMonitorGeneration += 1
        let nanoseconds = UInt64(interval * 1_000_000_000)
        authorizationRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return }
                guard let self else { return }
                await self.refreshAuthorizationNow()
            }
        }
    }

    /// This is the only method that may trigger the system PostEvent prompt.
    /// Call it exclusively from an explicit user action. The probe is posted
    /// only when the direct request did not immediately grant access.
    @discardableResult
    func requestAuthorization() async -> Bool {
        guard permissionRequestState != .requesting else {
            return isPostEventAuthorized
        }

        if await refreshAuthorizationNow() {
            return true
        }

        permissionRequestState = .requesting
        permissionWasRequested = true
        recordPermissionRequest()
        _ = permissionClient.request()
        if await refreshAuthorizationNow() {
            return true
        }

        await waitAfterPromptProbe()
        if !(await refreshAuthorizationNow()) {
            permissionRequestState = .awaitingSystemApproval
            openPostEventSettings()
        }
        return isPostEventAuthorized
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
        guard await refreshAuthorizationNow() else {
            return .copiedForManualPaste
        }

        await waitBeforePosting()
        guard isApplicationFrontmost(application.processIdentifier) else {
            return .copiedForManualPaste
        }
        guard let activePostingRoute else {
            return .copiedForManualPaste
        }
        return postCommandV(activePostingRoute)
            ? .pastedAutomatically
            : .copiedForManualPaste
    }
}
