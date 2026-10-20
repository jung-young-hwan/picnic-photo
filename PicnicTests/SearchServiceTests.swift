import XCTest
@testable import Picnic

final class SearchServiceTests: XCTestCase {
    var store: AssetStore!
    var service: SearchService!
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    override func setUpWithError() throws {
        store = try AssetStore.inMemory()
        let lexicon = Lexicon(entries: [
            .init(label: "dog", ko: ["강아지", "개"]),
            .init(label: "beach", ko: ["해변", "바다"]),
            .init(label: "seascape", ko: ["바다"]),
        ])
        service = SearchService(store: store, lexicon: lexicon)

        try store.upsertMetadata([
            makeMeta("dog-jeju", date: date(2023, 8, 15), lat: 33.45, lon: 126.57),
            makeMeta("beach-jeju", date: date(2024, 7, 10), lat: 33.45, lon: 126.57),
            makeMeta("menu", date: date(2024, 1, 5)),
            makeMeta("shot", date: date(2024, 1, 6), screenshot: true),
            makeMeta("clip", kind: .video, date: date(2024, 1, 7)),
        ])
        try store.saveAnalysis(id: "dog-jeju", result: makeResult(labels: ["dog"]), version: 1)
        try store.saveAnalysis(id: "beach-jeju", result: makeResult(labels: ["beach"]), version: 1)
        try store.saveAnalysis(id: "menu", result: makeResult(ocr: "스타 벅스 아메리카노 4,500원"), version: 1)
        try store.savePlace(
            gridKey: "33.45,126.57",
            info: PlaceInfo(country: "대한민국", admin: "제주특별자치도", locality: "제주시"))
    }

    func ids(_ query: String) throws -> [String] {
        try service.search(query, now: date(2026, 10, 20), calendar: calendar).map(\.id)
    }

    func testKoreanObjectSearch() throws {
        XCTAssertEqual(try ids("강아지"), ["dog-jeju"])
        XCTAssertEqual(try ids("개"), ["dog-jeju"])
        XCTAssertEqual(try ids("dog"), ["dog-jeju"])
    }

    func testPlaceSearch() throws {
        XCTAssertEqual(try ids("제주"), ["beach-jeju", "dog-jeju"])
    }

    func testWordsAreCombinedWithAnd() throws {
        XCTAssertEqual(try ids("제주 바다"), ["beach-jeju"])
        XCTAssertEqual(try ids("제주 바다 강아지"), [])
    }

    func testTextSearchIgnoresSpaces() throws {
        XCTAssertEqual(try ids("스타벅스"), ["menu"])
        XCTAssertEqual(try ids("아메리카노"), ["menu"])
    }

    func testDateAndFlags() throws {
        XCTAssertEqual(try ids("2023년 8월"), ["dog-jeju"])
        XCTAssertEqual(try ids("제주 2024"), ["beach-jeju"])
        XCTAssertEqual(try ids("스크린샷"), ["shot"])
        XCTAssertEqual(try ids("동영상"), ["clip"])
    }

    func testReasons() throws {
        let hit = try XCTUnwrap(service.search("제주 강아지", now: date(2026, 10, 20), calendar: calendar).first)
        XCTAssertEqual(hit.reasons, [.place, .object])
    }

    func testNoMatchReturnsEmpty() throws {
        XCTAssertEqual(try ids("고양이"), [])
        XCTAssertEqual(try ids("   "), [])
    }

    func testLikeWildcardsAreEscaped() throws {
        XCTAssertEqual(try ids("%"), [])
    }
}
