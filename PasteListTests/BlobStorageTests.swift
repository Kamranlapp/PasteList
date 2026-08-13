import AppKit
import Foundation
import XCTest
@testable import PasteList

final class BlobStorageTests: XCTestCase {
    func testFilesAreStagedBeforeTheyAreCommittedToAClipID() throws {
        try withStorage { storage, paths, temporaryRoot in
            let source = temporaryRoot.appendingPathComponent("staged.txt")
            try Data("staged".utf8).write(to: source)

            let staged = try storage.stageFiles(at: [source])
            defer { storage.discard(staged) }

            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: paths.blobsDirectory.appendingPathComponent("77").path
                )
            )
            XCTAssertTrue(
                try FileManager.default.contentsOfDirectory(atPath: paths.blobsDirectory.path)
                    .contains { $0.hasPrefix(".staging-") }
            )

            let manifest = try storage.commit(staged, for: 77)

            XCTAssertEqual(
                try storage.fileURLs(from: manifest).map(\.lastPathComponent),
                ["staged.txt"]
            )
        }
    }

    func testRTFRoundTripUsesRelativePathAndDeletesCleanly() throws {
        try withStorage { storage, paths, _ in
            let rtf = Data("{\\rtf1 Hello}".utf8)
            let relativePath = try storage.saveRTF(rtf, for: 42)

            XCTAssertEqual(relativePath, "42.rtf")
            XCTAssertFalse(NSString(string: relativePath).isAbsolutePath)
            XCTAssertEqual(try storage.readRTF(for: 42), rtf)
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: paths.blobsDirectory.appendingPathComponent(relativePath).path
                )
            )

            try storage.deleteAll(for: 42)
            XCTAssertThrowsError(try storage.readRTF(for: 42))
            try storage.deleteAll(for: 42)
        }
    }

    func testImageIsNormalizedToPNG() throws {
        try withStorage { storage, paths, _ in
            let image = NSImage(size: NSSize(width: 4, height: 3), flipped: false) { rect in
                NSColor.systemRed.setFill()
                rect.fill()
                return true
            }

            let relativePath = try storage.saveImage(image, for: 7)
            let pngData = try storage.readImageData(for: 7)

            XCTAssertEqual(relativePath, "7.png")
            XCTAssertEqual(
                Array(pngData.prefix(8)),
                [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
            )
            let decoded = try XCTUnwrap(NSBitmapImageRep(data: pngData))
            XCTAssertEqual(decoded.pixelsWide, 4)
            XCTAssertEqual(decoded.pixelsHigh, 3)

            let dragURLs = try storage.dragURLs(
                for: ClipRecord(
                    id: 7,
                    type: ClipContentType.image.rawValue,
                    content: relativePath,
                    previewText: "4 × 3",
                    createdAt: Date()
                )
            )
            XCTAssertEqual(
                dragURLs,
                [paths.blobsDirectory.appendingPathComponent(relativePath)]
            )
        }
    }

    func testMultipleFilesAndFolderAreCopiedWithJSONManifest() throws {
        try withStorage { storage, paths, temporaryRoot in
            let sources = temporaryRoot.appendingPathComponent("sources", isDirectory: true)
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)

            let textFile = sources.appendingPathComponent("alpha.txt")
            try Data("original".utf8).write(to: textFile)

            let folder = sources.appendingPathComponent("Folder", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("nested".utf8).write(
                to: folder.appendingPathComponent("nested.txt")
            )

            let manifest = try storage.saveFiles(at: [textFile, folder], for: 12)
            let manifestPaths = try JSONDecoder().decode(
                [String].self,
                from: try XCTUnwrap(manifest.data(using: .utf8))
            )
            XCTAssertEqual(manifestPaths, ["12/alpha.txt", "12/Folder"])
            XCTAssertTrue(manifestPaths.allSatisfy { !NSString(string: $0).isAbsolutePath })

            let copiedURLs = try storage.fileURLs(from: manifest)
            XCTAssertEqual(copiedURLs.map(\.lastPathComponent), ["alpha.txt", "Folder"])
            XCTAssertTrue(copiedURLs.allSatisfy {
                $0.path.hasPrefix(paths.blobsDirectory.path + "/")
            })
            XCTAssertEqual(try Data(contentsOf: copiedURLs[0]), Data("original".utf8))
            XCTAssertEqual(
                try Data(contentsOf: copiedURLs[1].appendingPathComponent("nested.txt")),
                Data("nested".utf8)
            )

            let dragURLs = try storage.dragURLs(
                for: ClipRecord(
                    id: 12,
                    type: ClipContentType.file.rawValue,
                    content: manifest,
                    previewText: "alpha.txt, Folder",
                    createdAt: Date()
                )
            )
            XCTAssertEqual(dragURLs, copiedURLs)

            try Data("changed".utf8).write(to: textFile)
            XCTAssertEqual(try Data(contentsOf: copiedURLs[0]), Data("original".utf8))

            try storage.deleteAll(for: 12)
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: paths.blobsDirectory.appendingPathComponent("12").path
                )
            )
        }
    }

    func testFailedCopyRemovesPartialStagingData() throws {
        try withStorage { storage, paths, temporaryRoot in
            let validFile = temporaryRoot.appendingPathComponent("valid.txt")
            try Data("valid".utf8).write(to: validFile)
            let missingFile = temporaryRoot.appendingPathComponent("missing.txt")

            XCTAssertThrowsError(
                try storage.saveFiles(at: [validFile, missingFile], for: 99)
            )
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: paths.blobsDirectory.appendingPathComponent("99").path
                )
            )
            XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: paths.blobsDirectory.path)
                .contains { $0.hasPrefix(".staging-99-") })
        }
    }

    func testCopyFailureAfterStagingHasStartedLeavesNoGarbage() throws {
        let fileManager = FailingCopyFileManager(failingOnCopyNumber: 2)
        try withStorage(fileManager: fileManager) { storage, paths, temporaryRoot in
            let first = temporaryRoot.appendingPathComponent("first.txt")
            let second = temporaryRoot.appendingPathComponent("second.txt")
            try Data("first".utf8).write(to: first)
            try Data("second".utf8).write(to: second)

            XCTAssertThrowsError(try storage.saveFiles(at: [first, second], for: 100))
            XCTAssertEqual(
                try FileManager.default.contentsOfDirectory(atPath: paths.blobsDirectory.path),
                []
            )
        }
    }

    func testDuplicateTopLevelNamesAreRejectedWithoutCreatingBlobs() throws {
        try withStorage { storage, paths, temporaryRoot in
            let firstDirectory = temporaryRoot.appendingPathComponent("first", isDirectory: true)
            let secondDirectory = temporaryRoot.appendingPathComponent("second", isDirectory: true)
            try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)

            let first = firstDirectory.appendingPathComponent("same.txt")
            let second = secondDirectory.appendingPathComponent("same.txt")
            try Data("first".utf8).write(to: first)
            try Data("second".utf8).write(to: second)

            XCTAssertThrowsError(try storage.saveFiles(at: [first, second], for: 101))
            XCTAssertEqual(
                try FileManager.default.contentsOfDirectory(atPath: paths.blobsDirectory.path),
                []
            )
        }
    }

    func testManifestRejectsAbsoluteAndEscapingPaths() throws {
        try withStorage { storage, _, _ in
            XCTAssertThrowsError(try storage.fileURLs(from: "[\"/tmp/file\"]"))
            XCTAssertThrowsError(try storage.fileURLs(from: "[\"../outside\"]"))
            XCTAssertThrowsError(try storage.fileURLs(from: "not-json"))
        }
    }

    private func withStorage<T>(
        fileManager: FileManager = .default,
        _ body: (BlobStorage, AppPaths, URL) throws -> T
    ) throws -> T {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlobStorageTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }

        let paths = try AppPaths(
            fileManager: fileManager,
            applicationSupportRoot: temporaryRoot
        )
        let storage = try BlobStorage(paths: paths, fileManager: fileManager)
        return try body(storage, paths, temporaryRoot)
    }
}

private final class FailingCopyFileManager: FileManager, @unchecked Sendable {
    enum ForcedError: Error {
        case copyFailed
    }

    private let failingOnCopyNumber: Int
    private var copyCount = 0

    init(failingOnCopyNumber: Int) {
        self.failingOnCopyNumber = failingOnCopyNumber
        super.init()
    }

    override func copyItem(at sourceURL: URL, to destinationURL: URL) throws {
        copyCount += 1
        if copyCount == failingOnCopyNumber {
            throw ForcedError.copyFailed
        }
        try super.copyItem(at: sourceURL, to: destinationURL)
    }
}
