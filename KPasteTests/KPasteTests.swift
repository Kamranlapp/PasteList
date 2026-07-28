import Foundation
import Carbon
import GRDB
import XCTest
@testable import KPaste

final class KPasteTests: XCTestCase {
    func testApplicationConfiguration() {
        XCTAssertEqual(AppConfiguration.name, "KPaste")
        XCTAssertEqual(AppConfiguration.bundleIdentifier, "com.kam.kpaste")
    }

    func testDefaultGlobalHotKeyIsCommandShiftV() {
        let hotKey = HotKey.defaultValue

        XCTAssertEqual(hotKey.displayName, "⇧⌘V")
        XCTAssertNotEqual(hotKey.modifiers & UInt32(cmdKey), 0)
        XCTAssertNotEqual(hotKey.modifiers & UInt32(shiftKey), 0)
    }

    func testAppPathsCreateExpectedDirectories() throws {
        try withTemporaryPaths { paths in
            XCTAssertEqual(paths.applicationSupportDirectory.lastPathComponent, "com.kam.kpaste")
            XCTAssertEqual(paths.databaseURL.lastPathComponent, "clips.sqlite")
            XCTAssertEqual(paths.blobsDirectory.lastPathComponent, "blobs")

            var isDirectory: ObjCBool = false
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: paths.blobsDirectory.path,
                    isDirectory: &isDirectory
                )
            )
            XCTAssertTrue(isDirectory.boolValue)
        }
    }

    func testMigrationCreatesClipsSchemaAndIndexes() throws {
        try withTemporaryPaths { paths in
            let appDatabase = try AppDatabase(paths: paths)

            let schema = try appDatabase.databasePool.read { database in
                try String.fetchOne(
                    database,
                    sql: "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'clips'"
                )
            }
            XCTAssertNotNil(schema)
            XCTAssertTrue(schema?.contains("AUTOINCREMENT") == true)

            let columns = try appDatabase.databasePool.read { database in
                try Row.fetchAll(database, sql: "PRAGMA table_info(clips)")
            }
            XCTAssertEqual(
                columns.map { $0["name"] as String },
                ["id", "type", "content", "preview_text", "created_at", "pinned", "app_bundle_id"]
            )

            let indexNames = try appDatabase.databasePool.read { database in
                try String.fetchAll(
                    database,
                    sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'clips'"
                )
            }
            XCTAssertTrue(indexNames.contains("clips_created_at_desc"))
            XCTAssertTrue(indexNames.contains("clips_pinned_created_at_desc"))
        }
    }

    func testClipRecordRoundTripAndAutoIncrementedID() throws {
        try withTemporaryPaths { paths in
            let appDatabase = try AppDatabase(paths: paths)
            let createdAt = Date(timeIntervalSince1970: 1_700_000_000)

            let inserted = try appDatabase.databasePool.write { database in
                var clip = ClipRecord(
                    type: "text",
                    content: "Hello",
                    previewText: "Hello",
                    createdAt: createdAt,
                    appBundleID: "com.apple.TextEdit"
                )
                try clip.insert(database)
                return clip
            }

            XCTAssertNotNil(inserted.id)
            let fetched = try appDatabase.databasePool.read { database in
                try ClipRecord.fetchOne(database, key: inserted.id)
            }
            XCTAssertEqual(fetched, inserted)
        }
    }

    func testMigrationCanRunMoreThanOnce() throws {
        try withTemporaryPaths { paths in
            _ = try AppDatabase(paths: paths)
            let reopenedDatabase = try AppDatabase(paths: paths)

            let migrationCount = try reopenedDatabase.databasePool.read { database in
                try Int.fetchOne(
                    database,
                    sql: "SELECT COUNT(*) FROM grdb_migrations WHERE identifier = 'createClips'"
                )
            }
            XCTAssertEqual(migrationCount, 1)
        }
    }

    private func withTemporaryPaths<T>(
        _ body: (AppPaths) throws -> T
    ) throws -> T {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("KPasteTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }

        let paths = try AppPaths(applicationSupportRoot: temporaryRoot)
        return try body(paths)
    }
}
