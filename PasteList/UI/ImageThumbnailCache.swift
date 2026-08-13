import CoreGraphics
import Foundation
import ImageIO

actor ImageThumbnailCache {
    private let blobStorage: BlobStorage
    private let maximumEntryCount: Int
    private var images: [Int64: CGImage] = [:]
    private var accessOrder: [Int64] = []

    init(blobStorage: BlobStorage, maximumEntryCount: Int = 100) {
        self.blobStorage = blobStorage
        self.maximumEntryCount = max(1, maximumEntryCount)
    }

    func thumbnail(for clipID: Int64, maximumPixelSize: Int = 72) throws -> CGImage {
        if let cached = images[clipID] {
            markRecentlyUsed(clipID)
            return cached
        }

        let data = try blobStorage.readImageData(for: clipID)
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(1, maximumPixelSize),
                    kCGImageSourceShouldCacheImmediately: true,
                ] as CFDictionary
            )
        else {
            throw BlobStorage.StorageError.imageEncodingFailed
        }

        images[clipID] = image
        markRecentlyUsed(clipID)
        evictIfNeeded()
        return image
    }

    func remove(for clipID: Int64) {
        images[clipID] = nil
        accessOrder.removeAll { $0 == clipID }
    }

    private func markRecentlyUsed(_ clipID: Int64) {
        accessOrder.removeAll { $0 == clipID }
        accessOrder.append(clipID)
    }

    private func evictIfNeeded() {
        while accessOrder.count > maximumEntryCount {
            let oldestID = accessOrder.removeFirst()
            images[oldestID] = nil
        }
    }
}
