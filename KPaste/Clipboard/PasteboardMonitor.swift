import AppKit
import Foundation

struct FileContentComparator: @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func contentsEqual(_ lhs: [URL], _ rhs: [URL]) throws -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }

        for (leftURL, rightURL) in zip(lhs, rhs) {
            guard
                leftURL.lastPathComponent == rightURL.lastPathComponent,
                try contentsEqual(leftURL, rightURL)
            else {
                return false
            }
        }
        return true
    }

    private func contentsEqual(_ lhs: URL, _ rhs: URL) throws -> Bool {
        let keys: Set<URLResourceKey> = [
            .fileSizeKey,
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ]
        let leftValues = try lhs.resourceValues(forKeys: keys)
        let rightValues = try rhs.resourceValues(forKeys: keys)

        guard
            leftValues.isDirectory == rightValues.isDirectory,
            leftValues.isRegularFile == rightValues.isRegularFile,
            leftValues.isSymbolicLink == rightValues.isSymbolicLink
        else {
            return false
        }

        if leftValues.isSymbolicLink == true {
            return try fileManager.destinationOfSymbolicLink(atPath: lhs.path)
                == fileManager.destinationOfSymbolicLink(atPath: rhs.path)
        }

        if leftValues.isDirectory == true {
            let leftChildren = try children(of: lhs)
            let rightChildren = try children(of: rhs)
            guard leftChildren.map(\.lastPathComponent) == rightChildren.map(\.lastPathComponent) else {
                return false
            }
            for (leftChild, rightChild) in zip(leftChildren, rightChildren) {
                guard try contentsEqual(leftChild, rightChild) else {
                    return false
                }
            }
            return true
        }

        guard leftValues.fileSize == rightValues.fileSize else {
            return false
        }
        return try fileBytesEqual(lhs, rhs)
    }

    private func children(of directory: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: []
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func fileBytesEqual(_ lhs: URL, _ rhs: URL) throws -> Bool {
        let leftHandle = try FileHandle(forReadingFrom: lhs)
        let rightHandle = try FileHandle(forReadingFrom: rhs)
        defer {
            try? leftHandle.close()
            try? rightHandle.close()
        }

        while true {
            let leftData = try leftHandle.read(upToCount: 64 * 1024) ?? Data()
            let rightData = try rightHandle.read(upToCount: 64 * 1024) ?? Data()
            guard leftData == rightData else {
                return false
            }
            if leftData.isEmpty {
                return true
            }
        }
    }
}

actor PasteboardCaptureProcessor {
    private enum PreparedPayload: Sendable {
        case text(String)
        case rtf(Data)
        case imagePNG(Data)
        case files([URL])
        case url(String)

        var type: ClipContentType {
            switch self {
            case .text: .text
            case .rtf: .rtf
            case .imagePNG: .image
            case .files: .file
            case .url: .url
            }
        }
    }

    private let repository: ClipRepository
    private let blobStorage: BlobStorage
    private let fileComparator: FileContentComparator
    private let now: @Sendable () -> Date

    init(
        repository: ClipRepository,
        blobStorage: BlobStorage,
        fileComparator: FileContentComparator = FileContentComparator(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.repository = repository
        self.blobStorage = blobStorage
        self.fileComparator = fileComparator
        self.now = now
    }

    @discardableResult
    func process(
        _ item: ParsedClipboardItem,
        sourceBundleID: String?
    ) throws -> ClipRecord? {
        let payload = try prepare(item.payload)
        if try isConsecutiveDuplicate(payload) {
            return nil
        }

        let clip = ClipRecord(
            type: payload.type.rawValue,
            content: immediateContent(for: payload) ?? "",
            previewText: item.previewText,
            createdAt: now(),
            appBundleID: sourceBundleID
        )

        switch payload {
        case .text, .url:
            return try repository.insert(clip)

        case .rtf(let data):
            return try insertBlobBacked(clip) { id in
                try self.blobStorage.saveRTF(data, for: id)
            }

        case .imagePNG(let data):
            return try insertBlobBacked(clip) { id in
                try self.blobStorage.savePNGData(data, for: id)
            }

        case .files(let urls):
            return try insertBlobBacked(clip) { id in
                try self.blobStorage.saveFiles(at: urls, for: id)
            }
        }
    }

    private func prepare(_ payload: ClipboardPayload) throws -> PreparedPayload {
        switch payload {
        case .text(let text):
            return .text(text)
        case .rtf(let data, _):
            return .rtf(data)
        case .image(let image):
            return .imagePNG(try blobStorage.normalizedPNGData(from: image.data))
        case .files(let urls):
            return .files(urls)
        case .url(let url):
            return .url(url.absoluteString)
        }
    }

    private func immediateContent(for payload: PreparedPayload) -> String? {
        switch payload {
        case .text(let text), .url(let text):
            return text
        case .rtf, .imagePNG, .files:
            return nil
        }
    }

    private func insertBlobBacked(
        _ clip: ClipRecord,
        save: @escaping @Sendable (Int64) throws -> String
    ) throws -> ClipRecord {
        try repository.insert(
            clip,
            preparingContent: save,
            rollbackContent: { [blobStorage] id in
                try? blobStorage.deleteAll(for: id)
            }
        )
    }

    private func isConsecutiveDuplicate(_ payload: PreparedPayload) throws -> Bool {
        guard
            let latest = try repository.fetchLatest(),
            latest.type == payload.type.rawValue
        else {
            return false
        }

        switch payload {
        case .text(let text), .url(let text):
            return latest.content == text

        case .rtf(let data), .imagePNG(let data):
            return (try? blobStorage.readData(atRelativePath: latest.content)) == data

        case .files(let sourceURLs):
            guard let storedURLs = try? blobStorage.fileURLs(from: latest.content) else {
                return false
            }
            return (try? fileComparator.contentsEqual(sourceURLs, storedURLs)) == true
        }
    }
}

@MainActor
final class PasteboardMonitor: NSObject {
    static let pollingInterval: TimeInterval = 0.4

    private let pasteboard: NSPasteboard
    private let parser: ClipboardParser
    private let processor: PasteboardCaptureProcessor
    private let interval: TimeInterval
    private let sourceBundleIDProvider: () -> String?

    private var lastObservedChangeCount: Int
    private var timer: Timer?
    private var processingTask: Task<Void, Never>?

    var isRunning: Bool { timer != nil }

    init(
        pasteboard: NSPasteboard = .general,
        parser: ClipboardParser = ClipboardParser(),
        processor: PasteboardCaptureProcessor,
        interval: TimeInterval = PasteboardMonitor.pollingInterval,
        sourceBundleIDProvider: @escaping () -> String? = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }
    ) {
        self.pasteboard = pasteboard
        self.parser = parser
        self.processor = processor
        self.interval = interval
        self.sourceBundleIDProvider = sourceBundleIDProvider
        lastObservedChangeCount = pasteboard.changeCount
        super.init()
    }

    func start() {
        guard timer == nil else {
            return
        }

        lastObservedChangeCount = pasteboard.changeCount
        let timer = Timer(
            timeInterval: interval,
            target: self,
            selector: #selector(timerDidFire),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        processingTask?.cancel()
        processingTask = nil
    }

    @discardableResult
    func checkForChanges() -> Bool {
        guard isRunning else {
            return false
        }

        let changeCount = pasteboard.changeCount
        guard changeCount != lastObservedChangeCount else {
            return false
        }
        lastObservedChangeCount = changeCount

        guard let item = parser.parse(pasteboard) else {
            return false
        }
        let sourceBundleID = sourceBundleIDProvider()
        let previousTask = processingTask
        processingTask = Task { [processor] in
            await previousTask?.value
            guard !Task.isCancelled else {
                return
            }
            do {
                _ = try await processor.process(item, sourceBundleID: sourceBundleID)
            } catch {
                NSLog("KPaste failed to save a clipboard item: %@", String(describing: error))
            }
        }
        return true
    }

    func waitForPendingProcessing() async {
        await processingTask?.value
    }

    @discardableResult
    func performSelfWrite<T>(
        _ mutation: (NSPasteboard) throws -> T
    ) rethrows -> T {
        defer {
            lastObservedChangeCount = pasteboard.changeCount
        }
        return try mutation(pasteboard)
    }

    func suppressCurrentChange() {
        lastObservedChangeCount = pasteboard.changeCount
    }

    @objc private func timerDidFire() {
        _ = checkForChanges()
    }

}
