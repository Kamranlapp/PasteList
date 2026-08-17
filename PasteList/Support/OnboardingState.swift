import Combine
import Foundation

@MainActor
final class OnboardingState: ObservableObject {
    private enum DefaultsKey {
        static let completed = "onboarding.completed"
    }

    @Published private(set) var hasCompleted: Bool

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        hasCompleted = userDefaults.bool(forKey: DefaultsKey.completed)
    }

    var shouldPresentOnLaunch: Bool {
        !hasCompleted
    }

    func complete() {
        userDefaults.set(true, forKey: DefaultsKey.completed)
        hasCompleted = true
    }

    #if DEBUG
    func reset() {
        userDefaults.removeObject(forKey: DefaultsKey.completed)
        hasCompleted = false
    }
    #endif
}
