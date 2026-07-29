import AppKit
import Foundation

final class BlobStorage: @unchecked Sendable {
    enum StorageError: Error {
        case destinationAlreadyExists(URL)
        case duplicateFileName(String)
        case emptyFileSelection
        case imageEncodingFailed
        case invalidClipID(Int64)
        case invalidFileManifest
        case invalidRelativePath(String)
        case missingBlob(URL)
        case sourceDoesNotExist(URL)
    }

    private let blobsDirectory: URL
    private let fileManager: FileManager

    init(paths: AppPaths, fileManager: FileManager = .default) throws {
        blobsDirectory = paths.blobsDirectory.standardizedFileURL
        self.fileManager = fileManager
        try fileManager.createDirectory(
            at: blobsDirectory,
            withIntermediateDirectories: true
        )
    }

    func saveRTF(_ data: Data, for clipID: Int64) throws -> String {
        try saveData(data, as: "\(validated(clipID)).rtf", clipID: clipID)
    }

    func readRTF(for clipID: Int64) throws -> Data {
        try readData(atRelativePath: "\(validated(clipID)).rtf")
    }

    func saveImage(_ image: NSImage, for clipID: Int64) throws -> String {
        try savePNGData(normalizedPNGData(from: image), for: clipID)
    }

    func normalizedPNGData(from imageData: Data) throws -> Data {
        guard let image = NSImage(data: imageData) else {
            throw StorageError.imageEncodingFailed
        }
        return try normalizedPNGData(from: image)
    }

    func savePNGData(_ pngData: Data, for clipID: Int64) throws -> String {
        try saveData(pngData, as: "\(validated(clipID)).png", clipID: clipID)
    }

    private func normalizedPNGData(from image: NSImage) throws -> Data {
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw StorageError.imageEncodingFailed
        }
        return pngData
    }

    func readImageData(for clipID: Int64) throws -> Data {
        try readData(atRelativePath: "\(validated(clipID)).png")
    }

    func readImage(for clipID: Int64) throws -> NSImage {
        let data = try readImageData(for: clipID)
        guard let image = NSImage(data: data) else {
            throw StorageError.imageEncodingFailed
        }
        return image
    }

    func saveFiles(at sourceURLs: [URL], for clipID: Int64) throws -> String {
        let clipID = try validated(clipID)
        guard !sourceURLs.isEmpty else {
            throw StorageError.emptyFileSelection
        }

        var names = Set<String>()
        for sourceURL in sourceURLs {
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw StorageError.sourceDoesNotExist(sourceURL)
            }

            let name = sourceURL.lastPathComponent
            guard !name.isEmpty else {
                throw StorageError.invalidRelativePath(name)
            }
            guard names.insert(name).inserted else {
                throw StorageError.duplicateFileName(name)
            }
        }

        let directoryName = String(clipID)
        let relativePaths = sourceURLs.map { "\(directoryName)/\($0.lastPathComponent)" }
        let manifestData = try JSONEncoder().encode(relativePaths)
        guard let manifest = String(data: manifestData, encoding: .utf8) else {
            throw StorageError.invalidFileManifest
        }

        let destination = blobsDirectory.appendingPathComponent(directoryName, isDirectory: true)
        try ensureDestinationIsAvailable(destination)

        let stagingDirectory = stagingURL(for: clipID, isDirectory: true)
        defer {
            try? fileManager.removeItem(at: stagingDirectory)
        }

        try fileManager.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: false
        )
        for sourceURL in sourceURLs {
            try fileManager.copyItem(
                at: sourceURL,
                to: stagingDirectory.appendingPathComponent(
                    sourceURL.lastPathComponent,
                    isDirectory: sourceURL.hasDirectoryPath
                )
            )
        }
        try fileManager.moveItem(at: stagingDirectory, to: destination)

        return manifest
    }

    func fileURLs(from manifest: String) throws -> [URL] {
        guard
            let data = manifest.data(using: .utf8),
            let relativePaths = try? JSONDecoder().decode([String].self, from: data),
            !relativePaths.isEmpty
        else {
            throw StorageError.invalidFileManifest
        }

        return try relativePaths.map { relativePath in
            let url = try url(forRelativePath: relativePath)
            guard fileManager.fileExists(atPath: url.path) else {
                throw StorageError.missingBlob(url)
            }
            return url
        }
    }

    func dragURLs(for clip: ClipRecord) throws -> [URL] {
        switch ClipContentType(rawValue: clip.type) {
        case .image:
            let url = try url(forRelativePath: clip.content)
            guard fileManager.fileExists(atPath: url.path) else {
                throw StorageError.missingBlob(url)
            }
            return [url]
        case .file:
            return try fileURLs(from: clip.content)
        case .text, .rtf, .url, nil:
            return []
        }
    }

    func readData(atRelativePath relativePath: String) throws -> Data {
        let url = try url(forRelativePath: relativePath)
        guard fileManager.fileExists(atPath: url.path) else {
            throw StorageError.missingBlob(url)
        }
        return try Data(contentsOf: url)
    }

    func deleteAll(for clipID: Int64) throws {
        let clipID = try validated(clipID)
        let names = ["\(clipID).rtf", "\(clipID).png", "\(clipID)"]

        for name in names {
            let url = blobsDirectory.appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }

        let stagingPrefix = ".staging-\(clipID)-"
        let entries = try fileManager.contentsOfDirectory(
            at: blobsDirectory,
            includingPropertiesForKeys: nil
        )
        for entry in entries where entry.lastPathComponent.hasPrefix(stagingPrefix) {
            try fileManager.removeItem(at: entry)
        }
    }

    func deleteAll(for clip: ClipRecord) throws {
        guard let clipID = clip.id else {
            return
        }
        try deleteAll(for: clipID)
    }

    func deleteOrphanedData(
        referencedBy clips: [ClipRecord],
        olderThan cutoff: Date
    ) throws {
        let referencedNames = Set(clips.compactMap { clip -> String? in
            guard let id = clip.id else {
                return nil
            }
            switch ClipContentType(rawValue: clip.type) {
            case .rtf: return "\(id).rtf"
            case .image: return "\(id).png"
            case .file: return String(id)
            case .text, .url, nil: return nil
            }
        })

        let entries = try fileManager.contentsOfDirectory(
            at: blobsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey]
        )
        for entry in entries {
            let name = entry.lastPathComponent
            let values = try entry.resourceValues(
                forKeys: [.contentModificationDateKey, .isDirectoryKey]
            )
            guard let modifiedAt = values.contentModificationDate, modifiedAt < cutoff else {
                continue
            }

            if name.hasPrefix(".staging-") {
                try fileManager.removeItem(at: entry)
                continue
            }

            guard isManagedBlobName(name, isDirectory: values.isDirectory == true) else {
                continue
            }
            if !referencedNames.contains(name) {
                try fileManager.removeItem(at: entry)
            }
        }
    }

    private func saveData(
        _ data: Data,
        as relativePath: String,
        clipID: Int64
    ) throws -> String {
        let clipID = try validated(clipID)
        let destination = try url(forRelativePath: relativePath)
        try ensureDestinationIsAvailable(destination)

        let stagingFile = stagingURL(for: clipID, isDirectory: false)
        defer {
            try? fileManager.removeItem(at: stagingFile)
        }

        try data.write(to: stagingFile, options: .atomic)
        try fileManager.moveItem(at: stagingFile, to: destination)
        return relativePath
    }

    private func ensureDestinationIsAvailable(_ destination: URL) throws {
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw StorageError.destinationAlreadyExists(destination)
        }
    }

    private func isManagedBlobName(_ name: String, isDirectory: Bool) -> Bool {
        if isDirectory {
            return Int64(name).map { $0 > 0 } == true
        }

        let extensionName = URL(fileURLWithPath: name).pathExtension.lowercased()
        guard extensionName == "rtf" || extensionName == "png" else {
            return false
        }
        let stem = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        return Int64(stem).map { $0 > 0 } == true
    }

    private func stagingURL(for clipID: Int64, isDirectory: Bool) -> URL {
        blobsDirectory.appendingPathComponent(
            ".staging-\(clipID)-\(UUID().uuidString)",
            isDirectory: isDirectory
        )
    }

    private func validated(_ clipID: Int64) throws -> Int64 {
        guard clipID > 0 else {
            throw StorageError.invalidClipID(clipID)
        }
        return clipID
    }

    private func url(forRelativePath relativePath: String) throws -> URL {
        guard
            !relativePath.isEmpty,
            !NSString(string: relativePath).isAbsolutePath
        else {
            throw StorageError.invalidRelativePath(relativePath)
        }

        let url = blobsDirectory
            .appendingPathComponent(relativePath)
            .standardizedFileURL
        let rootPath = blobsDirectory.path
        guard url.path.hasPrefix(rootPath + "/") else {
            throw StorageError.invalidRelativePath(relativePath)
        }
        return url
    }
}
