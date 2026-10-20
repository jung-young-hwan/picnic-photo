import Foundation
import GRDB

/// 검색·정리 화면에 필요한 조회.
struct AssetSummary: Equatable, Sendable, Identifiable {
    var id: String
    var createdAt: Date?
    var mediaType: MediaKind
    var fileSize: Int64
}

struct AssetFilter: Equatable, Sendable {
    var intervals: [DateInterval] = []
    var months: [Set<Int>] = []
    var flags: [SearchFlag] = []
}

extension AssetStore {
    private static func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ",")
    }

    /// LIKE 패턴 특수문자를 이스케이프한다.
    static func likePattern(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "%\(escaped)%"
    }

    func ids(withLabels keywords: Set<String>, minConfidence: Double = 0.3) throws -> Set<String> {
        guard !keywords.isEmpty else { return [] }
        let list = Array(keywords)
        return try writer.read { db in
            Set(
                try String.fetchAll(
                    db,
                    sql: """
                        SELECT DISTINCT assetId FROM label
                        WHERE keyword IN (\(Self.placeholders(list.count))) AND confidence >= ?
                        """,
                    arguments: StatementArguments(list) + [minConfidence]))
        }
    }

    /// 사진 속 글자에 단어가 들어 있는 사진. 띄어쓰기는 무시한다.
    func ids(withTextContaining word: String) throws -> Set<String> {
        let pattern = Self.likePattern(word.lowercased().replacingOccurrences(of: " ", with: ""))
        return try writer.read { db in
            Set(
                try String.fetchAll(
                    db,
                    sql: "SELECT assetId FROM ocr WHERE REPLACE(text, ' ', '') LIKE ? ESCAPE '\\'",
                    arguments: [pattern]))
        }
    }

    func ids(withPlaceContaining word: String) throws -> Set<String> {
        let pattern = Self.likePattern(word.lowercased().replacingOccurrences(of: " ", with: ""))
        return try writer.read { db in
            Set(
                try String.fetchAll(
                    db,
                    sql: """
                        SELECT a.id FROM asset a JOIN place p ON p.id = a.placeID
                        WHERE p.searchText LIKE ? ESCAPE '\\'
                        """,
                    arguments: [pattern]))
        }
    }

    /// 날짜·종류 조건에 맞는 에셋 (최신순).
    func summaries(matching filter: AssetFilter, limit: Int? = nil) throws -> [AssetSummary] {
        var clauses: [String] = []
        var arguments = StatementArguments()
        for interval in filter.intervals {
            clauses.append("createdAt >= ? AND createdAt < ?")
            arguments += [interval.start, interval.end]
        }
        for months in filter.months where !months.isEmpty {
            clauses.append(
                "CAST(strftime('%m', createdAt, 'localtime') AS INTEGER) IN (\(Self.placeholders(months.count)))")
            arguments += StatementArguments(Array(months))
        }
        for flag in filter.flags {
            switch flag {
            case .screenshot: clauses.append("isScreenshot = 1")
            case .video: clauses.append("mediaType = 2")
            }
        }
        var sql = "SELECT id, createdAt, mediaType, fileSize FROM asset"
        if !clauses.isEmpty {
            sql += " WHERE " + clauses.map { "(\($0))" }.joined(separator: " AND ")
        }
        sql += " ORDER BY createdAt DESC"
        if let limit {
            sql += " LIMIT ?"
            arguments += [limit]
        }
        let finalSQL = sql
        let finalArguments = arguments
        return try writer.read { db in
            try Row.fetchAll(db, sql: finalSQL, arguments: finalArguments).map(Self.summary)
        }
    }

    static func summary(_ row: Row) -> AssetSummary {
        AssetSummary(
            id: row["id"], createdAt: row["createdAt"],
            mediaType: MediaKind(rawValue: row["mediaType"]) ?? .image,
            fileSize: row["fileSize"])
    }
}
