import XCTest
@testable import Picnic

final class QueryParserTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12))! }

    func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func parse(_ text: String) -> [QueryTerm] {
        QueryParser.parse(text, now: now, calendar: calendar)
    }

    func testYearAndMonthCombine() {
        XCTAssertEqual(parse("2023년 8월"), [.date(DateInterval(start: date(2023, 8, 1), end: date(2023, 9, 1)))])
        XCTAssertEqual(parse("2023.8"), [.date(DateInterval(start: date(2023, 8, 1), end: date(2023, 9, 1)))])
    }

    func testYearAlone() {
        XCTAssertEqual(parse("2023"), [.date(DateInterval(start: date(2023, 1, 1), end: date(2024, 1, 1)))])
        XCTAssertEqual(parse("2023년"), parse("2023"))
    }

    func testRelativeDates() {
        XCTAssertEqual(parse("작년"), [.date(DateInterval(start: date(2025, 1, 1), end: date(2026, 1, 1)))])
        XCTAssertEqual(parse("지난달"), [.date(DateInterval(start: date(2026, 9, 1), end: date(2026, 10, 1)))])
    }

    func testMonthAndSeason() {
        XCTAssertEqual(parse("8월"), [.months([8])])
        XCTAssertEqual(parse("겨울 바다"), [.months([12, 1, 2]), .text("바다")])
    }

    func testFlagsAndStopwords() {
        XCTAssertEqual(parse("캡처"), [.flag(.screenshot)])
        XCTAssertEqual(parse("제주 동영상"), [.text("제주"), .flag(.video)])
        XCTAssertEqual(parse("강아지 사진"), [.text("강아지")])
    }

    func testTextIsLowercased() {
        XCTAssertEqual(parse("  Starbucks  제주 "), [.text("starbucks"), .text("제주")])
    }

    func testFourDigitNumberOutsideRangeIsText() {
        XCTAssertEqual(parse("1234"), [.text("1234")])
    }
}
