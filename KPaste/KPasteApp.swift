import AppKit
import SwiftUI

@MainActor
final class AppServices: ObservableObject {
    @Published var globalHotKeyController: GlobalHotKeyController?
    @Published var accessibilityController: AccessibilityController?
    @Published var launchAtLoginController: LaunchAtLoginController?
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let services = AppServices()
    private(set) var database: AppDatabase?
    private(set) var blobStorage: BlobStorage?
    private(set) var clipRepository: ClipRepository?
    private(set) var pasteboardMonitor: PasteboardMonitor?
    private(set) var statusItemController: StatusItemController?
    private(set) var accessibilityController: AccessibilityController?
    private(set) var globalHotKeyController: GlobalHotKeyController?
    private(set) var launchAtLoginController: LaunchAtLoginController?
    private(set) var preferencesWindowController: PreferencesWindowController?
    private(set) var retentionScheduler: RetentionScheduler?

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
            let accessibilityController = AccessibilityController()
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
            self.accessibilityController = accessibilityController
            services.accessibilityController = accessibilityController
            self.launchAtLoginController = launchAtLoginController
            services.launchAtLoginController = launchAtLoginController
            self.retentionScheduler = retentionScheduler
            let preferencesWindowController = PreferencesWindowController(services: services)
            self.preferencesWindowController = preferencesWindowController
            let statusItemController = StatusItemController(
                repository: repository,
                blobStorage: blobStorage,
                pasteboardMonitor: monitor,
                accessibilityController: accessibilityController,
                onOpenSettings: { [weak preferencesWindowController] in
                    preferencesWindowController?.show()
                }
            )
            self.statusItemController = statusItemController
            globalHotKeyController = GlobalHotKeyController { [weak statusItemController] in
                statusItemController?.showPopover()
            }
            services.globalHotKeyController = globalHotKeyController
            retentionScheduler.start()
            monitor.start()
        } catch {
            NSLog("KPaste failed to initialize its database: %@", String(describing: error))
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pasteboardMonitor?.stop()
        retentionScheduler?.stop()
    }
}

@main
struct KPasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            PreferencesContainerView(services: appDelegate.services)
        }
    }
}
