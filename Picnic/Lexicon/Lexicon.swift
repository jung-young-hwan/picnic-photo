import Foundation

/// Vision 분류 라벨(영어)과 한국어 검색어를 잇는 사전.
final class Lexicon: Sendable {
    struct Entry: Codable, Equatable, Sendable {
        /// Vision 라벨 식별자 (예: "dog")
        let label: String
        /// 한국어 대표어가 맨 앞, 나머지는 동의어 (예: ["강아지", "개", "멍멍이"])
        let ko: [String]
    }

    static let shared: Lexicon = {
        do {
            return try Lexicon.loadBundled()
        } catch {
            assertionFailure("lexicon_ko.json 로드 실패: \(error)")
            return Lexicon(entries: [])
        }
    }()

    let entries: [Entry]
    private let koreanToLabels: [String: Set<String>]
    private let labelToKorean: [String: String]

    init(entries: [Entry]) {
        self.entries = entries
        var map: [String: Set<String>] = [:]
        var reverse: [String: String] = [:]
        for entry in entries {
            for word in entry.ko {
                map[Lexicon.normalize(word), default: []].insert(entry.label)
            }
            if let first = entry.ko.first, reverse[entry.label] == nil {
                reverse[entry.label] = first
            }
        }
        koreanToLabels = map
        labelToKorean = reverse
    }

    static func loadBundled(bundle: Bundle = .main) throws -> Lexicon {
        guard let url = bundle.url(forResource: "lexicon_ko", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let data = try Data(contentsOf: url)
        return Lexicon(entries: try JSONDecoder().decode([Entry].self, from: data))
    }

    static func normalize(_ word: String) -> String {
        word.lowercased().replacingOccurrences(of: " ", with: "")
    }

    /// 검색어에 해당하는 Vision 라벨들. 영어 라벨을 그대로 입력해도 찾는다.
    func labels(for word: String) -> Set<String> {
        let key = Lexicon.normalize(word)
        var result = koreanToLabels[key] ?? []
        let asLabel = word.lowercased().replacingOccurrences(of: " ", with: "_")
        if labelToKorean[asLabel] != nil {
            result.insert(asLabel)
        }
        return result
    }

    /// 라벨의 한국어 대표어. 사전에 없으면 nil.
    func korean(for label: String) -> String? {
        labelToKorean[label]
    }
}
