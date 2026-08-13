import AppKit
import SwiftUI

@MainActor
final class AppServices: ObservableObject {
    @Published var globalHotKeyController: GlobalHotKeyController?
    @Published var pasteAutomationController: PasteAutomationController?
    @Published var launchAtLoginController: LaunchAtLoginController?
    @Published var onOpenOnboarding: (() -> Void)?
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let services = AppServices()
    private(set) var database: AppDatabase?
    private(set) var blobStorage: BlobStorage?
    private(set) var clipRepository: ClipRepository?
    private(set) var pasteboardMonitor: PasteboardMonitor?
    private(set) var statusItemController: StatusItemController?
    private(set) var pasteAutomationController: PasteAutomationController?
    private(set) var globalHotKeyController: GlobalHotKeyController?
    private(set) var launchAtLoginController: LaunchAtLoginController?
    private(set) var preferencesWindowController: PreferencesWindowController?
    private(set) var retentionScheduler: RetentionScheduler?
    private(set) var onboardingWindowController: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Hosted unit tests create isolated databases explicitly.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        do {
            let paths = try AppPaths()
            let database = try AppDatabase(paths: paths)
            let blobStorage = try BlobStorage(paths: paths)
            let repository = ClipRepository(database: database)
            let processor = PasteboardCaptureProcessor(
                repository: repository,
                blobStorage: blobStorage
            )
            let monitor = PasteboardMonitor(processor: processor)
            let pasteAutomationController = PasteAutomationController()
            let launchAtLoginController = LaunchAtLoginController()
            launchAtLoginController.performInitialSetupIfNeeded()
            let retentionScheduler = RetentionScheduler(
                service: RetentionService(
                    repository: repository,
                    blobStorage: blobStorage
                )
            )

            self.database = database
            self.blobStorage = blobStorage
            clipRepository = repository
            pasteboardMonitor = monitor
            self.pasteAutomationController = pasteAutomationController
            services.pasteAutomationController = pasteAutomationController
            self.launchAtLoginController = launchAtLoginController
            services.launchAtLoginController = launchAtLoginController
            self.retentionScheduler = retentionScheduler
            let preferencesWindowController = PreferencesWindowController(services: services)
            self.preferencesWindowController = preferencesWindowController
            let onboardingWindowController = OnboardingWindowController(
                state: OnboardingState(),
                pasteAutomationController: pasteAutomationController
            )
            self.onboardingWindowController = onboardingWindowController
            services.onOpenOnboarding = { [weak onboardingWindowController] in
                onboardingWindowController?.show()
            }
            let statusItemController = StatusItemController(
                repository: repository,
                blobStorage: blobStorage,
                pasteboardMonitor: monitor,
                pasteAutomationController: pasteAutomationController,
                onOpenSettings: { [weak preferencesWindowController] in
                    preferencesWindowController?.show()
                }
            )
            self.statusItemController = statusItemController
            globalHotKeyController = GlobalHotKeyController { [weak statusItemController] in
                statusItemController?.toggleCursorPanelAtPointer()
            }
            services.globalHotKeyController = globalHotKeyController
            retentionScheduler.start()
            monitor.start()
            onboardingWindowController.showIfNeeded()
        } catch {
            NSLog("PasteList failed to initialize its database: %@", String(describing: error))
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pasteboardMonitor?.stop()
        retentionScheduler?.stop()
    }
}

@main
struct PasteListApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            PreferencesContainerView(services: appDelegate.services)
        }
    }
}
