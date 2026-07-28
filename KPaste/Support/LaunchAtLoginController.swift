import Combine
import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var statusText = "Not configured"
    @Published private(set) var errorMessage: String?

    private enum DefaultsKey {
        static let completedInitialSetup = "launchAtLogin.completedInitialSetup"
    }

    private let service: SMAppService
    private let userDefaults: UserDefaults

    init(
        service: SMAppService = .mainApp,
        userDefaults: UserDefaults = .standard
    ) {
        self.service = service
        self.userDefaults = userDefaults
        refresh()
    }

    func performInitialSetupIfNeeded() {
        guard !userDefaults.bool(forKey: DefaultsKey.completedInitialSetup) else {
            refresh()
            return
        }

        defer {
            userDefaults.set(true, forKey: DefaultsKey.completedInitialSetup)
            refresh()
        }

        guard service.status != .enabled, service.status != .requiresApproval else {
            return
        }

        do {
            try service.register()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    func refresh() {
        switch service.status {
        case .enabled:
            isEnabled = true
            statusText = "Enabled"
        case .requiresApproval:
            isEnabled = true
            statusText = "Requires approval in System Settings"
        case .notRegistered:
            isEnabled = false
            statusText = "Disabled"
        case .notFound:
            isEnabled = false
            statusText = "Unavailable from the current app location"
        @unknown default:
            isEnabled = false
            statusText = "Unknown status"
        }
    }
}
