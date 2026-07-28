import AppKit
import Foundation
import XCTest
@testable import KPaste

@MainActor
final class PasteboardMonitorTests: XCTestCase {
    func testMonitorCapturesChangeAndSourceBundleIdentifier() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        defer { pasteboard.clearContents() }

        let monitor = PasteboardMonitor(
            pasteboard: pasteboard,
            processor: harness.processor,
            interval: 60,
            sourceBundleIDProvider: { "com.example.Source" }
        )
        monitor.start()
        defer { monitor.stop() }

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("Captured text", forType: .string))
        XCTAssertTrue(monitor.checkForChanges())
        await monitor.waitForPendingProcessing()

        let clips = try harness.repository.fetchHistory()
        let clip = try XCTUnwrap(clips.first)
        XCTAssertEqual(clips.count, 1)
        XCTAssertEqual(clip.type, ClipContentType.text.rawValue)
        XCTAssertEqual(clip.content, "Captured text")
        XCTAssertEqual(clip.appBundleID, "com.example.Source")
    }

    func testMonitorIgnoresSensitiveMarkers() async throws {
        for marker in [ClipboardParser.concealedType, ClipboardParser.transientType] {
            let harness = try makeHarness()
            defer { harness.cleanUp() }
            let pasteboard = NSPasteboard.withUniqueName()
            pasteboard.clearContents()
            defer { pasteboard.clearContents() }
            let monitor = PasteboardMonitor(
                pasteboard: pasteboard,
                processor: harness.processor,
                interval: 60
            )
            monitor.start()

            pasteboard.declareTypes([.string, marker], owner: nil)
            pasteboard.setString("secret", forType: .string)
            pasteboard.setData(Data(), forType: marker)
            XCTAssertFalse(monitor.checkForChanges())
            await monitor.waitForPendingProcessing()

            XCTAssertEqual(try harness.repository.fetchHistory(), [])
            monitor.stop()
        }
    }

    func testSelfWriteIsSuppressedButNextExternalChangeIsCaptured() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        defer { pasteboard.clearContents() }
        let monitor = PasteboardMonitor(
            pasteboard: pasteboard,
            processor: harness.processor,
            interval: 60
        )
        monitor.start()
        defer { monitor.stop() }

        monitor.performSelfWrite { pasteboard in
            pasteboard.clearContents()
            XCTAssertTrue(pasteboard.setString("KPaste write", forType: .string))
        }
        XCTAssertFalse(monitor.checkForChanges())
        await monitor.waitForPendingProcessing()
        XCTAssertEqual(try harness.repository.fetchHistory(), [])

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("External write", forType: .string))
        XCTAssertTrue(monitor.checkForChanges())
        await monitor.waitForPendingProcessing()
        XCTAssertEqual(try harness.repository.fetchHistory().map(\.content), ["External write"])
    }

    func testTimerStartsOnceAndStopsCleanly() throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let monitor = PasteboardMonitor(
            pasteboard: NSPasteboard.withUniqueName(),
            processor: harness.processor,
            interval: 60
        )

        XCTAssertEqual(PasteboardMonitor.pollingInterval, 0.4)
        XCTAssertFalse(monitor.isRunning)
        monitor.start()
        XCTAssertTrue(monitor.isRunning)
        monitor.start()
        XCTAssertTrue(monitor.isRunning)
        monitor.stop()
        XCTAssertFalse(monitor.isRunning)
    }

    func testConsecutiveDuplicatesForEveryContentTypeAreSkipped() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let sourceBundleID = "com.example.Source"

        let text = ParsedClipboardItem(
            type: .text,
            payload: .text("same text"),
            previewText: "same text"
        )
        _ = try await harness.processor.process(text, sourceBundleID: sourceBundleID)
        let duplicateText = try await harness.processor.process(text, sourceBundleID: sourceBundleID)
        XCTAssertNil(duplicateText)

        let url = URL(string: "https://example.com/path")!
        let urlItem = ParsedClipboardItem(
            type: .url,
            payload: .url(url),
            previewText: url.absoluteString
        )
        _ = try await harness.processor.process(urlItem, sourceBundleID: sourceBundleID)
        let duplicateURL = try await harness.processor.process(urlItem, sourceBundleID: sourceBundleID)
        XCTAssertNil(duplicateURL)

        let rtfData = Data("{\\rtf1 identical}".utf8)
        let rtf = ParsedClipboardItem(
            type: .rtf,
            payload: .rtf(data: rtfData, plainText: "identical"),
            previewText: "identical"
        )
        _ = try await harness.processor.process(rtf, sourceBundleID: sourceBundleID)
        let duplicateRTF = try await harness.processor.process(rtf, sourceBundleID: sourceBundleID)
        XCTAssertNil(duplicateRTF)

        let image = makeImageItem(width: 6, height: 4)
        _ = try await harness.processor.process(image, sourceBundleID: sourceBundleID)
        let duplicateImage = try await harness.processor.process(image, sourceBundleID: sourceBundleID)
        XCTAssertNil(duplicateImage)

        let sourceDirectory = harness.temporaryRoot
            .appendingPathComponent("sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let file = sourceDirectory.appendingPathComponent("file.txt")
        let folder = sourceDirectory.appendingPathComponent("Folder", isDirectory: true)
        try Data("file bytes".utf8).write(to: file)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("nested bytes".utf8).write(to: folder.appendingPathComponent("nested.txt"))
        let files = ParsedClipboardItem(
            type: .file,
            payload: .files([file, folder]),
            previewText: "file.txt, Folder"
        )
        _ = try await harness.processor.process(files, sourceBundleID: sourceBundleID)
        let duplicateFiles = try await harness.processor.process(files, sourceBundleID: sourceBundleID)
        XCTAssertNil(duplicateFiles)

        let clips = try harness.repository.fetchHistory()
        XCTAssertEqual(clips.count, 5)
        XCTAssertEqual(
            clips.map(\.type),
            ["file", "image", "rtf", "url", "text"]
        )
        XCTAssertTrue(clips.allSatisfy { $0.appBundleID == sourceBundleID })
    }

    func testDeduplicationIsOnlyConsecutive() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let first = textItem("A")
        let second = textItem("B")

        _ = try await harness.processor.process(first, sourceBundleID: nil)
        _ = try await harness.processor.process(second, sourceBundleID: nil)
        _ = try await harness.processor.process(first, sourceBundleID: nil)

        XCTAssertEqual(
            try harness.repository.fetchHistory().map(\.content),
            ["A", "B", "A"]
        )
    }

    func testChangedNestedFileCreatesNewClip() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let folder = harness.temporaryRoot.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let nestedFile = folder.appendingPathComponent("nested.txt")
        try Data("version one".utf8).write(to: nestedFile)
        let item = ParsedClipboardItem(
            type: .file,
            payload: .files([folder]),
            previewText: "Folder"
        )

        _ = try await harness.processor.process(item, sourceBundleID: nil)
        let duplicate = try await harness.processor.process(item, sourceBundleID: nil)
        XCTAssertNil(duplicate)

        try Data("version two".utf8).write(to: nestedFile)
        let changed = try await harness.processor.process(item, sourceBundleID: nil)
        XCTAssertNotNil(changed)
        XCTAssertEqual(try harness.repository.fetchHistory().count, 2)
    }

    func testBlobFailureRollsBackDatabaseAndRemovesArtifacts() async throws {
        let harness = try makeHarness()
        defer { harness.cleanUp() }
        let missingFile = harness.temporaryRoot.appendingPathComponent("missing.txt")
        let item = ParsedClipboardItem(
            type: .file,
            payload: .files([missingFile]),
            previewText: "missing.txt"
        )

        do {
            _ = try await harness.processor.process(item, sourceBundleID: nil)
            XCTFail("Expected file copy to fail")
        } catch {
            // Expected: the source disappears before a complete blob can be prepared.
        }

        XCTAssertEqual(try harness.repository.fetchHistory(), [])
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: harness.paths.blobsDirectory.path),
            []
        )
    }

    private func textItem(_ text: String) -> ParsedClipboardItem {
        ParsedClipboardItem(type: .text, payload: .text(text), previewText: text)
    }

    private func makeImageItem(width: Int, height: Int) -> ParsedClipboardItem {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            fatalError("Unable to create test image")
        }
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(representation)
        let data = image.tiffRepresentation!
        return ParsedClipboardItem(
            type: .image,
            payload: .image(
                ClipboardImage(data: data, pixelWidth: width, pixelHeight: height)
            ),
            previewText: "\(width) × \(height)"
        )
    }

    private func makeHarness() throws -> MonitorTestHarness {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteboardMonitorTests-\(UUID().uuidString)", isDirectory: true)
        let paths = try AppPaths(applicationSupportRoot: temporaryRoot)
        let database = try AppDatabase(paths: paths)
        let repository = ClipRepository(database: database)
        let blobStorage = try BlobStorage(paths: paths)
        let processor = PasteboardCaptureProcessor(
            repository: repository,
            blobStorage: blobStorage
        )
        return MonitorTestHarness(
            temporaryRoot: temporaryRoot,
            paths: paths,
            database: database,
            repository: repository,
            blobStorage: blobStorage,
            processor: processor
        )
    }
}

private struct MonitorTestHarness {
    let temporaryRoot: URL
    let paths: AppPaths
    let database: AppDatabase
    let repository: ClipRepository
    let blobStorage: BlobStorage
    let processor: PasteboardCaptureProcessor

    func cleanUp() {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }
}
