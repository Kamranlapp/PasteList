import AppKit
import Foundation

enum RestoredPasteboardPayload: Equatable, Sendable {
    case text(String)
    case url(String)
    case rtf(Data)
    case imagePNG(Data)
    case files([URL])
}

actor ClipRestorationDataSource {
    enum RestorationError: LocalizedError {
        case missingClipID
        case unsupportedClipType(String)

        var errorDescription: String? {
            switch self {
            case .missingClipID:
                "The clip has no database identifier."
            case .unsupportedClipType(let type):
                "Unsupported clip type: \(type)"
            }
        }
    }

    private let repository: ClipRepository
    private let blobStorage: BlobStorage

    init(repository: ClipRepository, blobStorage: BlobStorage) {
        self.repository = repository
        self.blobStorage = blobStorage
    }

    func payload(for clip: ClipRecord) throws -> RestoredPasteboardPayload {
        switch ClipContentType(rawValue: clip.type) {
        case .text:
            return .text(clip.content)
        case .url:
            return .url(clip.content)
        case .rtf:
            return .rtf(try blobStorage.readData(atRelativePath: clip.content))
        case .image:
            return .imagePNG(try blobStorage.readData(atRelativePath: clip.content))
        case .file:
            return .files(try blobStorage.fileURLs(from: clip.content))
        case nil:
            throw RestorationError.unsupportedClipType(clip.type)
        }
    }

    func markUsed(_ clip: ClipRecord) throws {
        guard let id = clip.id else {
            throw RestorationError.missingClipID
        }
        _ = try repository.markUsed(id: id)
    }
}

@MainActor
final class ClipRestorer {
    enum RestorationError: LocalizedError {
        case pasteboardWriteFailed

        var errorDescription: String? {
            "The clip could not be written to the pasteboard."
        }
    }

    private let dataSource: ClipRestorationDataSource
    private let monitor: PasteboardMonitor

    init(
        repository: ClipRepository,
        blobStorage: BlobStorage,
        monitor: PasteboardMonitor
    ) {
        dataSource = ClipRestorationDataSource(
            repository: repository,
            blobStorage: blobStorage
        )
        self.monitor = monitor
    }

    func restore(_ clip: ClipRecord) async throws {
        let payload = try await dataSource.payload(for: clip)
        try monitor.performSelfWrite { pasteboard in
            try write(payload, to: pasteboard)
        }
        try await dataSource.markUsed(clip)
    }

    private func write(
        _ payload: RestoredPasteboardPayload,
        to pasteboard: NSPasteboard
    ) throws {
        let succeeded: Bool

        switch payload {
        case .text(let text):
            pasteboard.declareTypes([.string], owner: nil)
            succeeded = pasteboard.setString(text, forType: .string)

        case .url(let value):
            pasteboard.declareTypes([.URL, .string], owner: nil)
            let wroteURL = pasteboard.setString(value, forType: .URL)
            let wroteString = pasteboard.setString(value, forType: .string)
            succeeded = wroteURL && wroteString

        case .rtf(let data):
            pasteboard.declareTypes([.rtf], owner: nil)
            succeeded = pasteboard.setData(data, forType: .rtf)

        case .imagePNG(let data):
            pasteboard.declareTypes([.png], owner: nil)
            succeeded = pasteboard.setData(data, forType: .png)

        case .files(let urls):
            pasteboard.clearContents()
            succeeded = pasteboard.writeObjects(urls.map { $0 as NSURL })
        }

        guard succeeded else {
            throw RestorationError.pasteboardWriteFailed
        }
    }
}
