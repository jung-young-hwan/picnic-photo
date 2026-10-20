import Foundation
import GRDB

/// 색인 저장소. SQL 은 Store 폴더 안에서만 다룬다.
final class AssetStore: @unchecked Sendable {
    let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    static func inMemory() throws -> AssetStore {
        AssetStore(writer: try AppDatabase.openInMemory())
    }

    // MARK: - 메타데이터

    /// 메타데이터를 넣거나 갱신한다. 이미 있는 분석 결과는 유지한다.
    func upsertMetadata(_ items: [AssetMetadata]) throws {
        try writer.write { db in
            let statement = try db.cachedStatement(sql: """
                INSERT INTO asset (id, mediaType, createdAt, lat, lon, gridKey, isScreenshot,
                                   fileSize, pixelWidth, pixelHeight, duration)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    mediaType = excluded.mediaType,
                    createdAt = excluded.createdAt,
                    lat = excluded.lat,
                    lon = excluded.lon,
                    placeID = CASE WHEN asset.gridKey IS excluded.gridKey THEN asset.placeID ELSE NULL END,
                    gridKey = excluded.gridKey,
                    isScreenshot = excluded.isScreenshot,
                    fileSize = CASE WHEN excluded.fileSize > 0 THEN excluded.fileSize ELSE asset.fileSize END,
                    pixelWidth = excluded.pixelWidth,
                    pixelHeight = excluded.pixelHeight,
                    duration = excluded.duration
                """)
            for m in items {
                try statement.execute(arguments: [
                    m.id, m.mediaType.rawValue, m.createdAt, m.lat, m.lon, m.gridKey, m.isScreenshot,
                    m.fileSize, m.pixelWidth, m.pixelHeight, m.duration,
                ])
            }
        }
    }

    /// 파일 크기를 아직 모르는 에셋 ID.
    func idsMissingFileSize(limit: Int) throws -> [String] {
        try writer.read { db in
            try String.fetchAll(
                db, sql: "SELECT id FROM asset WHERE fileSize = 0 ORDER BY createdAt DESC LIMIT ?",
                arguments: [limit])
        }
    }

    func saveFileSizes(_ sizes: [String: Int64]) throws {
        try writer.write { db in
            for (id, size) in sizes {
                try db.execute(sql: "UPDATE asset SET fileSize = ? WHERE id = ?", arguments: [size, id])
            }
        }
    }

    func allIDs() throws -> Set<String> {
        try writer.read { db in Set(try String.fetchAll(db, sql: "SELECT id FROM asset")) }
    }

    /// 라이브러리에서 사라진 에셋을 지운다. 지운 개수를 돌려준다.
    @discardableResult
    func removeAssets(notIn keep: Set<String>) throws -> Int {
        let gone = try allIDs().subtracting(keep)
        try removeAssets(ids: Array(gone))
        return gone.count
    }

    func removeAssets(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        try writer.write { db in
            for start in stride(from: 0, to: ids.count, by: 500) {
                let chunk = Array(ids[start..<min(start + 500, ids.count)])
                _ = try AssetRecord.deleteAll(db, keys: chunk)
            }
        }
    }

    func asset(id: String) throws -> AssetRecord? {
        try writer.read { db in try AssetRecord.fetchOne(db, key: id) }
    }

    func assetCount() throws -> Int {
        try writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM asset") ?? 0 }
    }

    // MARK: - 분석

    func saveAnalysis(id: String, result: AnalysisResult, version: Int) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                    UPDATE asset SET sharpness = ?, aesthetic = ?, isUtility = ?, dhash = ?,
                                     textLength = ?, analyzedVersion = ?
                    WHERE id = ?
                    """,
                arguments: [
                    result.sharpness, result.aesthetic, result.isUtility,
                    Int64(bitPattern: result.dhash), result.ocrText?.count ?? 0, version, id,
                ])
            try db.execute(sql: "DELETE FROM label WHERE assetId = ?", arguments: [id])
            for label in result.labels {
                try db.execute(
                    sql: "INSERT INTO label (assetId, keyword, confidence) VALUES (?, ?, ?)",
                    arguments: [id, label.keyword, label.confidence])
            }
            if let text = result.ocrText, !text.isEmpty {
                try db.execute(
                    sql: "INSERT OR REPLACE INTO ocr (assetId, text) VALUES (?, ?)",
                    arguments: [id, text.lowercased()])
            } else {
                try db.execute(sql: "DELETE FROM ocr WHERE assetId = ?", arguments: [id])
            }
        }
    }

    func markAnalysisFailed(id: String) throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE asset SET analyzeFailures = analyzeFailures + 1 WHERE id = ?",
                arguments: [id])
        }
    }

    /// 아직 분석하지 않은 사진 ID (최신순). 3번 실패한 사진은 건너뛴다.
    func pendingAnalysisIDs(version: Int, limit: Int) throws -> [String] {
        try writer.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT id FROM asset
                    WHERE mediaType = 1 AND analyzedVersion < ? AND analyzeFailures < 3
                    ORDER BY createdAt DESC LIMIT ?
                    """,
                arguments: [version, limit])
        }
    }

    func analysisProgress(version: Int) throws -> AnalysisProgress {
        try writer.read { db in
            let total = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM asset WHERE mediaType = 1") ?? 0
            let done = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM asset
                    WHERE mediaType = 1 AND (analyzedVersion >= ? OR analyzeFailures >= 3)
                    """,
                arguments: [version]) ?? 0
            return AnalysisProgress(analyzed: done, total: total)
        }
    }

    func labels(for id: String) throws -> [LabelScore] {
        try writer.read { db in
            try Row.fetchAll(
                db, sql: "SELECT keyword, confidence FROM label WHERE assetId = ? ORDER BY confidence DESC",
                arguments: [id]
            ).map { LabelScore(keyword: $0["keyword"], confidence: $0["confidence"]) }
        }
    }

    func ocrText(for id: String) throws -> String? {
        try writer.read { db in
            try String.fetchOne(db, sql: "SELECT text FROM ocr WHERE assetId = ?", arguments: [id])
        }
    }

    /// 많이 나온 라벨 (추천 검색어용).
    func topLabels(limit: Int, minConfidence: Double = 0.5) throws -> [String] {
        try writer.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT keyword FROM label WHERE confidence >= ?
                    GROUP BY keyword ORDER BY COUNT(*) DESC LIMIT ?
                    """,
                arguments: [minConfidence, limit])
        }
    }

    // MARK: - 지명

    /// 지명이 아직 없는 격자 (최근 사진이 있는 격자 우선).
    func pendingPlaceTasks(limit: Int) throws -> [PlaceTask] {
        try writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT gridKey, AVG(lat) AS lat, AVG(lon) AS lon FROM asset
                    WHERE gridKey IS NOT NULL AND placeID IS NULL
                    GROUP BY gridKey ORDER BY MAX(createdAt) DESC LIMIT ?
                    """,
                arguments: [limit]
            ).map { PlaceTask(gridKey: $0["gridKey"], lat: $0["lat"], lon: $0["lon"]) }
        }
    }

    func savePlace(gridKey: String, info: PlaceInfo) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO place (gridKey, country, admin, locality, subLocality, name, searchText)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(gridKey) DO UPDATE SET
                        country = excluded.country, admin = excluded.admin, locality = excluded.locality,
                        subLocality = excluded.subLocality, name = excluded.name,
                        searchText = excluded.searchText
                    """,
                arguments: [
                    gridKey, info.country, info.admin, info.locality, info.subLocality, info.name,
                    info.searchText,
                ])
            let placeID = try Int64.fetchOne(
                db, sql: "SELECT id FROM place WHERE gridKey = ?", arguments: [gridKey])
            try db.execute(
                sql: "UPDATE asset SET placeID = ? WHERE gridKey = ?", arguments: [placeID, gridKey])
        }
    }

    func place(forAsset id: String) throws -> PlaceInfo? {
        try writer.read { db in
            guard
                let row = try Row.fetchOne(
                    db,
                    sql: "SELECT p.* FROM place p JOIN asset a ON a.placeID = p.id WHERE a.id = ?",
                    arguments: [id])
            else { return nil }
            return PlaceInfo(
                country: row["country"], admin: row["admin"], locality: row["locality"],
                subLocality: row["subLocality"], name: row["name"])
        }
    }

    /// 사진이 많은 지역 이름 (추천 검색어용).
    func topPlaces(limit: Int) throws -> [String] {
        try writer.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT COALESCE(p.subLocality, p.locality, p.admin) AS n FROM asset a
                    JOIN place p ON p.id = a.placeID
                    WHERE n IS NOT NULL
                    GROUP BY n ORDER BY COUNT(*) DESC LIMIT ?
                    """,
                arguments: [limit])
        }
    }

    // MARK: - 정리 제외

    func exclude(ids: [String]) throws {
        try writer.write { db in
            for id in ids {
                try db.execute(
                    sql: "INSERT OR IGNORE INTO exclusion (assetId) VALUES (?)", arguments: [id])
            }
        }
    }

    func clearExclusions() throws {
        try writer.write { db in try db.execute(sql: "DELETE FROM exclusion") }
    }

    func exclusionCount() throws -> Int {
        try writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exclusion") ?? 0 }
    }

    // MARK: - 비슷한 사진 판정 캐시

    func cachedSimilarity(_ a: String, _ b: String) throws -> Bool? {
        let (x, y) = a < b ? (a, b) : (b, a)
        return try writer.read { db in
            try Bool.fetchOne(
                db, sql: "SELECT similar FROM pairCache WHERE a = ? AND b = ?", arguments: [x, y])
        }
    }

    func saveSimilarity(_ a: String, _ b: String, similar: Bool) throws {
        let (x, y) = a < b ? (a, b) : (b, a)
        try writer.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO pairCache (a, b, similar) VALUES (?, ?, ?)",
                arguments: [x, y, similar])
        }
    }

    // MARK: - 초기화

    func resetAll() throws {
        try writer.write { db in
            for table in ["label", "ocr", "pairCache", "exclusion", "asset", "place"] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
        }
        try writer.vacuum()
    }
}
