import Foundation
import GRDB

enum MediaKind: Int, Codable, Sendable, DatabaseValueConvertible {
    case image = 1
    case video = 2
}

/// asset 테이블의 한 행.
struct AssetRecord: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable {
    static let databaseTableName = "asset"

    var id: String
    var mediaType: MediaKind
    var createdAt: Date?
    var lat: Double?
    var lon: Double?
    var gridKey: String?
    var placeID: Int64?
    var isScreenshot: Bool
    var fileSize: Int64
    var pixelWidth: Int
    var pixelHeight: Int
    var duration: Double
    var sharpness: Double?
    var aesthetic: Double?
    var isUtility: Bool?
    var dhash: Int64?
    var textLength: Int
    var analyzedVersion: Int
    var analyzeFailures: Int
}

/// PhotoKit 에서 바로 얻을 수 있는 정보 (분석 전에 저장).
struct AssetMetadata: Equatable, Sendable {
    var id: String
    var mediaType: MediaKind
    var createdAt: Date?
    var lat: Double?
    var lon: Double?
    var isScreenshot: Bool
    var fileSize: Int64
    var pixelWidth: Int
    var pixelHeight: Int
    var duration: Double

    /// 약 1km 격자. 같은 격자는 지명 조회를 한 번만 한다.
    var gridKey: String? {
        guard let lat, let lon else { return nil }
        return String(format: "%.2f,%.2f", lat, lon)
    }
}

struct LabelScore: Equatable, Sendable {
    var keyword: String
    var confidence: Double
}

/// 사진 1장의 분석 결과.
struct AnalysisResult: Equatable, Sendable {
    var labels: [LabelScore]
    var ocrText: String?
    var sharpness: Double
    var aesthetic: Double?
    var isUtility: Bool?
    var dhash: UInt64
}

/// 역지오코딩 결과.
struct PlaceInfo: Equatable, Sendable {
    var country: String?
    var admin: String?
    var locality: String?
    var subLocality: String?
    var name: String?

    static let empty = PlaceInfo()

    /// 검색용: 모든 필드를 공백 없이 소문자로 이어 붙인다.
    var searchText: String {
        [country, admin, locality, subLocality, name]
            .compactMap { $0 }
            .joined(separator: "|")
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }

    /// 화면 표시용 짧은 이름. 예) "제주시 애월읍"
    var displayName: String? {
        let parts = [locality ?? admin, subLocality].compactMap { $0 }
        return parts.isEmpty ? (name ?? country) : parts.joined(separator: " ")
    }
}

struct PlaceTask: Equatable, Sendable {
    var gridKey: String
    var lat: Double
    var lon: Double
}

struct AnalysisProgress: Equatable, Sendable {
    var analyzed: Int
    var total: Int
    var fraction: Double { total == 0 ? 1 : Double(analyzed) / Double(total) }
    var isComplete: Bool { analyzed >= total }
}
