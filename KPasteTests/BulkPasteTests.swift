import AppKit
import Foundation
import XCTest
@testable import KPaste

@MainActor
final class BulkPasteTests: XCTestCase {
    func testBulkPasteWritesOneCombinedStringSuppressesCaptureAndPreservesSelectionOrder() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        defer { pasteboard.clearContents() }
        let monitor = harness.makeMonitor(pasteboard: pasteboard)
        monitor.start()
        defer { monitor.stop() }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let controller = BulkPasteController(
            repository: harness.repository,
            blobStorage: harness.blobStorage,
            monitor: monitor,
            now: { now }
        )
        let text = try harness.insertText("First")
        let rtf = try harness.insertRTF("Second")
        let url = try harness.insertURL("https://example.com")
        let changeCountBeforePaste = pasteboard.changeCount

        try await controller.paste([text, rtf, url], separator: " | ")

        XCTAssertEqual(pasteboard.changeCount, changeCountBeforePaste + 1)
        XCTAssertEqual(
            pasteboard.string(forType: .string),
            "First | Second | https://example.com"
        )
        XCTAssertFalse(monitor.checkForChanges())
        await monitor.waitForPendingProcessing()
        XCTAssertEqual(try harness.repository.fetchAll().count, 3)
        XCTAssertEqual(
            try harness.repository.fetchHistory().compactMap(\.id),
            [text.id, rtf.id, url.id].compactMap { $0 }
        )
        let updatedText = try XCTUnwrap(
            harness.repository.fetch(id: try XCTUnwrap(text.id))
        )
        XCTAssertEqual(
            updatedText.createdAt.timeIntervalSinceReferenceDate,
            now.timeIntervalSinceReferenceDate,
            accuracy: 0.000_001
        )
    }

    func testSeparatorOptionsProduceExpectedValues() {
        XCTAssertEqual(BulkSeparatorOption.newline.value(customValue: "ignored"), "\n")
        XCTAssertEqual(BulkSeparatorOption.doubleNewline.value(customValue: "ignored"), "\n\n")
        XCTAssertEqual(BulkSeparatorOption.space.value(customValue: "ignored"), " ")
        XCTAssertEqual(BulkSeparatorOption.commaSpace.value(customValue: "ignored"), ", ")
        XCTAssertEqual(BulkSeparatorOption.semicolonSpace.value(customValue: "ignored"), "; ")
        XCTAssertEqual(BulkSeparatorOption.tab.value(customValue: "ignored"), "\t")
        XCTAssertEqual(BulkSeparatorOption.empty.value(customValue: "ignored"), "")
        XCTAssertEqual(BulkSeparatorOption.custom.value(customValue: " <> "), " <> ")
    }

    func testBulkPasteJoinsConsecutiveTextsWithSpaces() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let source = BulkPasteDataSource(
            repository: harness.repository,
            blobStorage: harness.blobStorage
        )
        let first = try harness.insertText("First")
        let second = try harness.insertText("Second")
        let third = try harness.insertText("Third")

        let combined = try await source.combinedText(
            for: [first, second, third],
            separator: " "
        )

        XCTAssertEqual(combined, "First Second Third")
    }

    func testBulkPasteCardFormatsProduceExpectedText() {
        let values = ["First", "Second", "Third"]

        XCTAssertEqual(BulkPasteFormat.newline.combine(values), "First\nSecond\nThird")
        XCTAssertEqual(
            BulkPasteFormat.bullets.combine(values),
            "• First\n• Second\n• Third"
        )
        XCTAssertEqual(BulkPasteFormat.commaSpace.combine(values), "First, Second, Third")
        XCTAssertEqual(BulkPasteFormat.periodSpace.combine(values), "First. Second. Third")
        XCTAssertEqual(BulkPasteFormat.slash.combine(values), "First / Second / Third")
    }

    func testBulkDataSourceRejectsNonTextClips() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let source = BulkPasteDataSource(
            repository: harness.repository,
            blobStorage: harness.blobStorage
        )
        let image = ClipRecord(
            type: ClipContentType.image.rawValue,
            content: "1.png",
            previewText: "10 × 10",
            createdAt: Date()
        )

        do {
            _ = try await source.combinedText(for: [image], separator: "\n")
            XCTFail("Expected an unsupported-type error")
        } catch let error as BulkPasteDataSource.BulkPasteError {
            guard case .unsupportedType(ClipContentType.image.rawValue) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    private func makeHarness() throws -> BulkPasteTestHarness {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BulkPasteTests-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppPaths(applicationSupportRoot: root)
        let database = try AppDatabase(paths: paths)
        let repository = ClipRepository(database: database)
        let blobStorage = try BlobStorage(paths: paths)
        let processor = PasteboardCaptureProcessor(
            repository: repository,
            blobStorage: blobStorage
        )
        return BulkPasteTestHarness(
            root: root,
            database: database,
            repository: repository,
            blobStorage: blobStorage,
            processor: processor
        )
    }
}

private struct BulkPasteTestHarness {
    let root: URL
    let database: AppDatabase
    let repository: ClipRepository
    let blobStorage: BlobStorage
    let processor: PasteboardCaptureProcessor

    @MainActor
    func makeMonitor(pasteboard: NSPasteboard) -> PasteboardMonitor {
        PasteboardMonitor(
            pasteboard: pasteboard,
            processor: processor,
            interval: 60
        )
    }

    func insertText(_ value: String) throws -> ClipRecord {
        try insert(type: .text, content: value)
    }

    func insertURL(_ value: String) throws -> ClipRecord {
        try insert(type: .url, content: value)
    }

    func insertRTF(_ value: String) throws -> ClipRecord {
        let attributedString = NSAttributedString(string: value)
        let data = try attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let storage = blobStorage
        return try repository.insert(
            ClipRecord(
                type: ClipContentType.rtf.rawValue,
                content: "",
                previewText: value,
                createdAt: Date(timeIntervalSince1970: 1)
            ),
            preparingContent: { id in try storage.saveRTF(data, for: id) },
            rollbackContent: { id in try? storage.deleteAll(for: id) }
        )
    }

    private func insert(type: ClipContentType, content: String) throws -> ClipRecord {
        try repository.insert(
            ClipRecord(
                type: type.rawValue,
                content: content,
                previewText: content,
                createdAt: Date(timeIntervalSince1970: 1)
            )
        )
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }
}
