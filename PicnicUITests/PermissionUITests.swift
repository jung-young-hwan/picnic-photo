import XCTest

/// 화면 캡처 전에 사진 접근을 허용해 두는 UI 테스트 (screenshots 워크플로 전용).
final class PermissionUITests: XCTestCase {
    func testGrantPhotoAccess() throws {
        let app = XCUIApplication()
        app.launch()
        let connect = app.buttons["사진 연결하기"]
        if connect.waitForExistence(timeout: 15) {
            connect.tap()
        }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 {
            let allow = springboard.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'Full Access' OR label CONTAINS '모든 사진'")
            ).firstMatch
            guard allow.waitForExistence(timeout: 6) else { break }
            allow.tap()
        }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15), "권한 허용 후 탭 화면이 나와야 한다")
    }
}
