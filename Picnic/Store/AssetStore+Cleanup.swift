import Foundation
import GRDB

extension AssetStore {
    private static let notExcluded = "id NOT IN (SELECT assetId FROM exclusion)"

    /// 문서·영수증으로 볼 Vision 라벨.
    static let documentLabels = ["document", "receipt", "handwriting", "printed_page", "sticky_note", "whiteboard"]

    /// 분석된 일반 사진의 선명도 (오름차순). 흐림 기준을 정하는 데 쓴다.
    func sharpnessValues() throws -> [Double] {
        try writer.read { db in
            try Double.fetchAll(
                db,
                sql: """
                    SELECT sharpness FROM asset
                    WHERE mediaType = 1 AND isScreenshot = 0 AND sharpness IS NOT NULL
                      AND COALESCE(isUtility, 0) = 0
                    ORDER BY sharpness ASC
                    """)
        }
    }

    func blurrySummaries(threshold: Double) throws -> [AssetSummary] {
        try fetchSummaries(
            where: """
                mediaType = 1 AND isScreenshot = 0 AND sharpness IS NOT NULL AND sharpness <= ?
                  AND COALESCE(isUtility, 0) = 0
                """,
            arguments: [threshold], order: "sharpness ASC")
    }

    func screenshotSummaries() throws -> [AssetSummary] {
        try fetchSummaries(where: "isScreenshot = 1", arguments: [], order: "createdAt DESC")
    }

    /// 영수증·문서: 문서 라벨이 붙었거나, 글자가 아주 많거나, 애플이 '유틸리티 이미지'로 본 사진 중 글자가 있는 것.
    func documentSummaries(minTextLength: Int = 30, heavyTextLength: Int = 80) throws -> [AssetSummary] {
        let labels = Self.documentLabels.map { "'\($0)'" }.joined(separator: ",")
        return try fetchSummaries(
            where: """
                mediaType = 1 AND isScreenshot = 0
                  AND (id IN (SELECT assetId FROM label WHERE keyword IN (\(labels)) AND confidence >= 0.5)
                       OR textLength >= ?
                       OR (isUtility = 1 AND textLength >= ?))
                """,
            arguments: [heavyTextLength, minTextLength], order: "createdAt DESC")
    }

    func largeVideoSummaries(minBytes: Int64) throws -> [AssetSummary] {
        try fetchSummaries(
            where: "mediaType = 2 AND fileSize >= ?", arguments: [minBytes], order: "fileSize DESC")
    }

    /// 비슷한 사진 판별용 항목 (스크린샷·제외 사진 빼고).
    func similarityItems() throws -> [SimilarGrouper.Item] {
        try writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, createdAt, dhash, sharpness, aesthetic FROM asset
                    WHERE mediaType = 1 AND isScreenshot = 0 AND dhash IS NOT NULL
                      AND createdAt IS NOT NULL AND \(Self.notExcluded)
                    ORDER BY createdAt ASC
                    """
            ).map { row in
                let hash: Int64 = row["dhash"]
                return SimilarGrouper.Item(
                    id: row["id"], createdAt: row["createdAt"], dhash: UInt64(bitPattern: hash),
                    score: SimilarGrouper.score(sharpness: row["sharpness"], aesthetic: row["aesthetic"]))
            }
        }
    }

    func summaries(ids: [String]) throws -> [AssetSummary] {
        guard !ids.isEmpty else { return [] }
        var result: [String: AssetSummary] = [:]
        try writer.read { db in
            for start in stride(from: 0, to: ids.count, by: 500) {
                let chunk = Array(ids[start..<min(start + 500, ids.count)])
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT id, createdAt, mediaType, fileSize FROM asset
                        WHERE id IN (\(Array(repeating: "?", count: chunk.count).joined(separator: ",")))
                        """,
                    arguments: StatementArguments(chunk))
                for row in rows {
                    let summary = Self.summary(row)
                    result[summary.id] = summary
                }
            }
        }
        return ids.compactMap { result[$0] }
    }

    private func fetchSummaries(where clause: String, arguments: StatementArguments, order: String) throws
        -> [AssetSummary]
    {
        try writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, createdAt, mediaType, fileSize FROM asset
                    WHERE (\(clause)) AND \(Self.notExcluded)
                    ORDER BY \(order)
                    """,
                arguments: arguments
            ).map(Self.summary)
        }
    }
}
