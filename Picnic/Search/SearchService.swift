import Foundation

/// 결과 사진이 왜 나왔는지 (화면에 칩으로 표시).
enum MatchReason: String, Hashable, Sendable, CaseIterable {
    case object  // 사물·장면
    case text  // 사진 속 글자
    case place  // 지역
    case date  // 날짜
    case kind  // 스크린샷·동영상

    var title: String {
        switch self {
        case .object: return "사물"
        case .text: return "글자"
        case .place: return "지역"
        case .date: return "날짜"
        case .kind: return "종류"
        }
    }
}

struct SearchHit: Identifiable, Equatable, Sendable {
    var summary: AssetSummary
    var reasons: Set<MatchReason>
    var id: String { summary.id }
}

final class SearchService: Sendable {
    let store: AssetStore
    let lexicon: Lexicon

    init(store: AssetStore, lexicon: Lexicon) {
        self.store = store
        self.lexicon = lexicon
    }

    func search(_ query: String, now: Date = Date(), calendar: Calendar = .current) throws -> [SearchHit] {
        let terms = QueryParser.parse(query, now: now, calendar: calendar)
        guard !terms.isEmpty else { return [] }

        var filter = AssetFilter()
        var words: [String] = []
        for term in terms {
            switch term {
            case .date(let interval): filter.intervals.append(interval)
            case .months(let months): filter.months.append(months)
            case .flag(let flag): filter.flags.append(flag)
            case .text(let word): words.append(word)
            }
        }

        // 단어마다 사물·글자·지역 중 하나라도 맞는 사진을 찾고, 단어끼리는 교집합.
        var matched: Set<String>?
        var reasons: [String: Set<MatchReason>] = [:]
        for word in words {
            let byObject = try store.ids(withLabels: lexicon.labels(for: word))
            let byText = try store.ids(withTextContaining: word)
            let byPlace = try store.ids(withPlaceContaining: word)
            for id in byObject { reasons[id, default: []].insert(.object) }
            for id in byText { reasons[id, default: []].insert(.text) }
            for id in byPlace { reasons[id, default: []].insert(.place) }
            let union = byObject.union(byText).union(byPlace)
            matched = matched.map { $0.intersection(union) } ?? union
        }
        if let matched, matched.isEmpty { return [] }

        let base = try store.summaries(matching: filter)
        var common: Set<MatchReason> = []
        if !filter.intervals.isEmpty || !filter.months.isEmpty { common.insert(.date) }
        if !filter.flags.isEmpty { common.insert(.kind) }

        return base.compactMap { summary in
            if let matched, !matched.contains(summary.id) { return nil }
            return SearchHit(summary: summary, reasons: common.union(reasons[summary.id] ?? []))
        }
    }

    /// 검색창 아래 추천어: 많이 나온 사물(한국어)과 지역.
    func suggestions(limit: Int = 8) throws -> [String] {
        let labels = try store.topLabels(limit: limit * 3).compactMap { lexicon.korean(for: $0) }
        let places = try store.topPlaces(limit: limit / 2)
        // 사물 → 지역 → 사물 … 번갈아 섞는다
        var mixed: [String] = []
        var labelIterator = labels.makeIterator()
        var placeIterator = places.makeIterator()
        while mixed.count < limit * 2 {
            let a = labelIterator.next()
            let b = labelIterator.next()
            let c = placeIterator.next()
            if a == nil && b == nil && c == nil { break }
            mixed += [a, b, c].compactMap { $0 }
        }
        var seen: Set<String> = []
        var result: [String] = []
        for word in mixed where seen.insert(word).inserted {
            result.append(word)
            if result.count == limit { break }
        }
        return result
    }
}
