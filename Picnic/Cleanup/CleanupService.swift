import Foundation

enum CleanupCategory: String, CaseIterable, Identifiable, Sendable {
    case blurry
    case similar
    case screenshot
    case document
    case largeVideo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blurry: return "흐린 사진"
        case .similar: return "비슷한 사진"
        case .screenshot: return "스크린샷"
        case .document: return "영수증·문서"
        case .largeVideo: return "큰 동영상"
        }
    }

    var subtitle: String {
        switch self {
        case .blurry: return "초점이 나가거나 흔들린 사진이에요"
        case .similar: return "연속으로 찍은 비슷한 사진이에요"
        case .screenshot: return "화면을 캡처한 사진이에요"
        case .document: return "영수증, 문서, 메모를 찍은 사진이에요"
        case .largeVideo: return "용량을 많이 차지하는 동영상이에요"
        }
    }

    var symbol: String {
        switch self {
        case .blurry: return "camera.aperture"
        case .similar: return "square.on.square.fill"
        case .screenshot: return "iphone.gen3"
        case .document: return "doc.text.fill"
        case .largeVideo: return "play.rectangle.fill"
        }
    }
}

struct CleanupGroup: Identifiable, Equatable, Sendable {
    var items: [AssetSummary]
    /// 남기기를 추천하는 사진 (점수가 가장 높은 사진)
    var bestID: String
    var id: String { bestID }
}

struct CleanupResult: Equatable, Sendable {
    var category: CleanupCategory
    var items: [AssetSummary]
    /// 비슷한 사진 탭에서만 채워진다
    var groups: [CleanupGroup]
    var defaultSelected: Set<String>

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.fileSize } }

    func bytes(of ids: Set<String>) -> Int64 {
        items.reduce(0) { ids.contains($1.id) ? $0 + $1.fileSize : $0 }
    }
}

/// 정리 후보를 계산한다. 정밀 비교(`refine`)는 바깥에서 주입한다.
final class CleanupService: Sendable {
    /// 두 사진이 비슷한지 판정. 판정할 수 없으면 nil.
    typealias Refine = @Sendable (String, String) async -> Bool?

    let store: AssetStore
    let blurPercentile: Double
    let blurAbsoluteMax: Double
    let largeVideoBytes: Int64

    init(
        store: AssetStore, blurPercentile: Double = 0.05, blurAbsoluteMax: Double = 150,
        largeVideoBytes: Int64 = 20 * 1024 * 1024
    ) {
        self.store = store
        self.blurPercentile = blurPercentile
        self.blurAbsoluteMax = blurAbsoluteMax
        self.largeVideoBytes = largeVideoBytes
    }

    /// 흐림 기준: 라이브러리 하위 `percentile` 값과 절대 상한 중 작은 값.
    /// 분석된 사진이 100장 미만이면 상한의 절반만 쓴다.
    static func blurThreshold(sortedValues: [Double], percentile: Double, absoluteMax: Double) -> Double {
        guard sortedValues.count >= 100 else { return absoluteMax / 2 }
        let index = min(sortedValues.count - 1, Int(Double(sortedValues.count) * percentile))
        return min(sortedValues[index], absoluteMax)
    }

    func candidates(_ category: CleanupCategory, refine: Refine? = nil) async throws -> CleanupResult {
        switch category {
        case .blurry:
            let threshold = Self.blurThreshold(
                sortedValues: try store.sharpnessValues(), percentile: blurPercentile,
                absoluteMax: blurAbsoluteMax)
            let items = try store.blurrySummaries(threshold: threshold)
            return CleanupResult(
                category: category, items: items, groups: [], defaultSelected: Set(items.map(\.id)))
        case .screenshot:
            return CleanupResult(category: category, items: try store.screenshotSummaries(), groups: [], defaultSelected: [])
        case .document:
            return CleanupResult(category: category, items: try store.documentSummaries(), groups: [], defaultSelected: [])
        case .largeVideo:
            return CleanupResult(
                category: category, items: try store.largeVideoSummaries(minBytes: largeVideoBytes), groups: [],
                defaultSelected: [])
        case .similar:
            return try await similar(refine: refine)
        }
    }

    private func similar(refine: Refine?) async throws -> CleanupResult {
        let items = try store.similarityItems()
        let candidates = SimilarGrouper.candidatePairs(items)
        var links = candidates.sure
        for pair in candidates.maybe {
            if Task.isCancelled { break }
            if let cached = try store.cachedSimilarity(pair.a, pair.b) {
                if cached { links.append(pair) }
                continue
            }
            guard let refine, let similar = await refine(pair.a, pair.b) else { continue }
            try store.saveSimilarity(pair.a, pair.b, similar: similar)
            if similar { links.append(pair) }
        }
        let grouped = SimilarGrouper.groups(items, links: links)
        let summaries = try store.summaries(ids: grouped.flatMap { $0.map(\.id) })
        let byID = Dictionary(uniqueKeysWithValues: summaries.map { ($0.id, $0) })

        var groups: [CleanupGroup] = []
        var selected: Set<String> = []
        for group in grouped {
            let members = group.compactMap { byID[$0.id] }
            guard members.count >= 2, let best = group.first else { continue }
            groups.append(CleanupGroup(items: members, bestID: best.id))
            for member in members where member.id != best.id { selected.insert(member.id) }
        }
        return CleanupResult(
            category: .similar, items: groups.flatMap(\.items), groups: groups, defaultSelected: selected)
    }

    /// 홈 화면 카드용 요약. 비슷한 사진은 정밀 비교 없이 확실한 것과 이미 판정된 것만 센다.
    func overview() async throws -> [CleanupCategory: CleanupResult] {
        var result: [CleanupCategory: CleanupResult] = [:]
        for category in CleanupCategory.allCases {
            result[category] = try await candidates(category, refine: nil)
        }
        return result
    }
}
