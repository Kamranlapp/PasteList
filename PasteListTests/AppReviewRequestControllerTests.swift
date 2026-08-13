import AppKit
import XCTest
@testable import PasteList

@MainActor
final class AppReviewRequestControllerTests: XCTestCase {
    func testRequestsReviewExactlyOnTwentyFifthSuccessfulPaste() async throws {
        let defaults = try isolatedUserDefaults()
        var requestCount = 0
        let controller = makeController(defaults: defaults) {
            requestCount += 1
        }

        for _ in 0..<24 {
            XCTAssertFalse(controller.recordSuccessfulPaste())
        }
        XCTAssertEqual(controller.successfulPasteCount, 24)
        XCTAssertFalse(controller.hasRequested)

        XCTAssertTrue(controller.recordSuccessfulPaste())
        await controller.performPendingRequest(in: NSViewController())

        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(controller.successfulPasteCount, 25)
        XCTAssertTrue(controller.hasRequested)

        XCTAssertFalse(controller.recordSuccessfulPaste())
        await controller.performPendingRequest(in: NSViewController())
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(controller.successfulPasteCount, 25)
    }

    func testPersistedCountContinuesAfterControllerIsRecreated() async throws {
        let defaults = try isolatedUserDefaults()
        let firstController = makeController(defaults: defaults) {}
        for _ in 0..<24 {
            _ = firstController.recordSuccessfulPaste()
        }

        var requestCount = 0
        let recreatedController = makeController(defaults: defaults) {
            requestCount += 1
        }
        XCTAssertEqual(recreatedController.successfulPasteCount, 24)

        XCTAssertTrue(recreatedController.recordSuccessfulPaste())
        await recreatedController.performPendingRequest(in: NSViewController())

        XCTAssertEqual(requestCount, 1)
        XCTAssertTrue(recreatedController.hasRequested)
    }

    func testPersistedRequestedFlagSuppressesCountingAndRequests() async throws {
        let defaults = try isolatedUserDefaults()
        var requestCount = 0
        let firstController = makeController(defaults: defaults) {
            requestCount += 1
        }
        for _ in 0..<AppReviewRequestController.pasteThreshold {
            _ = firstController.recordSuccessfulPaste()
        }
        await firstController.performPendingRequest(in: NSViewController())

        let recreatedController = makeController(defaults: defaults) {
            requestCount += 1
        }
        XCTAssertFalse(recreatedController.recordSuccessfulPaste())
        await recreatedController.performPendingRequest(in: NSViewController())

        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(recreatedController.successfulPasteCount, 25)
    }

    func testAdditionalPasteWhileRequestIsPendingDoesNotScheduleDuplicate() async throws {
        let defaults = try isolatedUserDefaults()
        var requestCount = 0
        let controller = makeController(defaults: defaults) {
            requestCount += 1
        }
        for _ in 0..<24 {
            _ = controller.recordSuccessfulPaste()
        }

        XCTAssertTrue(controller.recordSuccessfulPaste())
        XCTAssertFalse(controller.recordSuccessfulPaste())
        await controller.performPendingRequest(in: NSViewController())

        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(controller.successfulPasteCount, 25)
    }

    private func makeController(
        defaults: UserDefaults,
        requestReview: @escaping () -> Void
    ) -> AppReviewRequestController {
        AppReviewRequestController(
            userDefaults: defaults,
            client: AppReviewRequestClient { _ in requestReview() },
            waitBeforeRequesting: {}
        )
    }

    private func isolatedUserDefaults() throws -> UserDefaults {
        let suiteName = "AppReviewRequestControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
