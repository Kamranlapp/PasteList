import AppKit
import Foundation

enum ClipContentType: String, Codable, Sendable {
    case text
    case rtf
    case image
    case file
    case url
}

struct ClipboardImage: Equatable, Sendable {
    let data: Data
    let pixelWidth: Int
    let pixelHeight: Int
}

enum ClipboardPayload: Equatable, Sendable {
    case text(String)
    case rtf(data: Data, plainText: String)
    case image(ClipboardImage)
    case files([URL])
    case url(URL)
}

struct ParsedClipboardItem: Equatable, Sendable {
    let type: ClipContentType
    let payload: ClipboardPayload
    let previewText: String
}

struct ClipboardParser: Sendable {
    static let concealedType = NSPasteboard.PasteboardType(
        "org.nspasteboard.ConcealedType"
    )
    static let transientType = NSPasteboard.PasteboardType(
        "org.nspasteboard.TransientType"
    )

    private static let maximumTextPreviewLength = 200

    func parse(_ pasteboard: NSPasteboard) -> ParsedClipboardItem? {
        guard !containsSensitiveMarker(pasteboard) else {
            return nil
        }

        if let files = readFiles(from: pasteboard) {
            return ParsedClipboardItem(
                type: .file,
                payload: .files(files),
                previewText: files.map(\.lastPathComponent).joined(separator: ", ")
            )
        }

        if let image = readImage(from: pasteboard) {
            return ParsedClipboardItem(
                type: .image,
                payload: .image(image),
                previewText: "\(image.pixelWidth) × \(image.pixelHeight)"
            )
        }

        if let rtfData = pasteboard.data(forType: .rtf) {
            let plainText = readRTFPlainText(rtfData)
                ?? pasteboard.string(forType: .string)
                ?? ""
            return ParsedClipboardItem(
                type: .rtf,
                payload: .rtf(data: rtfData, plainText: plainText),
                previewText: textPreview(plainText)
            )
        }

        if
            let urlString = pasteboard.string(forType: .URL),
            let explicitURL = explicitURL(from: urlString)
        {
            return ParsedClipboardItem(
                type: .url,
                payload: .url(explicitURL),
                previewText: explicitURL.absoluteString
            )
        }

        guard let text = pasteboard.string(forType: .string) else {
            return nil
        }

        if let webURL = inferredWebURL(from: text) {
            return ParsedClipboardItem(
                type: .url,
                payload: .url(webURL),
                previewText: webURL.absoluteString
            )
        }

        return ParsedClipboardItem(
            type: .text,
            payload: .text(text),
            previewText: textPreview(text)
        )
    }

    private func containsSensitiveMarker(_ pasteboard: NSPasteboard) -> Bool {
        guard let types = pasteboard.types else {
            return false
        }
        return types.contains(Self.concealedType) || types.contains(Self.transientType)
    }

    private func readFiles(from pasteboard: NSPasteboard) -> [URL]? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        guard let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) else {
            return nil
        }

        let fileURLs = objects.compactMap { object -> URL? in
            guard let url = object as? NSURL else {
                return nil
            }
            let bridgedURL = url as URL
            return bridgedURL.isFileURL ? bridgedURL : nil
        }
        return fileURLs.isEmpty ? nil : fileURLs
    }

    private func readImage(from pasteboard: NSPasteboard) -> ClipboardImage? {
        guard
            let image = pasteboard.readObjects(
                forClasses: [NSImage.self],
                options: nil
            )?.first as? NSImage,
            let data = image.tiffRepresentation
        else {
            return nil
        }

        let representation = image.representations.max { lhs, rhs in
            lhs.pixelsWide * lhs.pixelsHigh < rhs.pixelsWide * rhs.pixelsHigh
        }
        let width = representation?.pixelsWide ?? Int(image.size.width.rounded())
        let height = representation?.pixelsHigh ?? Int(image.size.height.rounded())
        guard width > 0, height > 0 else {
            return nil
        }

        return ClipboardImage(data: data, pixelWidth: width, pixelHeight: height)
    }

    private func readRTFPlainText(_ data: Data) -> String? {
        try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ).string
    }

    private func explicitURL(from string: String) -> URL? {
        guard
            let url = URL(string: string),
            let scheme = url.scheme,
            !scheme.isEmpty
        else {
            return nil
        }
        return url
    }

    private func inferredWebURL(from string: String) -> URL? {
        guard
            !string.isEmpty,
            let components = URLComponents(string: string),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            components.host?.isEmpty == false,
            let url = components.url
        else {
            return nil
        }
        return url
    }

    private func textPreview(_ text: String) -> String {
        let normalized = text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return String(normalized.prefix(Self.maximumTextPreviewLength))
    }
}

