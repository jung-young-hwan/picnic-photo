import Foundation

/// 비슷한 사진 묶음을 만드는 순수 로직.
///
/// 1. 촬영 시각이 `window` 이내로 붙어 있는 사진끼리만 비교한다.
/// 2. dHash 거리 ≤ `sureDistance` 이면 바로 같은 묶음.
/// 3. ≤ `maybeDistance` 이면 정밀 비교(Vision 특징 벡터)가 필요한 후보로 돌려준다.
enum SimilarGrouper {
    struct Item: Equatable, Sendable {
        var id: String
        var createdAt: Date
        var dhash: UInt64
        /// 보존 추천 점수 (클수록 좋은 사진)
        var score: Double
    }

    struct Pair: Hashable, Sendable {
        var a: String
        var b: String
    }

    struct Candidates: Equatable, Sendable {
        var sure: [Pair]
        var maybe: [Pair]
    }

    static func candidatePairs(
        _ items: [Item], window: TimeInterval = 180, sureDistance: Int = 3, maybeDistance: Int = 10,
        maxLookahead: Int = 30
    ) -> Candidates {
        let sorted = items.sorted { $0.createdAt < $1.createdAt }
        var sure: [Pair] = []
        var maybe: [Pair] = []
        for i in sorted.indices {
            var j = i + 1
            while j < sorted.count, j - i <= maxLookahead,
                sorted[j].createdAt.timeIntervalSince(sorted[i].createdAt) <= window
            {
                let distance = ImageMath.hamming(sorted[i].dhash, sorted[j].dhash)
                let pair = Pair(a: sorted[i].id, b: sorted[j].id)
                if distance <= sureDistance {
                    sure.append(pair)
                } else if distance <= maybeDistance {
                    maybe.append(pair)
                }
                j += 1
            }
        }
        return Candidates(sure: sure, maybe: maybe)
    }

    /// 연결된 사진끼리 묶는다. 2장 이상인 묶음만, 최신 묶음이 먼저. 묶음 안은 점수 높은 순.
    static func groups(_ items: [Item], links: [Pair]) -> [[Item]] {
        var parent: [String: String] = [:]
        func find(_ x: String) -> String {
            var root = x
            while let p = parent[root], p != root { root = p }
            var node = x
            while let p = parent[node], p != root {
                parent[node] = root
                node = p
            }
            return root
        }
        for item in items { parent[item.id] = item.id }
        for link in links where parent[link.a] != nil && parent[link.b] != nil {
            let ra = find(link.a)
            let rb = find(link.b)
            if ra != rb { parent[ra] = rb }
        }
        var buckets: [String: [Item]] = [:]
        for item in items { buckets[find(item.id), default: []].append(item) }
        return buckets.values
            .filter { $0.count >= 2 }
            .map { $0.sorted { ($0.score, $0.createdAt) > ($1.score, $1.createdAt) } }
            .sorted { lhs, rhs in
                let l = lhs.map(\.createdAt).max()!
                let r = rhs.map(\.createdAt).max()!
                return l > r
            }
    }

    /// 보존 추천 점수: 선명도(로그)와 애플 미적 점수를 합친 값.
    static func score(sharpness: Double?, aesthetic: Double?) -> Double {
        log1p(max(0, sharpness ?? 0)) + 2 * (aesthetic ?? 0)
    }
}
