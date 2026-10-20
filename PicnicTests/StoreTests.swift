import XCTest
@testable import Picnic

func makeMeta(
    _ id: String, kind: MediaKind = .image, date: Date = Date(timeIntervalSince1970: 1_700_000_000),
    lat: Double? = nil, lon: Double? = nil, screenshot: Bool = false, size: Int64 = 1000
) -> AssetMetadata {
    AssetMetadata(
        id: id, mediaType: kind, createdAt: date, lat: lat, lon: lon, isScreenshot: screenshot,
        fileSize: size, pixelWidth: 100, pixelHeight: 100, duration: 0)
}

func makeResult(
    labels: [String] = [], ocr: String? = nil, sharpness: Double = 500, aesthetic: Double? = 0.5,
    utility: Bool? = false, dhash: UInt64 = 0
) -> AnalysisResult {
    AnalysisResult(
        labels: labels.map { LabelScore(keyword: $0, confidence: 0.9) }, ocrText: ocr,
        sharpness: sharpness, aesthetic: aesthetic, isUtility: utility, dhash: dhash)
}

final class StoreTests: XCTestCase {
    var store: AssetStore!

    override func setUpWithError() throws {
        store = try AssetStore.inMemory()
    }

    func testUpsertKeepsAnalysis() throws {
        try store.upsertMetadata([makeMeta("a")])
        try store.saveAnalysis(id: "a", result: makeResult(labels: ["dog"], sharpness: 42), version: 1)
        try store.upsertMetadata([makeMeta("a", size: 0)])

        let record = try XCTUnwrap(store.asset(id: "a"))
        XCTAssertEqual(record.sharpness, 42)
        XCTAssertEqual(record.analyzedVersion, 1)
        XCTAssertEqual(record.fileSize, 1000, "크기 0으로 갱신하면 기존 크기를 유지해야 한다")
        XCTAssertEqual(try store.labels(for: "a").map(\.keyword), ["dog"])
    }

    func testPendingExcludesAnalyzedAndVideos() throws {
        try store.upsertMetadata([
            makeMeta("old", date: Date(timeIntervalSince1970: 1)),
            makeMeta("new", date: Date(timeIntervalSince1970: 2)),
            makeMeta("video", kind: .video),
        ])
        XCTAssertEqual(try store.pendingAnalysisIDs(version: 1, limit: 10), ["new", "old"])

        try store.saveAnalysis(id: "new", result: makeResult(), version: 1)
        XCTAssertEqual(try store.pendingAnalysisIDs(version: 1, limit: 10), ["old"])
        XCTAssertEqual(try store.analysisProgress(version: 1), AnalysisProgress(analyzed: 1, total: 2))
    }

    func testFailedThreeTimesIsSkipped() throws {
        try store.upsertMetadata([makeMeta("a")])
        for _ in 0..<3 { try store.markAnalysisFailed(id: "a") }
        XCTAssertEqual(try store.pendingAnalysisIDs(version: 1, limit: 10), [])
    }

    func testRemoveCascadesToLabelsAndOCR() throws {
        try store.upsertMetadata([makeMeta("a"), makeMeta("b")])
        try store.saveAnalysis(id: "a", result: makeResult(labels: ["cat"], ocr: "Hello"), version: 1)
        XCTAssertEqual(try store.ocrText(for: "a"), "hello")

        let removed = try store.removeAssets(notIn: ["b"])
        XCTAssertEqual(removed, 1)
        XCTAssertNil(try store.asset(id: "a"))
        XCTAssertEqual(try store.labels(for: "a"), [])
        XCTAssertNil(try store.ocrText(for: "a"))
    }

    func testPlaceResolutionAppliesToWholeGrid() throws {
        try store.upsertMetadata([
            makeMeta("a", lat: 33.4501, lon: 126.5701),
            makeMeta("b", lat: 33.4512, lon: 126.5699),
            makeMeta("c"),
        ])
        let tasks = try store.pendingPlaceTasks(limit: 10)
        XCTAssertEqual(tasks.map(\.gridKey), ["33.45,126.57"])

        try store.savePlace(
            gridKey: "33.45,126.57",
            info: PlaceInfo(country: "대한민국", admin: "제주특별자치도", locality: "제주시"))
        XCTAssertEqual(try store.pendingPlaceTasks(limit: 10), [])
        XCTAssertEqual(try store.place(forAsset: "b")?.locality, "제주시")
        XCTAssertNil(try store.place(forAsset: "c"))
    }

    func testSimilarityCacheIsOrderIndependent() throws {
        try store.saveSimilarity("z", "a", similar: true)
        XCTAssertEqual(try store.cachedSimilarity("a", "z"), true)
        XCTAssertNil(try store.cachedSimilarity("a", "b"))
    }
}
