import Foundation
import GRDB
import XCTest
@testable import KPaste

final class ClipRepositoryTests: XCTestCase {
    func testInsertFetchAndDelete() throws {
        try withRepository { repository, _ in
            let inserted = try repository.insert(makeClip("First", at: 100))

            let id = try XCTUnwrap(inserted.id)
            XCTAssertEqual(try repository.fetch(id: id), inserted)
            XCTAssertTrue(try repository.delete(id: id))
            XCTAssertNil(try repository.fetch(id: id))
            XCTAssertFalse(try repository.delete(id: id))
        }
    }

    func testDeleteAllReturnsDeletedIDsAndClearsPinnedAndHistory() throws {
        try withRepository { repository, _ in
            let history = try repository.insert(makeClip("History", at: 100))
            let pinned = try repository.insert(makeClip("Pinned", at: 200, pinned: true))

            XCTAssertEqual(Set(try repository.deleteAll()), Set([history.id, pinned.id].compactMap { $0 }))
            XCTAssertEqual(try repository.fetchAll(), [])
            XCTAssertEqual(try repository.deleteAll(), [])
        }
    }

    func testUnpinBumpsClipToTopOfHistory() throws {
        try withRepository { repository, _ in
            let recentHistory = try repository.insert(makeClip("Recent", at: 1_000))
            let oldPinned = try repository.insert(
                makeClip("Old pinned", at: 100, pinned: true)
            )
            let oldPinnedID = try XCTUnwrap(oldPinned.id)
            let bumpDate = Date(timeIntervalSince1970: 2_000)

            XCTAssertTrue(
                try repository.setPinned(
                    false,
                    for: oldPinnedID,
                    bumpingToTop: true,
                    at: bumpDate
                )
            )

            XCTAssertEqual(try repository.fetchPinned(), [])
            XCTAssertEqual(
                try repository.fetchHistory().map(\.id),
                [oldPinned.id, recentHistory.id]
            )
            XCTAssertEqual(
                try XCTUnwrap(repository.fetch(id: oldPinnedID)).createdAt,
                bumpDate
            )
        }
    }

    func testPinningDoesNotChangeCreatedAt() throws {
        try withRepository { repository, _ in
            let clip = try repository.insert(makeClip("Clip", at: 100))
            let id = try XCTUnwrap(clip.id)

            XCTAssertTrue(try repository.setPinned(true, for: id))

            XCTAssertEqual(
                try XCTUnwrap(repository.fetch(id: id)).createdAt,
                clip.createdAt
            )
        }
    }

    func testPinnedAndHistoryListsAreSortedNewestFirst() throws {
        try withRepository { repository, _ in
            let oldHistory = try repository.insert(makeClip("Old history", at: 100))
            let newestPinned = try repository.insert(makeClip("Newest pinned", at: 400, pinned: true))
            let newHistory = try repository.insert(makeClip("New history", at: 300))
            let oldPinned = try repository.insert(makeClip("Old pinned", at: 200, pinned: true))

            XCTAssertEqual(
                try repository.fetchPinned().map(\.id),
                [newestPinned.id, oldPinned.id]
            )
            XCTAssertEqual(
                try repository.fetchHistory().map(\.id),
                [newHistory.id, oldHistory.id]
            )

            let oldHistoryID = try XCTUnwrap(oldHistory.id)
            XCTAssertTrue(try repository.setPinned(true, for: oldHistoryID))
            XCTAssertEqual(
                try repository.fetchPinned().map(\.id),
                [newestPinned.id, oldPinned.id, oldHistory.id]
            )

            let newestPinnedID = try XCTUnwrap(newestPinned.id)
            XCTAssertTrue(try repository.setPinned(false, for: newestPinnedID))
            XCTAssertEqual(
                try repository.fetchPinned().map(\.id),
                [oldPinned.id, oldHistory.id]
            )
            XCTAssertEqual(
                try repository.fetchHistory().map(\.id),
                [newestPinned.id, newHistory.id]
            )
            XCTAssertFalse(try repository.setPinned(false, for: Int64.max))
        }
    }

    func testSearchIsCaseInsensitiveLiteralContains() throws {
        try withRepository { repository, _ in
            let literal = try repository.insert(makeClip("Budget 100%_DONE", at: 300))
            let wildcardLookalike = try repository.insert(makeClip("Budget 100xxDONE", at: 200))
            let cyrillic = try repository.insert(makeClip("ПРИВЕТ, Мир", at: 100))
            _ = try repository.insert(makeClip("Unrelated", at: 400))

            XCTAssertEqual(
                try repository.search(previewText: "100%_").map(\.id),
                [literal.id]
            )
            XCTAssertEqual(
                try repository.search(previewText: "budget").map(\.id),
                [literal.id, wildcardLookalike.id]
            )
            XCTAssertEqual(
                try repository.search(previewText: "привет").map(\.id),
                [cyrillic.id]
            )
        }
    }

    func testSearchAppliesToPinnedAndHistorySections() throws {
        try withRepository { repository, _ in
            let pinnedMatch = try repository.insert(makeClip("Shared value", at: 100, pinned: true))
            let historyMatch = try repository.insert(makeClip("Another shared value", at: 200))
            _ = try repository.insert(makeClip("Different", at: 300, pinned: true))

            XCTAssertEqual(
                try repository.fetchPinned(matching: "shared").map(\.id),
                [pinnedMatch.id]
            )
            XCTAssertEqual(
                try repository.fetchHistory(matching: "SHARED").map(\.id),
                [historyMatch.id]
            )
        }
    }

    func testMarkUsedMakesClipLatest() throws {
        try withRepository { repository, _ in
            let old = try repository.insert(makeClip("Old", at: 100))
            let current = try repository.insert(makeClip("Current", at: 200))

            XCTAssertEqual(try repository.fetchLatest()?.id, current.id)

            let oldID = try XCTUnwrap(old.id)
            let usedAt = Date(timeIntervalSince1970: 300)
            XCTAssertTrue(try repository.markUsed(id: oldID, at: usedAt))
            XCTAssertEqual(try repository.fetchLatest()?.id, old.id)
            XCTAssertEqual(try repository.fetch(id: oldID)?.createdAt, usedAt)
            XCTAssertFalse(try repository.markUsed(id: Int64.max, at: usedAt))
        }
    }

    @MainActor
    func testObservationPublishesSectionedHistoryChanges() async throws {
        try await withRepository { repository, database in
            var snapshots: [ClipHistorySnapshot] = []
            let changed = expectation(description: "Observation publishes insert")
            changed.expectedFulfillmentCount = 2

            let cancellable = repository.historyObservation().start(
                in: database.databasePool,
                scheduling: .immediate,
                onError: { error in
                    XCTFail("Unexpected observation error: \(error)")
                },
                onChange: { snapshot in
                    snapshots.append(snapshot)
                    changed.fulfill()
                }
            )

            XCTAssertEqual(snapshots, [ClipHistorySnapshot(pinned: [], history: [])])
            let inserted = try repository.insert(makeClip("Observed", at: 100, pinned: true))

            await fulfillment(of: [changed], timeout: 2)
            withExtendedLifetime(cancellable) {}
            XCTAssertEqual(snapshots.last?.pinned.map(\.id), [inserted.id])
            XCTAssertEqual(snapshots.last?.history, [])
        }
    }

    private func makeClip(
        _ preview: String,
        at timestamp: TimeInterval,
        pinned: Bool = false
    ) -> ClipRecord {
        ClipRecord(
            type: "text",
            content: preview,
            previewText: preview,
            createdAt: Date(timeIntervalSince1970: timestamp),
            pinned: pinned
        )
    }

    private func withRepository<T>(
        _ body: (ClipRepository, AppDatabase) throws -> T
    ) throws -> T {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }

        let paths = try AppPaths(applicationSupportRoot: temporaryRoot)
        let database = try AppDatabase(paths: paths)
        return try body(ClipRepository(database: database), database)
    }

    @MainActor
    private func withRepository<T>(
        _ body: (ClipRepository, AppDatabase) async throws -> T
    ) async throws -> T {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }

        let paths = try AppPaths(applicationSupportRoot: temporaryRoot)
        let database = try AppDatabase(paths: paths)
        return try await body(ClipRepository(database: database), database)
    }
}
