import XCTest
@testable import Picnic

final class LexiconTests: XCTestCase {
    func testKoreanSynonymsMapToLabel() {
        let lexicon = Lexicon(entries: [.init(label: "dog", ko: ["강아지", "개", "멍멍이"])])
        XCTAssertEqual(lexicon.labels(for: "강아지"), ["dog"])
        XCTAssertEqual(lexicon.labels(for: "멍멍이"), ["dog"])
        XCTAssertEqual(lexicon.labels(for: "DOG"), ["dog"])
        XCTAssertEqual(lexicon.korean(for: "dog"), "강아지")
        XCTAssertEqual(lexicon.labels(for: "고양이"), [])
    }

    func testOneWordCanMapToSeveralLabels() {
        let lexicon = Lexicon(entries: [
            .init(label: "beach", ko: ["해변", "바다"]),
            .init(label: "seascape", ko: ["바다"]),
        ])
        XCTAssertEqual(lexicon.labels(for: "바다"), ["beach", "seascape"])
    }

    func testBundledLexiconIsValid() throws {
        let lexicon = try Lexicon.loadBundled(bundle: Bundle(for: SearchService.self))
        XCTAssertGreaterThan(lexicon.entries.count, 300)
        for entry in lexicon.entries {
            XCTAssertFalse(entry.ko.isEmpty, "\(entry.label) 에 한국어가 없음")
            XCTAssertFalse(entry.ko.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }))
        }
        XCTAssertEqual(lexicon.labels(for: "강아지").contains("dog"), true)
        XCTAssertEqual(lexicon.labels(for: "영수증").contains("receipt"), true)
    }
}
