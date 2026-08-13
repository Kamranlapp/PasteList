import AppKit
import Foundation
import StoreKit

@MainActor
struct AppReviewRequestClient {
    let requestReview: (NSViewController) -> Void

    static let live = AppReviewRequestClient { viewController in
        AppStore.requestReview(in: viewController)
    }
}

@MainActor
final class AppReviewRequestController {
    static let pasteThreshold = 25

    private enum DefaultsKey {
        static let successfulPasteCount = "appReview.successfulPasteCount.v1"
        static let hasRequested = "appReview.hasRequested.v1"
    }

    private let userDefaults: UserDefaults
    private let client: AppReviewRequestClient
    private let waitBeforeRequesting: () async -> Void
    private var isRequestPending = false

    init(
        userDefaults: UserDefaults = .standard,
        client: AppReviewRequestClient = .live,
        waitBeforeRequesting: @escaping () async -> Void = {
            try? await Task.sleep(for: .seconds(3))
        }
    ) {
        self.userDefaults = userDefaults
        self.client = client
        self.waitBeforeRequesting = waitBeforeRequesting
    }

    var successfulPasteCount: Int {
        min(
            max(userDefaults.integer(forKey: DefaultsKey.successfulPasteCount), 0),
            Self.pasteThreshold
        )
    }

    var hasRequested: Bool {
        userDefaults.bool(forKey: DefaultsKey.hasRequested)
    }

    /// Records one completed PasteList paste action. Returns `true` only for
    /// the action that should schedule the single StoreKit request.
    func recordSuccessfulPaste() -> Bool {
        guard !hasRequested else {
            return false
        }

        let updatedCount = min(successfulPasteCount + 1, Self.pasteThreshold)
        userDefaults.set(updatedCount, forKey: DefaultsKey.successfulPasteCount)

        guard updatedCount == Self.pasteThreshold, !isRequestPending else {
            return false
        }
        isRequestPending = true
        return true
    }

    func performPendingRequest(in viewController: NSViewController) async {
        guard isRequestPending, !hasRequested else {
            return
        }

        await waitBeforeRequesting()
        guard !Task.isCancelled else {
            isRequestPending = false
            return
        }
        guard isRequestPending, !hasRequested else {
            return
        }

        // Store this immediately before calling StoreKit. StoreKit doesn't
        // report whether it actually displayed the prompt or received a rating.
        userDefaults.set(true, forKey: DefaultsKey.hasRequested)
        isRequestPending = false
        client.requestReview(viewController)
    }
}
