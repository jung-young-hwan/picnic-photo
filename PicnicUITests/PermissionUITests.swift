import XCTest

/// 화면 캡처 전에 사진 접근을 허용해 두는 UI 테스트 (screenshots 워크플로 전용).
final class PermissionUITests: XCTestCase {
    func testGrantPhotoAccess() throws {
        let app = XCUIApplication()
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        let connect = app.buttons["사진 연결하기"]
        if connect.waitForExistence(timeout: 15) {
            connect.tap()
        } else {
            print("PICNIC_DEBUG no connect button\n\(app.debugDescription)")
        }

        for attempt in 0..<4 {
            sleep(3)
            let candidates = springboard.buttons.allElementsBoundByIndex.map(\.label)
            print("PICNIC_DEBUG attempt \(attempt) springboard buttons: \(candidates)")
            let allow = springboard.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'Full Access' OR label CONTAINS[c] 'Allow' OR label CONTAINS '허용'")
            ).firstMatch
            if allow.exists {
                print("PICNIC_DEBUG tapping \(allow.label)")
                allow.tap()
            } else if app.tabBars.firstMatch.exists {
                break
            }
        }
        if !app.tabBars.firstMatch.waitForExistence(timeout: 10) {
            print("PICNIC_DEBUG app tree\n\(app.debugDescription)")
        }
        XCTAssertTrue(app.tabBars.firstMatch.exists, "권한 허용 후 탭 화면이 나와야 한다")
    }
}
