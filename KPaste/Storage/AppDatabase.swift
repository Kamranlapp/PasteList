import GRDB

final class AppDatabase {
    let databasePool: DatabasePool

    init(paths: AppPaths) throws {
        databasePool = try DatabasePool(path: paths.databaseURL.path)
        try Self.migrator.migrate(databasePool)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("createClips") { database in
            try database.create(table: ClipRecord.databaseTableName) { table in
                table.autoIncrementedPrimaryKey(ClipRecord.Columns.id.rawValue)
                table.column(ClipRecord.Columns.type.rawValue, .text).notNull()
                table.column(ClipRecord.Columns.content.rawValue, .text).notNull()
                table.column(ClipRecord.Columns.previewText.rawValue, .text).notNull()
                table.column(ClipRecord.Columns.createdAt.rawValue, .datetime).notNull()
                table.column(ClipRecord.Columns.pinned.rawValue, .boolean)
                    .notNull()
                    .defaults(to: false)
                table.column(ClipRecord.Columns.appBundleID.rawValue, .text)
            }

            try database.execute(
                sql: "CREATE INDEX clips_created_at_desc ON clips(created_at DESC)"
            )
            try database.execute(
                sql: "CREATE INDEX clips_pinned_created_at_desc ON clips(pinned, created_at DESC)"
            )
        }

        return migrator
    }
}
