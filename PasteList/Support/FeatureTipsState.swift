import Combine
import Foundation

enum FeatureTip: String, CaseIterable {
    case cursorPanelControls
    case rowGestures
}

@MainActor
final class FeatureTipsState: ObservableObject {
    private enum DefaultsKey {
        static func seen(_ tip: FeatureTip) -> String {
            "tips.seen.\(tip.rawValue)"
        }
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func hasSeen(_ tip: FeatureTip) -> Bool {
        userDefaults.bool(forKey: DefaultsKey.seen(tip))
    }

    func markSeen(_ tip: FeatureTip) {
        userDefaults.set(true, forKey: DefaultsKey.seen(tip))
        objectWillChange.send()
    }
}
