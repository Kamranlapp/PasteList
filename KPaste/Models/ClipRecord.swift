import Foundation
import GRDB

struct ClipRecord: Codable, Equatable, FetchableRecord, Identifiable, MutablePersistableRecord, Sendable {
    static let databaseTableName = "clips"

    var id: Int64?
    var type: String
    var content: String
    var previewText: String
    var createdAt: Date
    var pinned: Bool
    var appBundleID: String?

    init(
        id: Int64? = nil,
        type: String,
        content: String,
        previewText: String,
        createdAt: Date,
        pinned: Bool = false,
        appBundleID: String? = nil
    ) {
        self.id = id
        self.type = type
        self.content = content
        self.previewText = previewText
        self.createdAt = createdAt
        self.pinned = pinned
        self.appBundleID = appBundleID
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    enum Columns: String, ColumnExpression {
        case id
        case type
        case content
        case previewText = "preview_text"
        case createdAt = "created_at"
        case pinned
        case appBundleID = "app_bundle_id"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case content
        case previewText = "preview_text"
        case createdAt = "created_at"
        case pinned
        case appBundleID = "app_bundle_id"
    }
}
