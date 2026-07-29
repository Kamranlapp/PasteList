import Foundation
import Carbon
import GRDB
import ServiceManagement
import XCTest
@testable import KPaste

final class KPasteTests: XCTestCase {
    func testApplicationConfiguration() {
        XCTAssertEqual(AppConfiguration.name, "KPaste")
        XCTAssertEqual(AppConfiguration.bundleIdentifier, "com.kam.kpaste")
    }

    func testClipPrimaryInteractionsKeepSelectionAndDraggingExclusive() {
        let makeClip: (ClipContentType) -> ClipRecord = { type in
            ClipRecord(
                id: 1,
                type: type.rawValue,
                content: "content",
                previewText: "preview",
                createdAt: Date()
            )
        }

        XCTAssertEqual(makeClip(.text).primaryInteraction, .textSelection)
        XCTAssertEqual(makeClip(.rtf).primaryInteraction, .textSelection)
        XCTAssertEqual(makeClip(.url).primaryInteraction, .textSelection)
        XCTAssertEqual(makeClip(.image).primaryInteraction, .fileDrag)
        XCTAssertEqual(makeClip(.file).primaryInteraction, .fileDrag)
    }

    func testDefaultGlobalHotKeyIsCommandShiftV() {
        let hotKey = HotKey.defaultValue

        XCTAssertEqual(hotKey.displayName, "⇧⌘V")
        XCTAssertNotEqual(hotKey.modifiers & UInt32(cmdKey), 0)
        XCTAssertNotEqual(hotKey.modifiers & UInt32(shiftKey), 0)
    }

    @MainActor
    func testCursorPanelPlacesPointerOverFirstRowAwayFromScreenEdges() {
        let pointer = NSPoint(x: 800, y: 600)
        let expectedHorizontalPosition = StatusItemController.cursorScrollBarWidth
            + StatusItemController.cursorScrollBarSpacing
            + StatusItemController.cursorPanelPadding
            + StatusItemController.popoverSize.width
                * StatusItemController.cursorHorizontalAnchor
        let expectedVerticalPosition = StatusItemController.cursorWindowControlAreaHeight
            + StatusItemController.cursorWindowControlSpacing
            + StatusItemController.cursorPanelPadding
            + StatusItemController.cursorFirstRowCenterFromTop
        let frame = StatusItemController.cursorPanelFrame(
            pointerLocation: pointer,
            visibleFrame: NSRect(x: 0, y: 0, width: 1_440, height: 900)
        )

        XCTAssertEqual(
            pointer.x - frame.minX,
            expectedHorizontalPosition
        )
        XCTAssertEqual(
            frame.maxY - pointer.y,
            expectedVerticalPosition
        )
    }

    @MainActor
    func testCursorPanelStaysInsideVisibleScreenNearEdges() {
        let visibleFrame = NSRect(x: 0, y: 25, width: 1_000, height: 700)
        let frame = StatusItemController.cursorPanelFrame(
            pointerLocation: NSPoint(x: 995, y: 30),
            visibleFrame: visibleFrame
        )

        XCTAssertGreaterThanOrEqual(frame.minX, visibleFrame.minX)
        XCTAssertGreaterThanOrEqual(frame.minY, visibleFrame.minY)
        XCTAssertLessThanOrEqual(frame.maxX, visibleFrame.maxX)
        XCTAssertLessThanOrEqual(frame.maxY, visibleFrame.maxY)
    }

    @MainActor
    func testCursorPanelSizeIsSavedAndRestored() throws {
        let suiteName = "KPasteTests.cursorPanelSize.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let savedSize = NSSize(width: 460, height: 520)
        StatusItemController.saveCursorPanelSize(savedSize, in: defaults)

        XCTAssertEqual(
            StatusItemController.storedCursorPanelSize(in: defaults),
            savedSize
        )
    }

    func testCursorPanelResizeKeepsOppositeCornerFixed() {
        let initialFrame = NSRect(x: 100, y: 100, width: 500, height: 400)

        let resizedFrame = CursorPanelResizer.frame(
            from: initialFrame,
            dragging: [.top, .left],
            by: NSPoint(x: 50, y: -100),
            minimumSize: NSSize(width: 300, height: 250),
            within: nil
        )

        XCTAssertEqual(
            resizedFrame,
            NSRect(x: 150, y: 100, width: 450, height: 300)
        )
        XCTAssertEqual(resizedFrame.maxX, initialFrame.maxX)
        XCTAssertEqual(resizedFrame.minY, initialFrame.minY)
    }

    func testCursorPanelResizeHonorsMinimumSize() {
        let initialFrame = NSRect(x: 100, y: 100, width: 500, height: 400)

        let resizedFrame = CursorPanelResizer.frame(
            from: initialFrame,
            dragging: [.bottom, .right],
            by: NSPoint(x: -300, y: 250),
            minimumSize: NSSize(width: 300, height: 250),
            within: nil
        )

        XCTAssertEqual(
            resizedFrame,
            NSRect(x: 100, y: 250, width: 300, height: 250)
        )
        XCTAssertEqual(resizedFrame.maxX, 400)
        XCTAssertEqual(resizedFrame.maxY, initialFrame.maxY)
    }

    func testClipTimestampUsesTodayYesterdayAndWeekdayFormats() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 29,
                hour: 18
            ))
        )
        let today = try XCTUnwrap(
            calendar.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 29,
                hour: 15,
                minute: 4
            ))
        )
        let yesterday = try XCTUnwrap(
            calendar.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 28,
                hour: 9,
                minute: 15
            ))
        )
        let monday = try XCTUnwrap(
            calendar.date(from: DateComponents(
                year: 2026,
                month: 7,
                day: 27,
                hour: 20,
                minute: 30
            ))
        )

        XCTAssertEqual(
            ClipTimestampFormatter.string(for: today, relativeTo: now, calendar: calendar),
            "Today 15:04"
        )
        XCTAssertEqual(
            ClipTimestampFormatter.string(for: yesterday, relativeTo: now, calendar: calendar),
            "Yesterday 09:15"
        )
        XCTAssertEqual(
            ClipTimestampFormatter.string(for: monday, relativeTo: now, calendar: calendar),
            "Monday 20:30"
        )
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

@MainActor
final class LaunchAtLoginControllerTests: XCTestCase {
    func testInitialSetupDoesNotRegisterWithoutUserAction() throws {
        let defaults = try isolatedUserDefaults()
        let service = LaunchAtLoginServiceSpy(status: .notRegistered)
        let controller = LaunchAtLoginController(
            service: service,
            userDefaults: defaults
        )

        controller.performInitialSetupIfNeeded()

        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertFalse(controller.isEnabled)
    }

    func testToggleIsTheOnlyOperationThatChangesRegistration() throws {
        let defaults = try isolatedUserDefaults()
        let service = LaunchAtLoginServiceSpy(status: .notRegistered)
        let controller = LaunchAtLoginController(
            service: service,
            userDefaults: defaults
        )

        controller.setEnabled(true)
        controller.setEnabled(false)

        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(service.unregisterCallCount, 1)
    }

    private func isolatedUserDefaults() throws -> UserDefaults {
        let suiteName = "LaunchAtLoginControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}

@MainActor
private final class LaunchAtLoginServiceSpy: LaunchAtLoginServicing {
    var status: SMAppService.Status
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        status = .notRegistered
    }
}
