import AppKit
import Foundation
import XCTest
@testable import KPaste

final class ClipboardParserTests: XCTestCase {
    private let parser = ClipboardParser()

    func testConcealedAndTransientMarkersAreIgnoredBeforeReading() {
        for marker in [ClipboardParser.concealedType, ClipboardParser.transientType] {
            withPasteboard { pasteboard in
                pasteboard.declareTypes([.string, marker], owner: nil)
                pasteboard.setString("secret", forType: .string)
                pasteboard.setData(Data(), forType: marker)

                XCTAssertNil(parser.parse(pasteboard))
            }
        }
    }

    func testFilesAndFoldersHaveHighestPriority() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardParserTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)

        let file = temporaryRoot.appendingPathComponent("document.txt")
        let folder = temporaryRoot.appendingPathComponent("Folder", isDirectory: true)
        try Data("text".utf8).write(to: file)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        withPasteboard { pasteboard in
            let image = makeImage(width: 2, height: 2)
            XCTAssertTrue(pasteboard.writeObjects([file as NSURL, folder as NSURL, image]))

            let item = parser.parse(pasteboard)
            XCTAssertEqual(item?.type, .file)
            XCTAssertEqual(item?.previewText, "document.txt, Folder")
            guard case .files(let urls) = item?.payload else {
                return XCTFail("Expected file payload")
            }
            XCTAssertEqual(urls, [file, folder])
        }
    }

    func testImageHasPriorityOverRTFAndReportsPixelDimensions() throws {
        try withPasteboard { pasteboard in
            let image = makeImage(width: 8, height: 5)
            let rtf = try makeRTF("Lower priority")
            pasteboard.declareTypes([.tiff, .rtf], owner: nil)
            pasteboard.setData(try XCTUnwrap(image.tiffRepresentation), forType: .tiff)
            pasteboard.setData(rtf, forType: .rtf)

            let item = parser.parse(pasteboard)
            XCTAssertEqual(item?.type, .image)
            XCTAssertEqual(item?.previewText, "8 × 5")
            guard case .image(let parsedImage) = item?.payload else {
                return XCTFail("Expected image payload")
            }
            XCTAssertEqual(parsedImage.pixelWidth, 8)
            XCTAssertEqual(parsedImage.pixelHeight, 5)
            XCTAssertFalse(parsedImage.data.isEmpty)
        }
    }

    func testRTFReturnsOriginalDataAndPlainTextPreview() throws {
        let plainText = "Styled text\nwith another line"
        let rtf = try makeRTF(plainText)

        withPasteboard { pasteboard in
            pasteboard.declareTypes([.rtf, .URL, .string], owner: nil)
            pasteboard.setData(rtf, forType: .rtf)
            pasteboard.setString("https://example.com", forType: .URL)
            pasteboard.setString("Fallback", forType: .string)

            let item = parser.parse(pasteboard)
            XCTAssertEqual(item?.type, .rtf)
            XCTAssertEqual(item?.previewText, "Styled text with another line")
            guard case .rtf(let parsedData, let parsedText) = item?.payload else {
                return XCTFail("Expected RTF payload")
            }
            XCTAssertEqual(parsedData, rtf)
            XCTAssertEqual(parsedText, plainText)
        }
    }

    func testExplicitURLHasPriorityOverPlainText() {
        withPasteboard { pasteboard in
            pasteboard.declareTypes([.URL, .string], owner: nil)
            pasteboard.setString("mailto:test@example.com", forType: .URL)
            pasteboard.setString("Ordinary text", forType: .string)

            let item = parser.parse(pasteboard)
            XCTAssertEqual(item?.type, .url)
            XCTAssertEqual(item?.previewText, "mailto:test@example.com")
            guard case .url(let url) = item?.payload else {
                return XCTFail("Expected URL payload")
            }
            XCTAssertEqual(url.absoluteString, "mailto:test@example.com")
        }
    }

    func testPlainHTTPAndHTTPSStringsAreInferredAsURLs() {
        for address in ["http://example.com/path", "https://example.com?q=1"] {
            withPasteboard { pasteboard in
                pasteboard.setString(address, forType: .string)

                let item = parser.parse(pasteboard)
                XCTAssertEqual(item?.type, .url)
                XCTAssertEqual(item?.previewText, address)
            }
        }
    }

    func testNonWebAndNonEntireURLStringsRemainText() {
        for text in ["ftp://example.com", "https://example.com\nmore"] {
            withPasteboard { pasteboard in
                pasteboard.setString(text, forType: .string)

                let item = parser.parse(pasteboard)
                XCTAssertEqual(item?.type, .text)
                guard case .text(let parsedText) = item?.payload else {
                    return XCTFail("Expected text payload")
                }
                XCTAssertEqual(parsedText, text)
            }
        }
    }

    func testTextPreviewIsNormalizedAndLimitedTo200Characters() {
        let text = String(repeating: "a", count: 210) + "\nsecond line"
        withPasteboard { pasteboard in
            pasteboard.setString(text, forType: .string)

            let item = parser.parse(pasteboard)
            XCTAssertEqual(item?.type, .text)
            XCTAssertEqual(item?.previewText.count, 200)
            XCTAssertEqual(item?.previewText, String(repeating: "a", count: 200))
        }
    }

    func testUnsupportedPasteboardReturnsNil() {
        withPasteboard { pasteboard in
            pasteboard.setData(Data([0x01]), forType: .pdf)
            XCTAssertNil(parser.parse(pasteboard))
        }
    }

    private func withPasteboard(_ body: (NSPasteboard) throws -> Void) rethrows {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        defer { pasteboard.clearContents() }
        try body(pasteboard)
    }

    private func makeImage(width: Int, height: Int) -> NSImage {
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
        return image
    }

    private func makeRTF(_ string: String) throws -> Data {
        let attributedString = NSAttributedString(string: string)
        return try attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }
}
