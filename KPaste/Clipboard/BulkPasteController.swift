import AppKit
import Combine
import Foundation

enum BulkSeparatorOption: String, CaseIterable, Identifiable, Sendable {
    case newline
    case doubleNewline
    case space
    case commaSpace
    case semicolonSpace
    case tab
    case empty
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newline: "New line"
        case .doubleNewline: "Blank line"
        case .space: "Space"
        case .commaSpace: "Comma"
        case .semicolonSpace: "Semicolon"
        case .tab: "Tab"
        case .empty: "No separator"
        case .custom: "Custom"
        }
    }

    func value(customValue: String) -> String {
        switch self {
        case .newline: "\n"
        case .doubleNewline: "\n\n"
        case .space: " "
        case .commaSpace: ", "
        case .semicolonSpace: "; "
        case .tab: "\t"
        case .empty: ""
        case .custom: customValue
        }
    }
}

actor BulkPasteDataSource {
    enum BulkPasteError: LocalizedError {
        case emptySelection
        case missingClipID
        case unsupportedType(String)

        var errorDescription: String? {
            switch self {
            case .emptySelection: "Select at least one text clip."
            case .missingClipID: "A selected clip has no database identifier."
            case .unsupportedType(let type): "Clip type \(type) cannot be bulk pasted."
            }
        }
    }

    private let repository: ClipRepository
    private let blobStorage: BlobStorage
    private let now: @Sendable () -> Date

    init(
        repository: ClipRepository,
        blobStorage: BlobStorage,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.repository = repository
        self.blobStorage = blobStorage
        self.now = now
    }

    func combinedText(for clips: [ClipRecord], separator: String) throws -> String {
        guard !clips.isEmpty else {
            throw BulkPasteError.emptySelection
        }
        return try clips.map(plainText).joined(separator: separator)
    }

    func markUsed(_ clips: [ClipRecord]) throws {
        let identifiers = try clips.map { clip in
            guard let id = clip.id else {
                throw BulkPasteError.missingClipID
            }
            return id
        }
        try repository.markUsedPreservingOrder(ids: identifiers, at: now())
    }

    private func plainText(for clip: ClipRecord) throws -> String {
        switch ClipContentType(rawValue: clip.type) {
        case .text, .url:
            return clip.content
        case .rtf:
            let data = try blobStorage.readData(atRelativePath: clip.content)
            return try NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            ).string
        case .image, .file, nil:
            throw BulkPasteError.unsupportedType(clip.type)
        }
    }
}

@MainActor
final class BulkPasteController {
    enum BulkPasteError: LocalizedError {
        case pasteboardWriteFailed

        var errorDescription: String? {
            "The combined text could not be written to the pasteboard."
        }
    }

    private let dataSource: BulkPasteDataSource
    private let monitor: PasteboardMonitor

    init(
        repository: ClipRepository,
        blobStorage: BlobStorage,
        monitor: PasteboardMonitor,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        dataSource = BulkPasteDataSource(
            repository: repository,
            blobStorage: blobStorage,
            now: now
        )
        self.monitor = monitor
    }

    func paste(_ clips: [ClipRecord], separator: String) async throws {
        let combinedText = try await dataSource.combinedText(
            for: clips,
            separator: separator
        )
        try monitor.performSelfWrite { pasteboard in
            pasteboard.declareTypes([.string], owner: nil)
            guard pasteboard.setString(combinedText, forType: .string) else {
                throw BulkPasteError.pasteboardWriteFailed
            }
        }
        try await dataSource.markUsed(clips)
    }
}
