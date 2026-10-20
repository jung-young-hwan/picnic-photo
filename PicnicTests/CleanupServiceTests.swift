import XCTest
@testable import Picnic

final class CleanupServiceTests: XCTestCase {
    var store: AssetStore!
    var service: CleanupService!

    override func setUpWithError() throws {
        store = try AssetStore.inMemory()
        service = CleanupService(store: store, largeVideoBytes: 100)
    }

    func testBlurThreshold() {
        XCTAssertEqual(CleanupService.blurThreshold(sortedValues: [1, 2, 3], percentile: 0.05, absoluteMax: 150), 75)
        let values = (0..<200).map(Double.init)
        XCTAssertEqual(CleanupService.blurThreshold(sortedValues: values, percentile: 0.05, absoluteMax: 150), 10)
        let big = (0..<200).map { Double($0) + 1000 }
        XCTAssertEqual(CleanupService.blurThreshold(sortedValues: big, percentile: 0.05, absoluteMax: 150), 150)
    }

    func testBlurryAreSelectedByDefaultAndExclusionsRespected() async throws {
        try store.upsertMetadata([makeMeta("sharp"), makeMeta("soft"), makeMeta("soft2"), makeMeta("shot", screenshot: true)])
        try store.saveAnalysis(id: "sharp", result: makeResult(sharpness: 900), version: 1)
        try store.saveAnalysis(id: "soft", result: makeResult(sharpness: 10), version: 1)
        try store.saveAnalysis(id: "soft2", result: makeResult(sharpness: 20), version: 1)
        try store.saveAnalysis(id: "shot", result: makeResult(sharpness: 1), version: 1)

        var result = try await service.candidates(.blurry)
        XCTAssertEqual(result.items.map(\.id), ["soft", "soft2"])
        XCTAssertEqual(result.defaultSelected, ["soft", "soft2"])
        XCTAssertEqual(result.totalBytes, 2000)

        try store.exclude(ids: ["soft"])
        result = try await service.candidates(.blurry)
        XCTAssertEqual(result.items.map(\.id), ["soft2"])
    }

    func testDocumentsNeedUtilityAndText() async throws {
        try store.upsertMetadata([
            makeMeta("receipt"), makeMeta("sign"), makeMeta("label-doc"), makeMeta("menu"), makeMeta("plain"),
        ])
        try store.saveAnalysis(id: "receipt", result: makeResult(ocr: String(repeating: "가", count: 40), utility: true), version: 1)
        try store.saveAnalysis(id: "sign", result: makeResult(ocr: String(repeating: "가", count: 40), utility: false), version: 1)
        try store.saveAnalysis(id: "label-doc", result: makeResult(labels: ["receipt"], utility: nil), version: 1)
        try store.saveAnalysis(id: "menu", result: makeResult(ocr: String(repeating: "가", count: 90), utility: nil), version: 1)
        try store.saveAnalysis(id: "plain", result: makeResult(labels: ["dog"], utility: true), version: 1)

        let result = try await service.candidates(.document)
        XCTAssertEqual(Set(result.items.map(\.id)), ["receipt", "label-doc", "menu"])
        XCTAssertEqual(result.defaultSelected, [])
    }

    func testLargeVideosSortedBySize() async throws {
        try store.upsertMetadata([
            makeMeta("small", kind: .video, size: 50), makeMeta("big", kind: .video, size: 500),
            makeMeta("mid", kind: .video, size: 200),
        ])
        let result = try await service.candidates(.largeVideo)
        XCTAssertEqual(result.items.map(\.id), ["big", "mid"])
    }

    func testSimilarKeepsBestAndUsesRefine() async throws {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        try store.upsertMetadata([
            makeMeta("a", date: t), makeMeta("b", date: t.addingTimeInterval(2)),
            makeMeta("c", date: t.addingTimeInterval(4)),
        ])
        try store.saveAnalysis(id: "a", result: makeResult(sharpness: 100, dhash: 0), version: 1)
        try store.saveAnalysis(id: "b", result: makeResult(sharpness: 900, dhash: 0b1), version: 1)
        // c 는 a·b 와 거리 8 → 정밀 비교 대상
        try store.saveAnalysis(id: "c", result: makeResult(sharpness: 50, dhash: 0b1111_1111), version: 1)

        let calls = Counter()
        let result = try await service.candidates(.similar) { _, _ in
            await calls.increment()
            return true
        }
        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(result.groups[0].bestID, "b")
        XCTAssertEqual(result.defaultSelected, ["a", "c"])
        let firstCalls = await calls.value
        XCTAssertGreaterThan(firstCalls, 0)

        // 두 번째에는 캐시를 써서 refine 을 부르지 않는다
        _ = try await service.candidates(.similar) { _, _ in
            await calls.increment()
            return true
        }
        let secondCalls = await calls.value
        XCTAssertEqual(secondCalls, firstCalls)
    }
}

actor Counter {
    var value = 0
    func increment() { value += 1 }
}
