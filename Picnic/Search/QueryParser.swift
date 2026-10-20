import Foundation

enum SearchFlag: String, Equatable, Sendable {
    case screenshot
    case video
}

/// 검색어를 해석한 조각. 모든 조각을 만족하는 사진이 결과가 된다 (AND).
enum QueryTerm: Equatable, Sendable {
    /// 기간 [start, end)
    case date(DateInterval)
    /// 연도와 상관없이 해당 월들 (예: "8월", "여름")
    case months(Set<Int>)
    case flag(SearchFlag)
    /// 사물·글자·지역 중 하나라도 맞으면 된다
    case text(String)
}

enum QueryParser {
    static let stopwords: Set<String> = ["사진", "사진들", "이미지", "photo", "photos"]

    static let flagWords: [String: SearchFlag] = [
        "스크린샷": .screenshot, "캡처": .screenshot, "캡쳐": .screenshot, "스샷": .screenshot,
        "screenshot": .screenshot,
        "동영상": .video, "영상": .video, "비디오": .video, "video": .video,
    ]

    static let seasons: [String: Set<Int>] = [
        "봄": [3, 4, 5], "여름": [6, 7, 8], "가을": [9, 10, 11], "겨울": [12, 1, 2],
    ]

    static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> [QueryTerm] {
        let tokens = text.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        var terms: [QueryTerm] = []
        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            let next = i + 1 < tokens.count ? tokens[i + 1] : nil

            if stopwords.contains(token) {
                i += 1
                continue
            }
            if let flag = flagWords[token] {
                terms.append(.flag(flag))
                i += 1
                continue
            }
            if let months = seasons[token] {
                terms.append(.months(months))
                i += 1
                continue
            }
            if let interval = relativeInterval(token, now: now, calendar: calendar) {
                terms.append(.date(interval))
                i += 1
                continue
            }
            // "2023.8", "2023-08", "2023/8"
            if let ym = yearMonth(token),
                let interval = monthInterval(year: ym.0, month: ym.1, calendar: calendar)
            {
                terms.append(.date(interval))
                i += 1
                continue
            }
            if let year = year(token) {
                // "2023년 8월" 은 하나의 기간으로 합친다
                if let next, let month = month(next),
                    let interval = monthInterval(year: year, month: month, calendar: calendar)
                {
                    terms.append(.date(interval))
                    i += 2
                    continue
                }
                if let interval = yearInterval(year, calendar: calendar) {
                    terms.append(.date(interval))
                    i += 1
                    continue
                }
            }
            if let month = month(token) {
                terms.append(.months([month]))
                i += 1
                continue
            }
            terms.append(.text(token))
            i += 1
        }
        return terms
    }

    // MARK: - 패턴

    /// "2023" 또는 "2023년" (1990~2100)
    static func year(_ token: String) -> Int? {
        let digits = token.hasSuffix("년") ? String(token.dropLast()) : token
        guard digits.count == 4, let value = Int(digits), (1990...2100).contains(value) else { return nil }
        return value
    }

    /// "8월" (1~12)
    static func month(_ token: String) -> Int? {
        guard token.hasSuffix("월"), let value = Int(token.dropLast()), (1...12).contains(value) else {
            return nil
        }
        return value
    }

    static func yearMonth(_ token: String) -> (Int, Int)? {
        let parts = token.split(whereSeparator: { $0 == "." || $0 == "-" || $0 == "/" })
        guard parts.count == 2, let y = year(String(parts[0])), let m = Int(parts[1]), (1...12).contains(m)
        else { return nil }
        return (y, m)
    }

    static func relativeInterval(_ token: String, now: Date, calendar: Calendar) -> DateInterval? {
        let thisYear = calendar.component(.year, from: now)
        switch token {
        case "올해", "금년": return yearInterval(thisYear, calendar: calendar)
        case "작년", "지난해": return yearInterval(thisYear - 1, calendar: calendar)
        case "재작년": return yearInterval(thisYear - 2, calendar: calendar)
        case "이번달":
            return calendar.dateInterval(of: .month, for: now)
        case "지난달":
            guard let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) else { return nil }
            return calendar.dateInterval(of: .month, for: lastMonth)
        case "오늘":
            return calendar.dateInterval(of: .day, for: now)
        case "어제":
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return nil }
            return calendar.dateInterval(of: .day, for: yesterday)
        default: return nil
        }
    }

    static func yearInterval(_ year: Int, calendar: Calendar) -> DateInterval? {
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) else { return nil }
        return calendar.dateInterval(of: .year, for: start)
    }

    static func monthInterval(year: Int, month: Int, calendar: Calendar) -> DateInterval? {
        guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else {
            return nil
        }
        return calendar.dateInterval(of: .month, for: start)
    }
}
