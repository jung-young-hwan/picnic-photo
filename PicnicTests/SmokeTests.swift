import XCTest
import Vision
@testable import Picnic

final class SmokeTests: XCTestCase {
    func testPipelineRuns() {
        XCTAssertTrue(true)
    }

    /// 한국어 사전 작성을 위해 Vision 분류 라벨 전체를 로그로 출력한다 (임시).
    func testDumpVisionLabels() throws {
        let request = VNClassifyImageRequest()
        let ids = try request.supportedIdentifiers()
        print("PICNIC_LABEL_COUNT \(ids.count)")
        print("PICNIC_LABELS " + ids.joined(separator: ","))
    }
}
