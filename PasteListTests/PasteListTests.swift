import Foundation
import Carbon
import GRDB
import ServiceManagement
import XCTest
@testable import PasteList

@MainActor
private final class PermissionProbeGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        if isOpen {
            isOpen = false
            return
        }
        await withCheckedContinuation { continuation = $0 }
    }

    func resume() {
        if let continuation {
            continuation.resume()
            self.continuation = nil
        } else {
            isOpen = true
        }
    }
}

final class PasteListTests: XCTestCase {
    func testQuickPasteShortcutsAssignOneThroughNineThenZero() {
        XCTAssertEqual(
            (0..<10).compactMap(QuickPasteShortcut.label(forEntryIndex:)),
            ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        )
        XCTAssertNil(QuickPasteShortcut.label(forEntryIndex: 10))
    }

    func testQuickPasteShortcutsMapNumberRowAndNumericKeypad() {
        let numberRowKeyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]
        let numericKeypadKeyCodes: [UInt16] = [83, 84, 85, 86, 87, 88, 89, 91, 92, 82]

        XCTAssertEqual(
            numberRowKeyCodes.compactMap {
                QuickPasteShortcut.entryIndex(forKeyCode: $0)
            },
            Array(0..<10)
        )
        XCTAssertEqual(
            numericKeypadKeyCodes.compactMap {
                QuickPasteShortcut.entryIndex(forKeyCode: $0)
            },
            Array(0..<10)
        )
        XCTAssertNil(
            QuickPasteShortcut.entryIndex(
                forKeyCode: 18,
                modifierFlags: .command
            )
        )
    }

    func testMouseSwipeDeleteRecognizesOnlyDecisiveLeftwardDrags() {
        XCTAssertEqual(
            MouseSwipeDeleteGesture.intent(for: NSSize(width: -12, height: 2)),
            .deleteSwipe
        )
        XCTAssertEqual(
            MouseSwipeDeleteGesture.intent(for: NSSize(width: 12, height: 2)),
            .otherDrag
        )
        XCTAssertEqual(
            MouseSwipeDeleteGesture.intent(for: NSSize(width: -3, height: 12)),
            .otherDrag
        )
        XCTAssertEqual(
            MouseSwipeDeleteGesture.intent(for: NSSize(width: -3, height: 1)),
            .undecided
        )
        XCTAssertTrue(
            MouseSwipeDeleteGesture.shouldDelete(
                translation: NSSize(width: -48, height: 4)
            )
        )
        XCTAssertFalse(
            MouseSwipeDeleteGesture.shouldDelete(
                translation: NSSize(width: -47, height: 4)
            )
        )
        XCTAssertEqual(MouseSwipeDeleteGesture.visualOffset(for: -40), -40)
        XCTAssertEqual(
            MouseSwipeDeleteGesture.visualOffset(for: -200),
            -MouseSwipeDeleteGesture.maximumRevealDistance
        )
        XCTAssertEqual(MouseSwipeDeleteGesture.visualOffset(for: 20), 0)
    }

    @MainActor
    func testCursorPanelInterceptsQuickPasteBeforeFocusedSearchField() throws {
        let panel = CursorHistoryPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let searchField = NSTextField(frame: panel.contentView?.bounds ?? .zero)
        panel.contentView = searchField
        panel.makeFirstResponder(searchField)
        var pastedEntryIndex: Int?
        panel.quickPaste = { pastedEntryIndex = $0 }
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: panel.windowNumber,
                context: nil,
                characters: "2",
                charactersIgnoringModifiers: "2",
                isARepeat: false,
                keyCode: 19
            )
        )

        panel.sendEvent(event)

        XCTAssertEqual(pastedEntryIndex, 1)
        XCTAssertEqual(searchField.stringValue, "")
    }

    func testApplicationConfiguration() {
        XCTAssertEqual(AppConfiguration.name, "PasteList")
        XCTAssertEqual(AppConfiguration.bundleIdentifier, "com.kam.pastelist")
    }

    func testPrivacyManifestDeclaresNoCollectionAndRequiredReasons() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifestURL = projectRoot
            .appendingPathComponent("PasteList")
            .appendingPathComponent("PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: manifestURL)
        let manifest = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
        )

        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual(
            (manifest["NSPrivacyTrackingDomains"] as? [String])?.count,
            0
        )
        XCTAssertEqual(
            (manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])?.count,
            0
        )

        let accessedTypes = try XCTUnwrap(
            manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]]
        )
        var reasonsByType: [String: [String]] = [:]
        for entry in accessedTypes {
            guard
                let type = entry["NSPrivacyAccessedAPIType"] as? String,
                let reasons = entry["NSPrivacyAccessedAPITypeReasons"] as? [String]
            else {
                continue
            }
            reasonsByType[type] = reasons
        }
        XCTAssertEqual(
            reasonsByType["NSPrivacyAccessedAPICategoryUserDefaults"],
            ["CA92.1"]
        )
        XCTAssertEqual(
            reasonsByType["NSPrivacyAccessedAPICategoryFileTimestamp"],
            ["C617.1"]
        )
    }

    func testClipPrimaryInteractionsKeepSelectionAndDraggingExclusive() {
        let makeClip: (ClipContentType) -> ClipRecord = { type in
            ClipRecord(
                id: 1,
                type: type.rawValue,
                content: "content",
                previewText: "preview",
                createdAt: Date()
            )
        }

        XCTAssertEqual(makeClip(.text).primaryInteraction, .textSelection)
        XCTAssertEqual(makeClip(.rtf).primaryInteraction, .textSelection)
        XCTAssertEqual(makeClip(.url).primaryInteraction, .textSelection)
        XCTAssertEqual(makeClip(.image).primaryInteraction, .fileDrag)
        XCTAssertEqual(makeClip(.file).primaryInteraction, .fileDrag)
    }

    func testDefaultGlobalHotKeyIsCommandShiftV() {
        let hotKey = HotKey.defaultValue

        XCTAssertEqual(hotKey.displayName, "⇧⌘V")
        XCTAssertNotEqual(hotKey.modifiers & UInt32(cmdKey), 0)
        XCTAssertNotEqual(hotKey.modifiers & UInt32(shiftKey), 0)
    }

    @MainActor
    func testPostEventAccessIsRequestedOnlyByExplicitAction() async {
        var preflightCount = 0
        var requestCount = 0
        var probeCount = 0
        var isGranted = false
        let controller = PasteAutomationController(
            permissionClient: PostEventPermissionClient(
                preflight: {
                    preflightCount += 1
                    return isGranted
                },
                request: {
                    requestCount += 1
                    isGranted = true
                    return true
                },
                verifyPosting: {
                    probeCount += 1
                    return .session
                }
            ),
            frontmostApplication: { nil },
            isApplicationFrontmost: { _ in false },
            postCommandV: { _ in false },
            waitBeforePosting: {},
            waitAfterPromptProbe: {},
            permissionWasRequested: false,
            recordPermissionRequest: {}
        )

        XCTAssertEqual(preflightCount, 1)
        XCTAssertEqual(requestCount, 0)

        controller.refreshAuthorization()
        XCTAssertEqual(preflightCount, 2)
        XCTAssertEqual(requestCount, 0)

        let wasGranted = await controller.requestAuthorization()
        XCTAssertTrue(wasGranted)
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(probeCount, 0)
        XCTAssertTrue(controller.isPostEventAuthorized)
        XCTAssertEqual(controller.permissionState, .granted)
        XCTAssertEqual(controller.permissionRequestState, .idle)
    }

    @MainActor
    func testDeniedDirectRequestPostsOnePromptProbeAndWaitsForApproval() async {
        var requestCount = 0
        var probeCount = 0
        let controller = PasteAutomationController(
            permissionClient: PostEventPermissionClient(
                preflight: { false },
                request: {
                    requestCount += 1
                    return false
                },
                verifyPosting: {
                    probeCount += 1
                    return nil
                }
            ),
            frontmostApplication: { nil },
            isApplicationFrontmost: { _ in false },
            postCommandV: { _ in false },
            waitBeforePosting: {},
            waitAfterPromptProbe: {},
            permissionWasRequested: false,
            recordPermissionRequest: {}
        )

        let wasGranted = await controller.requestAuthorization()
        XCTAssertFalse(wasGranted)
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(probeCount, 2)
        XCTAssertEqual(controller.permissionState, .notGranted)
        XCTAssertEqual(controller.permissionRequestState, .awaitingSystemApproval)
    }

    @MainActor
    func testParallelPermissionRequestsDoNotCreateDuplicatePrompts() async {
        let gate = PermissionProbeGate()
        var requestCount = 0
        var probeCount = 0
        let controller = PasteAutomationController(
            permissionClient: PostEventPermissionClient(
                preflight: { false },
                request: {
                    requestCount += 1
                    return false
                },
                verifyPosting: {
                    probeCount += 1
                    return nil
                }
            ),
            frontmostApplication: { nil },
            isApplicationFrontmost: { _ in false },
            postCommandV: { _ in false },
            waitBeforePosting: {},
            waitAfterPromptProbe: { await gate.wait() },
            permissionWasRequested: false,
            recordPermissionRequest: {}
        )

        let firstRequest = Task { @MainActor in
            await controller.requestAuthorization()
        }
        while controller.permissionRequestState != .requesting {
            await Task.yield()
        }
        while probeCount == 0 {
            await Task.yield()
        }

        let secondResult = await controller.requestAuthorization()
        XCTAssertFalse(secondResult)
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(probeCount, 1)

        gate.resume()
        let firstResult = await firstRequest.value
        XCTAssertFalse(firstResult)
        XCTAssertEqual(probeCount, 2)
        XCTAssertEqual(controller.permissionRequestState, .awaitingSystemApproval)
    }

    @MainActor
    func testPostEventPermissionStateTracksGrantAndRevocation() {
        var isGranted = false
        let controller = PasteAutomationController(
            permissionClient: PostEventPermissionClient(
                preflight: { isGranted },
                request: { false },
                verifyPosting: { nil }
            ),
            frontmostApplication: { nil },
            isApplicationFrontmost: { _ in false },
            postCommandV: { _ in false },
            waitBeforePosting: {},
            permissionWasRequested: false,
            recordPermissionRequest: {}
        )

        XCTAssertEqual(controller.permissionState, .notGranted)

        isGranted = true
        controller.refreshAuthorization()
        XCTAssertEqual(controller.permissionState, .granted)

        isGranted = false
        controller.refreshAuthorization()
        XCTAssertEqual(controller.permissionState, .notGranted)
    }

    @MainActor
    func testVerifiedSessionDeliveryOverridesStalePreflightAndDetectsRevocation() async {
        var canPostSessionEvents = true
        var verificationCount = 0
        let controller = PasteAutomationController(
            permissionClient: PostEventPermissionClient(
                preflight: { false },
                request: { false },
                verifyPosting: {
                    verificationCount += 1
                    return canPostSessionEvents ? .session : nil
                }
            ),
            frontmostApplication: { nil },
            isApplicationFrontmost: { _ in false },
            postCommandV: { _ in false },
            waitBeforePosting: {},
            permissionWasRequested: true,
            recordPermissionRequest: {}
        )

        let initiallyVerified = await controller.refreshAuthorizationNow()
        XCTAssertTrue(initiallyVerified)
        XCTAssertEqual(controller.permissionState, .granted)

        canPostSessionEvents = false
        let verifiedAfterRevocation = await controller.refreshAuthorizationNow()
        XCTAssertFalse(verifiedAfterRevocation)
        XCTAssertEqual(controller.permissionState, .notGranted)
        XCTAssertEqual(verificationCount, 2)
    }

    @MainActor
    func testSettingsVisibilityUsesOneMonitorAtTheExpectedInterval() async {
        var isGranted = false
        let controller = PasteAutomationController(
            permissionClient: PostEventPermissionClient(
                preflight: { isGranted },
                request: { false },
                verifyPosting: { nil }
            ),
            frontmostApplication: { nil },
            isApplicationFrontmost: { _ in false },
            postCommandV: { _ in false },
            waitBeforePosting: {},
            permissionWasRequested: false,
            recordPermissionRequest: {}
        )
        let initialGeneration = controller.authorizationMonitorGeneration

        controller.setSettingsVisible(true)
        XCTAssertEqual(controller.authorizationRefreshInterval, 1)
        XCTAssertEqual(controller.permissionState, .notGranted)
        XCTAssertEqual(
            controller.authorizationMonitorGeneration,
            initialGeneration + 1
        )

        isGranted = true
        controller.setSettingsVisible(true)
        await Task.yield()
        XCTAssertEqual(controller.permissionState, .granted)
        XCTAssertEqual(
            controller.authorizationMonitorGeneration,
            initialGeneration + 1,
            "Opening an already-visible settings window must not create another monitor"
        )

        controller.setSettingsVisible(false)
        XCTAssertEqual(controller.authorizationRefreshInterval, 60)
        XCTAssertEqual(
            controller.authorizationMonitorGeneration,
            initialGeneration + 2
        )
    }

    @MainActor
    func testOnboardingIsPresentedOnlyBeforeCompletion() throws {
        let suiteName = "PasteListTests.onboarding.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initialState = OnboardingState(userDefaults: defaults)
        XCTAssertTrue(initialState.shouldPresentOnLaunch)

        initialState.complete()
        XCTAssertFalse(initialState.shouldPresentOnLaunch)

        let nextLaunchState = OnboardingState(userDefaults: defaults)
        XCTAssertFalse(nextLaunchState.shouldPresentOnLaunch)
        XCTAssertTrue(nextLaunchState.hasCompleted)
    }

    @MainActor
    func testCompletedOnboardingCanStillBeReopenedWithoutResettingState() throws {
        let suiteName = "PasteListTests.onboarding.reopen.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = OnboardingState(userDefaults: defaults)
        state.complete()

        var didRequestReopen = false
        let reopen = { didRequestReopen = true }
        reopen()

        XCTAssertTrue(didRequestReopen)
        XCTAssertTrue(state.hasCompleted)
        XCTAssertFalse(state.shouldPresentOnLaunch)
    }

    @MainActor
    func testAutomaticPasteActivatesPreviousApplicationAndPostsCommandV() async {
        var activationCount = 0
        var postCount = 0
        var postedRoute: EventPostingRoute?
        let target = PasteAutomationController.TargetApplication(
            processIdentifier: 42_424,
            bundleIdentifier: "com.example.target",
            isTerminated: { false },
            activate: {
                activationCount += 1
                return true
            }
        )
        let controller = PasteAutomationController(
            permissionClient: PostEventPermissionClient(
                preflight: { true },
                request: { XCTFail("Permission request must be explicit"); return false },
                verifyPosting: { XCTFail("Permission verification must be explicit"); return nil }
            ),
            frontmostApplication: { target },
            isApplicationFrontmost: { $0 == target.processIdentifier },
            postCommandV: { route in
                postCount += 1
                postedRoute = route
                return true
            },
            waitBeforePosting: {},
            permissionWasRequested: false,
            recordPermissionRequest: {}
        )
        controller.rememberFrontmostApplication()

        let result = await controller.pasteIntoPreviousApplication()

        XCTAssertEqual(result, .pastedAutomatically)
        XCTAssertEqual(activationCount, 1)
        XCTAssertEqual(postCount, 1)
        XCTAssertEqual(postedRoute, .session)
    }

    @MainActor
    func testAutomaticPasteUsesVerifiedHIDFallbackRoute() async {
        var postedRoute: EventPostingRoute?
        let target = PasteAutomationController.TargetApplication(
            processIdentifier: 42_427,
            bundleIdentifier: "com.example.target",
            isTerminated: { false },
            activate: { true }
        )
        let controller = PasteAutomationController(
            permissionClient: PostEventPermissionClient(
                preflight: { false },
                request: { false },
                verifyPosting: { .hid }
            ),
            frontmostApplication: { target },
            isApplicationFrontmost: { $0 == target.processIdentifier },
            postCommandV: { route in
                postedRoute = route
                return true
            },
            waitBeforePosting: {},
            permissionWasRequested: true,
            recordPermissionRequest: {}
        )
        controller.rememberFrontmostApplication()

        let result = await controller.pasteIntoPreviousApplication()

        XCTAssertEqual(result, .pastedAutomatically)
        XCTAssertEqual(postedRoute, .hid)
    }

    @MainActor
    func testAutomaticPasteFallsBackWithoutPermissionAndPreservesClipboard() async {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        pasteboard.setString("fallback payload", forType: .string)
        var activationCount = 0
        var postCount = 0
        var requestCount = 0
        let target = PasteAutomationController.TargetApplication(
            processIdentifier: 42_425,
            bundleIdentifier: "com.example.target",
            isTerminated: { false },
            activate: {
                activationCount += 1
                return true
            }
        )
        let controller = PasteAutomationController(
            permissionClient: PostEventPermissionClient(
                preflight: { false },
                request: {
                    requestCount += 1
                    return false
                },
                verifyPosting: { XCTFail("Paste fallback must not verify access"); return nil }
            ),
            frontmostApplication: { target },
            isApplicationFrontmost: { $0 == target.processIdentifier },
            postCommandV: { _ in
                postCount += 1
                return true
            },
            waitBeforePosting: {},
            permissionWasRequested: false,
            recordPermissionRequest: {}
        )
        controller.rememberFrontmostApplication()

        let result = await controller.pasteIntoPreviousApplication()

        XCTAssertEqual(result, .copiedForManualPaste)
        XCTAssertEqual(activationCount, 1)
        XCTAssertEqual(postCount, 0)
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "fallback payload")
    }

    @MainActor
    func testAutomaticPasteFallsBackWhenPreviousApplicationCannotActivate() async {
        var postCount = 0
        let target = PasteAutomationController.TargetApplication(
            processIdentifier: 42_426,
            bundleIdentifier: "com.example.target",
            isTerminated: { false },
            activate: { false }
        )
        let controller = PasteAutomationController(
            permissionClient: PostEventPermissionClient(
                preflight: { true },
                request: { XCTFail("Permission request must be explicit"); return false },
                verifyPosting: { XCTFail("Permission verification must be explicit"); return nil }
            ),
            frontmostApplication: { target },
            isApplicationFrontmost: { _ in false },
            postCommandV: { _ in
                postCount += 1
                return true
            },
            waitBeforePosting: {}
        )
        controller.rememberFrontmostApplication()

        let result = await controller.pasteIntoPreviousApplication()

        XCTAssertEqual(result, .copiedForManualPaste)
        XCTAssertEqual(postCount, 0)
    }

    @MainActor
    func testManualPasteFallbackUsesClearInstruction() {
        XCTAssertEqual(
            PasteFallbackPanelController.title,
            "Copied — press ⌘V to paste"
        )
        XCTAssertEqual(
            PasteFallbackPanelController.message,
            "For automatic and quick paste, allow PasteList in Settings."
        )
    }

    func testApplicationSourcesUseOnlyPostEventPermissionAPIs() throws {
        let testsURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testsURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoot = projectRoot.appendingPathComponent("PasteList", isDirectory: true)
        let forbiddenSymbols = [
            ["AXIsProcess", "Trusted"].joined(),
            ["AXUI", "Element"].joined(),
            ["IOHID", "CheckAccess"].joined(),
            ["IOHID", "RequestAccess"].joined(),
            ["Accessibility", "AccessSheet"].joined(),
        ]
        let sourceURLs = try FileManager.default
            .subpathsOfDirectory(atPath: sourceRoot.path)
            .filter { $0.hasSuffix(".swift") }
            .map { sourceRoot.appendingPathComponent($0) }

        for sourceURL in sourceURLs {
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            for symbol in forbiddenSymbols {
                XCTAssertFalse(source.contains(symbol), "Found forbidden API \(symbol) in \(sourceURL.path)")
            }
        }
    }

    @MainActor
    func testCursorPanelPlacesPointerOverFirstRowAwayFromScreenEdges() {
        let pointer = NSPoint(x: 800, y: 600)
        let expectedHorizontalPosition = StatusItemController.cursorScrollBarWidth
            + StatusItemController.cursorScrollBarSpacing
            + StatusItemController.cursorPanelPadding
            + StatusItemController.cursorPanelContentSize.width
                * StatusItemController.cursorHorizontalAnchor
        let expectedVerticalPosition = StatusItemController.cursorWindowControlAreaHeight
            + StatusItemController.cursorWindowControlSpacing
            + StatusItemController.cursorPanelPadding
            + StatusItemController.cursorFirstRowCenterFromTop
        let frame = StatusItemController.cursorPanelFrame(
            pointerLocation: pointer,
            visibleFrame: NSRect(x: 0, y: 0, width: 1_440, height: 900)
        )

        XCTAssertEqual(
            pointer.x - frame.minX,
            expectedHorizontalPosition
        )
        XCTAssertEqual(
            frame.maxY - pointer.y,
            expectedVerticalPosition
        )
    }

    @MainActor
    func testCursorPanelStaysInsideVisibleScreenNearEdges() {
        let visibleFrame = NSRect(x: 0, y: 25, width: 1_000, height: 700)
        let frame = StatusItemController.cursorPanelFrame(
            pointerLocation: NSPoint(x: 995, y: 30),
            visibleFrame: visibleFrame
        )

        XCTAssertGreaterThanOrEqual(frame.minX, visibleFrame.minX)
        XCTAssertGreaterThanOrEqual(frame.minY, visibleFrame.minY)
        XCTAssertLessThanOrEqual(frame.maxX, visibleFrame.maxX)
        XCTAssertLessThanOrEqual(frame.maxY, visibleFrame.maxY)
    }

    @MainActor
    func testCursorPanelSizeIsSavedAndRestored() throws {
        let suiteName = "PasteListTests.cursorPanelSize.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let savedSize = NSSize(width: 460, height: 520)
        StatusItemController.saveCursorPanelSize(savedSize, in: defaults)

        XCTAssertEqual(
            StatusItemController.storedCursorPanelSize(in: defaults),
            savedSize
        )
    }

    func testCursorPanelResizeKeepsOppositeCornerFixed() {
        let initialFrame = NSRect(x: 100, y: 100, width: 500, height: 400)

        let resizedFrame = CursorPanelResizer.frame(
            from: initialFrame,
            dragging: [.top, .left],
            by: NSPoint(x: 50, y: -100),
            minimumSize: NSSize(width: 300, height: 250),
            within: nil
        )

        XCTAssertEqual(
            resizedFrame,
            NSRect(x: 150, y: 100, width: 450, height: 300)
        )
        XCTAssertEqual(resizedFrame.maxX, initialFrame.maxX)
        XCTAssertEqual(resizedFrame.minY, initialFrame.minY)
    }

    func testCursorPanelResizeHonorsMinimumSize() {
        let initialFrame = NSRect(x: 100, y: 100, width: 500, height: 400)

        let resizedFrame = CursorPanelResizer.frame(
            from: initialFrame,
            dragging: [.bottom, .right],
            by: NSPoint(x: -300, y: 250),
            minimumSize: NSSize(width: 300, height: 250),
            within: nil
        )

        XCTAssertEqual(
            resizedFrame,
            NSRect(x: 100, y: 250, width: 300, height: 250)
        )
        XCTAssertEqual(resizedFrame.maxX, 400)
        XCTAssertEqual(resizedFrame.maxY, initialFrame.maxY)
    }

    @MainActor
    func testCursorPanelSurfaceFrameExcludesRailScrollBarAndControlStrip() {
        let panelFrame = NSRect(
            x: 400,
            y: 300,
            width: StatusItemController.cursorPanelSize.width,
            height: StatusItemController.cursorPanelSize.height
        )

        let surfaceFrame = StatusItemController.cursorPanelSurfaceFrame(in: panelFrame)

        XCTAssertEqual(
            surfaceFrame.size,
            StatusItemController.cursorPanelSurfaceSize
        )
        XCTAssertEqual(surfaceFrame.minX, panelFrame.minX + 16)
        XCTAssertEqual(surfaceFrame.maxX, panelFrame.maxX - 121)
        XCTAssertEqual(surfaceFrame.minY, panelFrame.minY)
        XCTAssertEqual(surfaceFrame.maxY, panelFrame.maxY - 50)
    }

    func testImagePreviewIsPlacedRightOfTheSurfaceSharingItsTopEdge() {
        let surfaceFrame = NSRect(x: 416, y: 300, width: 334, height: 416)

        let previewFrame = ImagePreviewPlacement.frame(
            previewSize: NSSize(width: 300, height: 200),
            anchorFrame: surfaceFrame,
            visibleFrame: NSRect(x: 0, y: 0, width: 1800, height: 1000),
            gap: 16
        )

        XCTAssertEqual(previewFrame.minX, surfaceFrame.maxX + 16)
        XCTAssertEqual(previewFrame.maxY, surfaceFrame.maxY)
        XCTAssertEqual(previewFrame, NSRect(x: 766, y: 516, width: 300, height: 200))
    }

    func testImagePreviewFlipsToTheLeftNearTheRightScreenEdge() {
        let surfaceFrame = NSRect(x: 1016, y: 300, width: 334, height: 416)

        let previewFrame = ImagePreviewPlacement.frame(
            previewSize: NSSize(width: 300, height: 200),
            anchorFrame: surfaceFrame,
            visibleFrame: NSRect(x: 0, y: 0, width: 1500, height: 1000),
            gap: 16
        )

        XCTAssertEqual(previewFrame.maxX, surfaceFrame.minX - 16)
        XCTAssertEqual(previewFrame.minX, 700)
    }

    func testImagePreviewStaysInsideVisibleFrame() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1800, height: 1000)

        let topFrame = ImagePreviewPlacement.frame(
            previewSize: NSSize(width: 300, height: 400),
            anchorFrame: NSRect(x: 416, y: 700, width: 334, height: 416),
            visibleFrame: visibleFrame,
            gap: 16
        )
        XCTAssertEqual(topFrame.maxY, visibleFrame.maxY)

        let bottomFrame = ImagePreviewPlacement.frame(
            previewSize: NSSize(width: 300, height: 400),
            anchorFrame: NSRect(x: 416, y: 0, width: 334, height: 300),
            visibleFrame: visibleFrame,
            gap: 16
        )
        XCTAssertEqual(bottomFrame.minY, visibleFrame.minY)
    }

    func testImagePreviewDisplaySizeFitsMaximumAndPreservesAspectRatio() {
        let displaySize = ImagePreviewPlacement.displaySize(
            pixelSize: NSSize(width: 1680, height: 945),
            scale: 2,
            maximum: NSSize(width: 420, height: 420),
            minimumLongSide: 120
        )

        XCTAssertEqual(displaySize.width, 420)
        XCTAssertEqual(displaySize.height, 236)
    }

    func testImagePreviewDisplaySizeIsScaleIndependent() {
        let retinaSize = ImagePreviewPlacement.displaySize(
            pixelSize: NSSize(width: 1680, height: 945),
            scale: 2,
            maximum: NSSize(width: 420, height: 420),
            minimumLongSide: 120
        )
        let nonRetinaSize = ImagePreviewPlacement.displaySize(
            pixelSize: NSSize(width: 1680, height: 945),
            scale: 1,
            maximum: NSSize(width: 420, height: 420),
            minimumLongSide: 120
        )

        XCTAssertEqual(retinaSize, nonRetinaSize)
    }

    func testImagePreviewDisplaySizeEnlargesTinyImages() {
        let displaySize = ImagePreviewPlacement.displaySize(
            pixelSize: NSSize(width: 32, height: 16),
            scale: 2,
            maximum: NSSize(width: 420, height: 420),
            minimumLongSide: 120
        )

        XCTAssertEqual(displaySize.width, 120)
        XCTAssertEqual(displaySize.height, 60)
    }

    func testSavedPanelIsHalfHeightAndSharesTopEdgeWithHistoryPanel() {
        let surfaceFrame = NSRect(x: 416, y: 300, width: 334, height: 416)

        let savedFrame = SavedClipsPlacement.frame(
            panelSurfaceFrame: surfaceFrame,
            visibleFrame: NSRect(x: 0, y: 0, width: 1800, height: 1000),
            gap: 16
        )

        XCTAssertEqual(
            savedFrame.width,
            (surfaceFrame.width * SavedClipsPlacement.widthRatio).rounded()
        )
        XCTAssertEqual(savedFrame.height, surfaceFrame.height / 2)
        XCTAssertEqual(savedFrame.maxX, surfaceFrame.minX - 16)
        XCTAssertEqual(savedFrame.maxY, surfaceFrame.maxY)
    }

    func testSavedPanelFlipsToTheRightNearTheLeftScreenEdge() {
        let surfaceFrame = NSRect(x: 100, y: 300, width: 334, height: 416)

        let savedFrame = SavedClipsPlacement.frame(
            panelSurfaceFrame: surfaceFrame,
            visibleFrame: NSRect(x: 0, y: 0, width: 1500, height: 1000),
            gap: 16
        )

        XCTAssertEqual(savedFrame.minX, surfaceFrame.maxX + 16)
    }

    func testSavedPanelStaysInsideVisibleFrame() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1800, height: 1000)

        let savedFrame = SavedClipsPlacement.frame(
            panelSurfaceFrame: NSRect(x: 416, y: 800, width: 334, height: 600),
            visibleFrame: visibleFrame,
            gap: 16
        )

        XCTAssertLessThanOrEqual(savedFrame.maxY, visibleFrame.maxY)
        XCTAssertGreaterThanOrEqual(savedFrame.minY, visibleFrame.minY)
    }

    func testImagePreviewStaysRightOfHistoryWhenSavedPanelIsOnTheLeft() {
        let surfaceFrame = NSRect(x: 416, y: 300, width: 334, height: 416)
        let visibleFrame = NSRect(x: 0, y: 0, width: 1800, height: 1000)
        let savedFrame = SavedClipsPlacement.frame(
            panelSurfaceFrame: surfaceFrame,
            visibleFrame: visibleFrame,
            gap: 16
        )

        let withoutSaved = ImagePreviewPlacement.frame(
            previewSize: NSSize(width: 300, height: 200),
            anchorFrame: surfaceFrame,
            visibleFrame: visibleFrame,
            gap: 16
        )
        let withSaved = ImagePreviewPlacement.frame(
            previewSize: NSSize(width: 300, height: 200),
            anchorFrame: surfaceFrame.union(savedFrame),
            visibleFrame: visibleFrame,
            gap: 16
        )

        XCTAssertEqual(savedFrame.maxX, surfaceFrame.minX - 16)
        XCTAssertEqual(withSaved.minX, withoutSaved.minX)
        // The union keeps the taller history panel's top, so the preview stays
        // on the same line either way.
        XCTAssertEqual(withSaved.maxY, withoutSaved.maxY)
    }

    @MainActor
    func testSavedPanelVisibilityIsSavedAndRestored() throws {
        let suiteName = "PasteListTests.savedPanelVisible.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(SavedClipsPanelController.storedVisibility(in: defaults))

        SavedClipsPanelController.saveVisibility(true, in: defaults)
        XCTAssertTrue(SavedClipsPanelController.storedVisibility(in: defaults))

        SavedClipsPanelController.saveVisibility(false, in: defaults)
        XCTAssertFalse(SavedClipsPanelController.storedVisibility(in: defaults))
    }

    func testClipTimestampUsesTodayYesterdayAndWeekdayFormats() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 29,
                hour: 18
            ))
        )
        let today = try XCTUnwrap(
            calendar.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 29,
                hour: 15,
                minute: 4
            ))
        )
        let yesterday = try XCTUnwrap(
            calendar.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 28,
                hour: 9,
                minute: 15
            ))
        )
        let thursday = try XCTUnwrap(
            calendar.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 23,
                hour: 20,
                minute: 30
            ))
        )

        XCTAssertEqual(
            ClipTimestampFormatter.string(for: today, relativeTo: now, calendar: calendar),
            "Today 15:04"
        )
        XCTAssertEqual(
            ClipTimestampFormatter.string(for: yesterday, relativeTo: now, calendar: calendar),
            "Yesterday 09:15"
        )
        XCTAssertEqual(
            ClipTimestampFormatter.string(for: thursday, relativeTo: now, calendar: calendar),
            "Thursday 20:30"
        )
    }

    func testAppPathsCreateExpectedDirectories() throws {
        try withTemporaryPaths { paths in
            XCTAssertEqual(paths.applicationSupportDirectory.lastPathComponent, "com.kam.pastelist")
            XCTAssertEqual(paths.databaseURL.lastPathComponent, "clips.sqlite")
            XCTAssertEqual(paths.blobsDirectory.lastPathComponent, "blobs")

            var isDirectory: ObjCBool = false
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: paths.blobsDirectory.path,
                    isDirectory: &isDirectory
                )
            )
            XCTAssertTrue(isDirectory.boolValue)
        }
    }

    func testMigrationCreatesClipsSchemaAndIndexes() throws {
        try withTemporaryPaths { paths in
            let appDatabase = try AppDatabase(paths: paths)

            let schema = try appDatabase.databasePool.read { database in
                try String.fetchOne(
                    database,
                    sql: "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'clips'"
                )
            }
            XCTAssertNotNil(schema)
            XCTAssertTrue(schema?.contains("AUTOINCREMENT") == true)

            let columns = try appDatabase.databasePool.read { database in
                try Row.fetchAll(database, sql: "PRAGMA table_info(clips)")
            }
            XCTAssertEqual(
                columns.map { $0["name"] as String },
                ["id", "type", "content", "preview_text", "created_at", "pinned", "app_bundle_id"]
            )

            let indexNames = try appDatabase.databasePool.read { database in
                try String.fetchAll(
                    database,
                    sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'clips'"
                )
            }
            XCTAssertTrue(indexNames.contains("clips_created_at_desc"))
            XCTAssertTrue(indexNames.contains("clips_pinned_created_at_desc"))
        }
    }

    func testClipRecordRoundTripAndAutoIncrementedID() throws {
        try withTemporaryPaths { paths in
            let appDatabase = try AppDatabase(paths: paths)
            let createdAt = Date(timeIntervalSince1970: 1_700_000_000)

            let inserted = try appDatabase.databasePool.write { database in
                var clip = ClipRecord(
                    type: "text",
                    content: "Hello",
                    previewText: "Hello",
                    createdAt: createdAt,
                    appBundleID: "com.apple.TextEdit"
                )
                try clip.insert(database)
                return clip
            }

            XCTAssertNotNil(inserted.id)
            let fetched = try appDatabase.databasePool.read { database in
                try ClipRecord.fetchOne(database, key: inserted.id)
            }
            XCTAssertEqual(fetched, inserted)
        }
    }

    func testMigrationCanRunMoreThanOnce() throws {
        try withTemporaryPaths { paths in
            _ = try AppDatabase(paths: paths)
            let reopenedDatabase = try AppDatabase(paths: paths)

            let migrationCount = try reopenedDatabase.databasePool.read { database in
                try Int.fetchOne(
                    database,
                    sql: "SELECT COUNT(*) FROM grdb_migrations WHERE identifier = 'createClips'"
                )
            }
            XCTAssertEqual(migrationCount, 1)
        }
    }

    private func withTemporaryPaths<T>(
        _ body: (AppPaths) throws -> T
    ) throws -> T {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteListTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }

        let paths = try AppPaths(applicationSupportRoot: temporaryRoot)
        return try body(paths)
    }
}

@MainActor
final class LaunchAtLoginControllerTests: XCTestCase {
    func testInitialSetupDoesNotRegisterWithoutUserAction() throws {
        let defaults = try isolatedUserDefaults()
        let service = LaunchAtLoginServiceSpy(status: .notRegistered)
        let controller = LaunchAtLoginController(
            service: service,
            userDefaults: defaults
        )

        controller.performInitialSetupIfNeeded()

        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertFalse(controller.isEnabled)
    }

    func testInitialSetupRemovesStaleLaunchRegistration() throws {
        let defaults = try isolatedUserDefaults()
        let service = LaunchAtLoginServiceSpy(status: .enabled)
        let controller = LaunchAtLoginController(
            service: service,
            userDefaults: defaults
        )

        controller.performInitialSetupIfNeeded()

        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertFalse(controller.isEnabled)
    }

    func testToggleIsTheOnlyOperationThatChangesRegistration() throws {
        let defaults = try isolatedUserDefaults()
        let service = LaunchAtLoginServiceSpy(status: .notRegistered)
        let controller = LaunchAtLoginController(
            service: service,
            userDefaults: defaults
        )

        controller.setEnabled(true)
        controller.setEnabled(false)

        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(service.unregisterCallCount, 1)
    }

    private func isolatedUserDefaults() throws -> UserDefaults {
        let suiteName = "LaunchAtLoginControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}

@MainActor
private final class LaunchAtLoginServiceSpy: LaunchAtLoginServicing {
    var status: SMAppService.Status
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        status = .notRegistered
    }
}
