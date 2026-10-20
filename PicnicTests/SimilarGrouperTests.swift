import XCTest
@testable import Picnic

final class SimilarGrouperTests: XCTestCase {
    func item(_ id: String, _ seconds: TimeInterval, hash: UInt64, score: Double = 0) -> SimilarGrouper.Item {
        .init(id: id, createdAt: Date(timeIntervalSince1970: seconds), dhash: hash, score: score)
    }

    func testCloseInTimeAndHashIsSure() {
        let c = SimilarGrouper.candidatePairs([item("a", 0, hash: 0b1111), item("b", 10, hash: 0b0111)])
        XCTAssertEqual(c.sure, [.init(a: "a", b: "b")])
        XCTAssertEqual(c.maybe, [])
    }

    func testMediumDistanceIsMaybe() {
        let c = SimilarGrouper.candidatePairs([item("a", 0, hash: 0), item("b", 10, hash: 0b1111_1111)])
        XCTAssertEqual(c.sure, [])
        XCTAssertEqual(c.maybe, [.init(a: "a", b: "b")])
    }

    func testFarApartInTimeIsIgnored() {
        let c = SimilarGrouper.candidatePairs([item("a", 0, hash: 0), item("b", 181, hash: 0)])
        XCTAssertEqual(c.sure, [])
    }

    func testDifferentHashIsIgnored() {
        let c = SimilarGrouper.candidatePairs([item("a", 0, hash: 0), item("b", 1, hash: UInt64.max)])
        XCTAssertEqual(c, .init(sure: [], maybe: []))
    }

    func testGroupsAreTransitiveAndBestFirst() {
        let items = [
            item("a", 0, hash: 0, score: 1), item("b", 5, hash: 0, score: 3), item("c", 10, hash: 0, score: 2),
            item("lonely", 1000, hash: 0),
        ]
        let groups = SimilarGrouper.groups(
            items, links: [.init(a: "a", b: "b"), .init(a: "b", b: "c")])
        XCTAssertEqual(groups.map { $0.map(\.id) }, [["b", "c", "a"]])
    }

    func testNewestGroupComesFirst() {
        let items = [item("a", 0, hash: 0), item("b", 1, hash: 0), item("c", 500, hash: 0), item("d", 501, hash: 0)]
        let groups = SimilarGrouper.groups(items, links: [.init(a: "a", b: "b"), .init(a: "c", b: "d")])
        XCTAssertEqual(groups.map { Set($0.map(\.id)) }, [["c", "d"], ["a", "b"]])
    }
}
