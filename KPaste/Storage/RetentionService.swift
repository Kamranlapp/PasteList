import Foundation

enum RetentionPolicy {
    static let maximumAge: TimeInterval = 7 * 24 * 60 * 60
    static let maximumUnpinnedClips = 200
    static let cleanupInterval: TimeInterval = 60 * 60
    static let orphanGracePeriod: TimeInterval = 60 * 60
}

actor RetentionService {
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

    @discardableResult
    func performCleanup() throws -> Int {
        let currentDate = now()
        let candidates = try repository.fetchRetentionCandidates(
            olderThan: currentDate.addingTimeInterval(-RetentionPolicy.maximumAge),
            maximumUnpinnedCount: RetentionPolicy.maximumUnpinnedClips
        )

        var deletedCount = 0
        for clip in candidates {
            guard let id = clip.id else {
                continue
            }
            if try repository.delete(id: id) {
                deletedCount += 1
                try blobStorage.deleteAll(for: id)
            }
        }

        let remainingClips = try repository.fetchAll()
        try blobStorage.deleteOrphanedData(
            referencedBy: remainingClips,
            olderThan: currentDate.addingTimeInterval(-RetentionPolicy.orphanGracePeriod)
        )
        return deletedCount
    }
}

@MainActor
final class RetentionScheduler: NSObject {
    private let service: RetentionService
    private let interval: TimeInterval
    private var timer: Timer?
    private var cleanupTask: Task<Void, Never>?

    init(
        service: RetentionService,
        interval: TimeInterval = RetentionPolicy.cleanupInterval
    ) {
        self.service = service
        self.interval = interval
    }

    func start() {
        guard timer == nil else {
            return
        }

        performCleanup()
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
        cleanupTask?.cancel()
        cleanupTask = nil
    }

    private func performCleanup() {
        guard cleanupTask == nil else {
            return
        }
        cleanupTask = Task { [weak self, service] in
            defer { self?.cleanupTask = nil }
            do {
                _ = try await service.performCleanup()
            } catch {
                NSLog("KPaste retention cleanup failed: %@", String(describing: error))
            }
        }
    }

    @objc private func timerDidFire() {
        performCleanup()
    }
}
