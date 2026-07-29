import AppKit
import Foundation
import XCTest
@testable import KPaste

@MainActor
final class HistoryViewModelTests: XCTestCase {
    func testFilterShowsTextsImagesFilesAndFoldersSeparately() async throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryViewModelTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let paths = try AppPaths(applicationSupportRoot: temporaryRoot)
        let repository = ClipRepository(database: try AppDatabase(paths: paths))
        let blobStorage = try BlobStorage(paths: paths)
        _ = try repository.insert(textClip("Text"))
        _ = try repository.insert(
            ClipRecord(
                type: ClipContentType.image.rawValue,
                content: "image.png",
                previewText: "Image",
                createdAt: Date()
            )
        )

        let sourceFile = temporaryRoot.appendingPathComponent("document.txt")
        try Data("file".utf8).write(to: sourceFile)
        _ = try repository.insert(
            ClipRecord(
                type: ClipContentType.file.rawValue,
                content: "",
                previewText: "document.txt",
                createdAt: Date()
            ),
            preparingContent: { id in
                try blobStorage.saveFiles(at: [sourceFile], for: id)
            },
            rollbackContent: { id in
                try? blobStorage.deleteAll(for: id)
            }
        )

        let sourceFolder = temporaryRoot.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceFolder,
            withIntermediateDirectories: true
        )
        _ = try repository.insert(
            ClipRecord(
                type: ClipContentType.file.rawValue,
                content: "",
                previewText: "Folder",
                createdAt: Date()
            ),
            preparingContent: { id in
                try blobStorage.saveFiles(at: [sourceFolder], for: id)
            },
            rollbackContent: { id in
                try? blobStorage.deleteAll(for: id)
            }
        )

        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        defer { pasteboard.clearContents() }
        let monitor = PasteboardMonitor(
            pasteboard: pasteboard,
            processor: PasteboardCaptureProcessor(
                repository: repository,
                blobStorage: blobStorage
            )
        )
        let defaultsSuite = "HistoryViewModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let viewModel = HistoryViewModel(
            repository: repository,
            blobStorage: blobStorage,
            restorer: ClipRestorer(
                repository: repository,
                blobStorage: blobStorage,
                monitor: monitor
            ),
            bulkPasteController: BulkPasteController(
                repository: repository,
                blobStorage: blobStorage,
                monitor: monitor
            ),
            userDefaults: defaults,
            onRestored: {}
        )

        try await waitUntil { viewModel.history.count == 4 }

        viewModel.filter = .texts
        XCTAssertEqual(viewModel.history.map(\.previewText), ["Text"])

        viewModel.filter = .images
        XCTAssertEqual(viewModel.history.map(\.previewText), ["Image"])

        viewModel.filter = .files
        XCTAssertEqual(viewModel.history.map(\.previewText), ["document.txt"])

        viewModel.filter = .folders
        XCTAssertEqual(viewModel.history.map(\.previewText), ["Folder"])

        viewModel.filter = .all
        XCTAssertEqual(viewModel.history.count, 4)
    }

    func testClearHistoryDeletesPinnedUnpinnedAndStoredContent() async throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryViewModelTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let paths = try AppPaths(applicationSupportRoot: temporaryRoot)
        let repository = ClipRepository(database: try AppDatabase(paths: paths))
        let blobStorage = try BlobStorage(paths: paths)
        let history = try repository.insert(textClip("History"))
        let pinned = try repository.insert(
            ClipRecord(
                type: ClipContentType.image.rawValue,
                content: "pending",
                previewText: "Pinned image",
                createdAt: Date(),
                pinned: true
            )
        )
        let pinnedID = try XCTUnwrap(pinned.id)
        _ = try blobStorage.savePNGData(Data("stored image".utf8), for: pinnedID)

        let actions = ClipHistoryActions(
            repository: repository,
            blobStorage: blobStorage
        )
        try await actions.clearHistory()

        XCTAssertNil(try repository.fetch(id: try XCTUnwrap(history.id)))
        XCTAssertNil(try repository.fetch(id: pinnedID))
        XCTAssertThrowsError(try blobStorage.readImageData(for: pinnedID))
    }

    func testSearchReconcilesSelectionWithVisibleSnapshot() async throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryViewModelTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let paths = try AppPaths(applicationSupportRoot: temporaryRoot)
        let repository = ClipRepository(database: try AppDatabase(paths: paths))
        let blobStorage = try BlobStorage(paths: paths)
        let visible = try repository.insert(textClip("Visible clip"))
        let hidden = try repository.insert(textClip("Other clip"))
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        defer { pasteboard.clearContents() }
        let monitor = PasteboardMonitor(
            pasteboard: pasteboard,
            processor: PasteboardCaptureProcessor(
                repository: repository,
                blobStorage: blobStorage
            )
        )
        let defaultsSuite = "HistoryViewModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let viewModel = HistoryViewModel(
            repository: repository,
            blobStorage: blobStorage,
            restorer: ClipRestorer(
                repository: repository,
                blobStorage: blobStorage,
                monitor: monitor
            ),
            bulkPasteController: BulkPasteController(
                repository: repository,
                blobStorage: blobStorage,
                monitor: monitor
            ),
            userDefaults: defaults,
            onRestored: {}
        )

        try await waitUntil { viewModel.history.count == 2 }
        viewModel.toggleSelection(visible)
        viewModel.toggleSelection(hidden)
        XCTAssertEqual(viewModel.selectedCount, 2)

        viewModel.searchText = "Visible"

        try await waitUntil { viewModel.history.map(\.id) == [visible.id] }
        XCTAssertEqual(viewModel.selectedClipIDs, [visible.id].compactMap { $0 })
    }

    private func textClip(_ text: String) -> ClipRecord {
        ClipRecord(
            type: ClipContentType.text.rawValue,
            content: text,
            previewText: text,
            createdAt: Date()
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<100 {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for view-model state")
    }
}
