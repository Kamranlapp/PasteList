import Combine
import Foundation
import ServiceManagement

@MainActor
protocol LaunchAtLoginServicing: AnyObject {
    var status: SMAppService.Status { get }

    func register() throws
    func unregister() throws
}

extension SMAppService: LaunchAtLoginServicing {}

@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var statusText = "Not configured"
    @Published private(set) var errorMessage: String?

    private enum DefaultsKey {
        static let completedInitialSetup = "launchAtLogin.completedInitialSetup"
    }

    private let service: any LaunchAtLoginServicing
    private let userDefaults: UserDefaults

    init(
        service: any LaunchAtLoginServicing = SMAppService.mainApp,
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

        do {
            if service.status != .notRegistered {
                try service.unregister()
            }
            userDefaults.set(true, forKey: DefaultsKey.completedInitialSetup)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
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
