import Foundation
import GRDB

/// 데이터베이스 생성과 스키마 마이그레이션.
enum AppDatabase {
    /// 앱 지원 폴더의 색인 파일 위치.
    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("picnic-index.sqlite")
    }

    static func openFile(at url: URL = fileURL) throws -> DatabasePool {
        let pool = try DatabasePool(path: url.path)
        try migrator.migrate(pool)
        return pool
    }

    static func openInMemory() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try migrator.migrate(queue)
        return queue
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "asset") { t in
                t.primaryKey("id", .text)
                t.column("mediaType", .integer).notNull()
                t.column("createdAt", .datetime)
                t.column("lat", .double)
                t.column("lon", .double)
                t.column("gridKey", .text)
                t.column("placeID", .integer)
                t.column("isScreenshot", .boolean).notNull().defaults(to: false)
                t.column("fileSize", .integer).notNull().defaults(to: 0)
                t.column("pixelWidth", .integer).notNull().defaults(to: 0)
                t.column("pixelHeight", .integer).notNull().defaults(to: 0)
                t.column("duration", .double).notNull().defaults(to: 0)
                t.column("sharpness", .double)
                t.column("aesthetic", .double)
                t.column("isUtility", .boolean)
                t.column("dhash", .integer)
                t.column("textLength", .integer).notNull().defaults(to: 0)
                t.column("analyzedVersion", .integer).notNull().defaults(to: 0)
                t.column("analyzeFailures", .integer).notNull().defaults(to: 0)
            }
            try db.create(index: "asset_createdAt", on: "asset", columns: ["createdAt"])
            try db.create(index: "asset_pending", on: "asset", columns: ["mediaType", "analyzedVersion"])
            try db.create(index: "asset_grid", on: "asset", columns: ["gridKey"])
            try db.create(index: "asset_place", on: "asset", columns: ["placeID"])

            try db.create(table: "label") { t in
                t.column("assetId", .text).notNull().references("asset", onDelete: .cascade)
                t.column("keyword", .text).notNull()
                t.column("confidence", .double).notNull()
            }
            try db.create(index: "label_keyword", on: "label", columns: ["keyword"])
            try db.create(index: "label_asset", on: "label", columns: ["assetId"])

            try db.create(table: "ocr") { t in
                t.primaryKey("assetId", .text).references("asset", onDelete: .cascade)
                t.column("text", .text).notNull()
            }

            try db.create(table: "place") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("gridKey", .text).notNull().unique()
                t.column("country", .text)
                t.column("admin", .text)
                t.column("locality", .text)
                t.column("subLocality", .text)
                t.column("name", .text)
                t.column("searchText", .text).notNull()
            }

            try db.create(table: "exclusion") { t in
                t.primaryKey("assetId", .text)
            }

            try db.create(table: "pairCache") { t in
                t.column("a", .text).notNull()
                t.column("b", .text).notNull()
                t.column("similar", .boolean).notNull()
                t.primaryKey(["a", "b"])
            }
        }
        return migrator
    }
}
