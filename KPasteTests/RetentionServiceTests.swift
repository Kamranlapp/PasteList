import Foundation
import XCTest
@testable import KPaste

final class RetentionServiceTests: XCTestCase {
    func testCandidateSelectionCombinesAgeAndCountAndExcludesPinned() throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let cutoff = Date(timeIntervalSince1970: 1_000)

        let oldest = try harness.insertText("oldest", at: Date(timeIntervalSince1970: 100))
        let thirdNewest = try harness.insertText("third", at: Date(timeIntervalSince1970: 1_100))
        _ = try harness.insertText("second", at: Date(timeIntervalSince1970: 1_200))
        _ = try harness.insertText("newest", at: Date(timeIntervalSince1970: 1_300))
        _ = try harness.repository.insert(
            ClipRecord(
                type: ClipContentType.text.rawValue,
                content: "pinned",
                previewText: "pinned",
                createdAt: Date(timeIntervalSince1970: 50),
                pinned: true
            )
        )

        let candidates = try harness.repository.fetchRetentionCandidates(
            olderThan: cutoff,
            maximumUnpinnedCount: 2
        )

        XCTAssertEqual(Set(candidates.compactMap(\.id)), Set([oldest.id, thirdNewest.id].compactMap { $0 }))
        XCTAssertTrue(candidates.allSatisfy { !$0.pinned })
    }

    func testCleanupDeletesExpiredClipAndItsBlobButKeepsPinnedAndRecentClips() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let expiredDate = now.addingTimeInterval(-RetentionPolicy.maximumAge - 1)

        let expired = try harness.insertRTF("expired", at: expiredDate)
        let pinned = try harness.insertRTF("pinned", at: expiredDate, pinned: true)
        let recent = try harness.insertText("recent", at: now.addingTimeInterval(-60))
        let service = RetentionService(
            repository: harness.repository,
            blobStorage: harness.blobStorage,
            now: { now }
        )

        let deletedCount = try await service.performCleanup()
        XCTAssertEqual(deletedCount, 1)

        XCTAssertNil(try harness.repository.fetch(id: try XCTUnwrap(expired.id)))
        XCTAssertNotNil(try harness.repository.fetch(id: try XCTUnwrap(pinned.id)))
        XCTAssertNotNil(try harness.repository.fetch(id: try XCTUnwrap(recent.id)))
        XCTAssertThrowsError(try harness.blobStorage.readData(atRelativePath: expired.content))
        XCTAssertNoThrow(try harness.blobStorage.readData(atRelativePath: pinned.content))
    }

    func testCleanupRemovesOnlyStaleManagedOrphans() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let staleDate = now.addingTimeInterval(-RetentionPolicy.orphanGracePeriod - 1)
        let staleOrphan = harness.paths.blobsDirectory.appendingPathComponent("999.rtf")
        let staleStaging = harness.paths.blobsDirectory.appendingPathComponent(".staging-88-test")
        let unknownFile = harness.paths.blobsDirectory.appendingPathComponent("keep.me")
        let freshOrphan = harness.paths.blobsDirectory.appendingPathComponent("998.png")

        for url in [staleOrphan, staleStaging, unknownFile, freshOrphan] {
            try Data("test".utf8).write(to: url)
        }
        for url in [staleOrphan, staleStaging, unknownFile] {
            try FileManager.default.setAttributes(
                [.modificationDate: staleDate],
                ofItemAtPath: url.path
            )
        }
        try FileManager.default.setAttributes(
            [.modificationDate: now],
            ofItemAtPath: freshOrphan.path
        )

        let service = RetentionService(
            repository: harness.repository,
            blobStorage: harness.blobStorage,
            now: { now }
        )
        let deletedCount = try await service.performCleanup()
        XCTAssertEqual(deletedCount, 0)

        XCTAssertFalse(FileManager.default.fileExists(atPath: staleOrphan.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleStaging.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unknownFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: freshOrphan.path))
    }

    private func makeHarness() throws -> RetentionTestHarness {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RetentionServiceTests-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppPaths(applicationSupportRoot: root)
        let database = try AppDatabase(paths: paths)
        let repository = ClipRepository(database: database)
        let blobStorage = try BlobStorage(paths: paths)
        return RetentionTestHarness(
            root: root,
            paths: paths,
            database: database,
            repository: repository,
            blobStorage: blobStorage
        )
    }
}

private struct RetentionTestHarness {
    let root: URL
    let paths: AppPaths
    let database: AppDatabase
    let repository: ClipRepository
    let blobStorage: BlobStorage

    func insertText(_ value: String, at date: Date) throws -> ClipRecord {
        try repository.insert(
            ClipRecord(
                type: ClipContentType.text.rawValue,
                content: value,
                previewText: value,
                createdAt: date
            )
        )
    }

    func insertRTF(_ value: String, at date: Date, pinned: Bool = false) throws -> ClipRecord {
        let data = Data("{\\rtf1\\ansi \(value)}".utf8)
        let storage = blobStorage
        return try repository.insert(
            ClipRecord(
                type: ClipContentType.rtf.rawValue,
                content: "",
                previewText: value,
                createdAt: date,
                pinned: pinned
            ),
            preparingContent: { id in try storage.saveRTF(data, for: id) },
            rollbackContent: { id in try? storage.deleteAll(for: id) }
        )
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }
}
