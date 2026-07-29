import Foundation
import GRDB

struct ClipHistorySnapshot: Equatable, Sendable {
    let pinned: [ClipRecord]
    let history: [ClipRecord]
}

typealias ClipHistoryValueObservation = ValueObservation<
    ValueReducers.RemoveDuplicates<ValueReducers.Fetch<ClipHistorySnapshot>>
>

final class ClipRepository: Sendable {
    enum RepositoryError: Error {
        case missingInsertedID
    }

    private let databasePool: DatabasePool

    init(database: AppDatabase) {
        databasePool = database.databasePool
    }

    @discardableResult
    func insert(_ clip: ClipRecord) throws -> ClipRecord {
        try databasePool.write { database in
            var insertedClip = clip
            try insertedClip.insert(database)
            return insertedClip
        }
    }

    @discardableResult
    func insert(
        _ clip: ClipRecord,
        preparingContent: @Sendable (Int64) throws -> String,
        rollbackContent: @Sendable (Int64) -> Void
    ) throws -> ClipRecord {
        try databasePool.write { database in
            var insertedClip = clip
            try insertedClip.insert(database)
            guard let id = insertedClip.id else {
                throw RepositoryError.missingInsertedID
            }

            do {
                insertedClip.content = try preparingContent(id)
                try insertedClip.update(database)
                return insertedClip
            } catch {
                rollbackContent(id)
                throw error
            }
        }
    }

    func fetch(id: Int64) throws -> ClipRecord? {
        try databasePool.read { database in
            try ClipRecord.fetchOne(database, key: id)
        }
    }

    func fetchPinned(matching query: String = "") throws -> [ClipRecord] {
        try databasePool.read { database in
            try Self.fetchClips(database, pinned: true, matching: query)
        }
    }

    func fetchHistory(matching query: String = "") throws -> [ClipRecord] {
        try databasePool.read { database in
            try Self.fetchClips(database, pinned: false, matching: query)
        }
    }

    func search(previewText query: String) throws -> [ClipRecord] {
        try databasePool.read { database in
            try Self.fetchClips(database, pinned: nil, matching: query)
        }
    }

    @discardableResult
    func setPinned(_ pinned: Bool, for id: Int64) throws -> Bool {
        try databasePool.write { database in
            try ClipRecord
                .filter(key: id)
                .updateAll(database, ClipRecord.Columns.pinned.set(to: pinned)) > 0
        }
    }

    @discardableResult
    func delete(id: Int64) throws -> Bool {
        try databasePool.write { database in
            try ClipRecord.deleteOne(database, key: id)
        }
    }

    @discardableResult
    func deleteAll() throws -> [Int64] {
        try databasePool.write { database in
            let ids = try ClipRecord.fetchAll(database).compactMap(\.id)
            _ = try ClipRecord.deleteAll(database)
            return ids
        }
    }

    @discardableResult
    func markUsed(id: Int64, at date: Date = Date()) throws -> Bool {
        try databasePool.write { database in
            try ClipRecord
                .filter(key: id)
                .updateAll(database, ClipRecord.Columns.createdAt.set(to: date)) > 0
        }
    }

    func markUsedPreservingOrder(ids: [Int64], at date: Date = Date()) throws {
        try databasePool.write { database in
            for (index, id) in ids.enumerated() {
                let orderedDate = date.addingTimeInterval(-Double(index) * 0.001)
                try ClipRecord
                    .filter(key: id)
                    .updateAll(
                        database,
                        ClipRecord.Columns.createdAt.set(to: orderedDate)
                    )
            }
        }
    }

    func fetchLatest() throws -> ClipRecord? {
        try databasePool.read { database in
            try ClipRecord
                .order(Self.historyOrdering)
                .fetchOne(database)
        }
    }

    func fetchAll() throws -> [ClipRecord] {
        try databasePool.read { database in
            try ClipRecord.fetchAll(database)
        }
    }

    func fetchRetentionCandidates(
        olderThan cutoff: Date,
        maximumUnpinnedCount: Int
    ) throws -> [ClipRecord] {
        try databasePool.read { database in
            let clips = try ClipRecord
                .filter(Column(ClipRecord.Columns.pinned.rawValue) == false)
                .order(Self.historyOrdering)
                .fetchAll(database)
            let maximumCount = max(0, maximumUnpinnedCount)
            return clips.enumerated().compactMap { index, clip in
                clip.createdAt < cutoff || index >= maximumCount ? clip : nil
            }
        }
    }

    func historyObservation(matching query: String = "") -> ClipHistoryValueObservation {
        ValueObservation
            .tracking { database in
                try Self.fetchSnapshot(database, matching: query)
            }
            .removeDuplicates()
    }

    @MainActor
    func observeHistory(
        matching query: String = "",
        onError: @escaping @MainActor (Error) -> Void,
        onChange: @escaping @MainActor (ClipHistorySnapshot) -> Void
    ) -> AnyDatabaseCancellable {
        historyObservation(matching: query).start(
            in: databasePool,
            onError: onError,
            onChange: onChange
        )
    }

    private static let historyOrdering = [
        Column(ClipRecord.Columns.createdAt.rawValue).desc,
        Column(ClipRecord.Columns.id.rawValue).desc,
    ]

    private static func fetchSnapshot(
        _ database: Database,
        matching query: String
    ) throws -> ClipHistorySnapshot {
        ClipHistorySnapshot(
            pinned: try fetchClips(database, pinned: true, matching: query),
            history: try fetchClips(database, pinned: false, matching: query)
        )
    }

    private static func fetchClips(
        _ database: Database,
        pinned: Bool?,
        matching query: String
    ) throws -> [ClipRecord] {
        var request = ClipRecord.all()

        if let pinned {
            request = request.filter(
                Column(ClipRecord.Columns.pinned.rawValue) == pinned
            )
        }

        if !query.isEmpty {
            request = request.filter(
                Column(ClipRecord.Columns.previewText.rawValue)
                    .localizedLowercased
                    .like(literalContainsPattern(for: query), escape: "\\")
            )
        }

        return try request
            .order(historyOrdering)
            .fetchAll(database)
    }

    private static func literalContainsPattern(for query: String) -> String {
        let escapedQuery = query.localizedLowercase
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "%\(escapedQuery)%"
    }
}
