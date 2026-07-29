import AppKit
import Foundation
import XCTest
@testable import KPaste

@MainActor
final class ClipRestorerTests: XCTestCase {
    func testRestoresTextAndURLSuppressesMonitoringAndMarksClipUsed() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        defer { pasteboard.clearContents() }

        let monitor = harness.makeMonitor(pasteboard: pasteboard)
        monitor.start()
        defer { monitor.stop() }
        let restorer = harness.makeRestorer(monitor: monitor)
        let oldDate = Date(timeIntervalSince1970: 1)

        let text = try harness.repository.insert(
            ClipRecord(
                type: ClipContentType.text.rawValue,
                content: "Hello from KPaste",
                previewText: "Hello from KPaste",
                createdAt: oldDate
            )
        )
        try await restorer.restore(text)

        XCTAssertEqual(pasteboard.string(forType: .string), "Hello from KPaste")
        XCTAssertFalse(monitor.checkForChanges())
        XCTAssertGreaterThan(
            try XCTUnwrap(harness.repository.fetch(id: try XCTUnwrap(text.id))).createdAt,
            oldDate
        )

        let urlValue = "https://example.com/path"
        let url = try harness.repository.insert(
            ClipRecord(
                type: ClipContentType.url.rawValue,
                content: urlValue,
                previewText: urlValue,
                createdAt: oldDate
            )
        )
        try await restorer.restore(url)

        XCTAssertEqual(pasteboard.string(forType: .URL), urlValue)
        XCTAssertEqual(pasteboard.string(forType: .string), urlValue)
        XCTAssertFalse(monitor.checkForChanges())
    }

    func testRestoresRTFPNGAndCopiedFilesAsTheirNativePasteboardTypes() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        defer { pasteboard.clearContents() }
        let monitor = harness.makeMonitor(pasteboard: pasteboard)
        let restorer = harness.makeRestorer(monitor: monitor)
        let storage = harness.blobStorage

        let rtfData = Data("{\\rtf1\\ansi Restored}".utf8)
        let rtf = try insertBlobClip(
            type: .rtf,
            preview: "Restored",
            repository: harness.repository,
            storage: harness.blobStorage
        ) { id in
            try storage.saveRTF(rtfData, for: id)
        }
        try await restorer.restore(rtf)
        let restoredRTF = try XCTUnwrap(pasteboard.data(forType: .rtf))
        let restoredRichText = try NSAttributedString(
            data: restoredRTF,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        XCTAssertEqual(restoredRichText.string, "Restored")
        XCTAssertEqual(pasteboard.string(forType: .string), "Restored")

        let image = NSImage(size: NSSize(width: 8, height: 6), flipped: false) { rect in
            NSColor.systemBlue.setFill()
            rect.fill()
            return true
        }
        let imageData = try XCTUnwrap(image.tiffRepresentation)
        let pngData = try storage.normalizedPNGData(from: imageData)
        let imageClip = try insertBlobClip(
            type: .image,
            preview: "8 × 6",
            repository: harness.repository,
            storage: harness.blobStorage
        ) { id in
            try storage.savePNGData(pngData, for: id)
        }
        let expectedPNG = try harness.blobStorage.readData(atRelativePath: imageClip.content)
        try await restorer.restore(imageClip)
        XCTAssertEqual(pasteboard.data(forType: .png), expectedPNG)

        let source = harness.temporaryRoot.appendingPathComponent("source.txt")
        try Data("file data".utf8).write(to: source)
        let fileClip = try insertBlobClip(
            type: .file,
            preview: "source.txt",
            repository: harness.repository,
            storage: harness.blobStorage
        ) { id in
            try storage.saveFiles(at: [source], for: id)
        }
        let expectedFileURL = try XCTUnwrap(
            harness.blobStorage.fileURLs(from: fileClip.content).first
        )
        try await restorer.restore(fileClip)
        let restoredURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        XCTAssertEqual(restoredURLs, [expectedFileURL])
    }

    func testPlainTextModeStripsRichTextAndURLPasteboardTypes() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        defer { pasteboard.clearContents() }
        let restorer = harness.makeRestorer(
            monitor: harness.makeMonitor(pasteboard: pasteboard)
        )
        let storage = harness.blobStorage

        let richText = NSAttributedString(
            string: "Styled text",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 16)]
        )
        let rtfData = try richText.data(
            from: NSRange(location: 0, length: richText.length),
            documentAttributes: [
                .documentType: NSAttributedString.DocumentType.rtf,
            ]
        )
        let rtf = try insertBlobClip(
            type: .rtf,
            preview: "Styled text",
            repository: harness.repository,
            storage: harness.blobStorage
        ) { id in
            try storage.saveRTF(rtfData, for: id)
        }

        try await restorer.restore(rtf, asPlainText: true)

        XCTAssertTrue(pasteboard.types?.contains(.string) == true)
        XCTAssertEqual(pasteboard.string(forType: .string), "Styled text")
        XCTAssertNil(pasteboard.data(forType: .rtf))

        let urlValue = "https://example.com/plain"
        let url = try harness.repository.insert(
            ClipRecord(
                type: ClipContentType.url.rawValue,
                content: urlValue,
                previewText: urlValue,
                createdAt: Date()
            )
        )

        try await restorer.restore(url, asPlainText: true)

        XCTAssertTrue(pasteboard.types?.contains(.string) == true)
        XCTAssertEqual(pasteboard.string(forType: .string), urlValue)
        XCTAssertNil(pasteboard.string(forType: .URL))
    }

    func testThumbnailIsDecodedOffTheStoredPNGAndBounded() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let image = NSImage(size: NSSize(width: 120, height: 60), flipped: false) { rect in
            NSColor.systemGreen.setFill()
            rect.fill()
            return true
        }
        _ = try harness.blobStorage.saveImage(image, for: 1)
        let cache = ImageThumbnailCache(blobStorage: harness.blobStorage, maximumEntryCount: 2)

        let thumbnail = try await cache.thumbnail(for: 1, maximumPixelSize: 24)

        XCTAssertLessThanOrEqual(max(thumbnail.width, thumbnail.height), 24)
        XCTAssertGreaterThan(thumbnail.width, thumbnail.height)
    }

    private func insertBlobClip(
        type: ClipContentType,
        preview: String,
        repository: ClipRepository,
        storage: BlobStorage,
        save: @escaping @Sendable (Int64) throws -> String
    ) throws -> ClipRecord {
        try repository.insert(
            ClipRecord(
                type: type.rawValue,
                content: "",
                previewText: preview,
                createdAt: Date(timeIntervalSince1970: 1)
            ),
            preparingContent: save,
            rollbackContent: { id in try? storage.deleteAll(for: id) }
        )
    }

    private func makeHarness() throws -> RestorerTestHarness {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipRestorerTests-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppPaths(applicationSupportRoot: temporaryRoot)
        let database = try AppDatabase(paths: paths)
        let repository = ClipRepository(database: database)
        let blobStorage = try BlobStorage(paths: paths)
        let processor = PasteboardCaptureProcessor(
            repository: repository,
            blobStorage: blobStorage
        )
        return RestorerTestHarness(
            temporaryRoot: temporaryRoot,
            database: database,
            repository: repository,
            blobStorage: blobStorage,
            processor: processor
        )
    }
}

private struct RestorerTestHarness {
    let temporaryRoot: URL
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

    @MainActor
    func makeRestorer(monitor: PasteboardMonitor) -> ClipRestorer {
        ClipRestorer(
            repository: repository,
            blobStorage: blobStorage,
            monitor: monitor
        )
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }
}
