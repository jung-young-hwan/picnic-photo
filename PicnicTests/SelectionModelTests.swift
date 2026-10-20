import XCTest
@testable import Picnic

final class SelectionModelTests: XCTestCase {
    let ids = ["a", "b", "c", "d", "e"]

    func testSelectAllAndDeselectAll() {
        let model = SelectionModel()
        model.selectAll(ids)
        XCTAssertEqual(model.count, 5)
        model.deselectAll()
        XCTAssertEqual(model.count, 0)
    }

    func testDragFromUnselectedSelectsRange() {
        let model = SelectionModel()
        model.beginDrag(at: 1, in: ids)
        model.updateDrag(to: 3)
        XCTAssertEqual(model.selected, ["b", "c", "d"])
        model.endDrag()
        XCTAssertFalse(model.isDragging)
    }

    func testDragFromSelectedDeselectsRange() {
        let model = SelectionModel(selected: ["a", "b", "c", "d", "e"])
        model.beginDrag(at: 4, in: ids)
        model.updateDrag(to: 2)
        XCTAssertEqual(model.selected, ["a", "b"])
    }

    func testShrinkingRangeRestoresPreviousState() {
        let model = SelectionModel(selected: ["e"])
        model.beginDrag(at: 0, in: ids)
        model.updateDrag(to: 4)
        XCTAssertEqual(model.selected, Set(ids))
        model.updateDrag(to: 1)
        XCTAssertEqual(model.selected, ["a", "b", "e"], "범위 밖 e 는 원래 선택 상태로 돌아가야 한다")
    }

    func testUpdateReportsChangeOnlyOnNewCell() {
        let model = SelectionModel()
        model.beginDrag(at: 0, in: ids)
        XCTAssertTrue(model.updateDrag(to: 1))
        XCTAssertFalse(model.updateDrag(to: 1))
        XCTAssertTrue(model.updateDrag(to: 99), "범위 밖은 마지막 칸으로 맞춘다")
        XCTAssertEqual(model.selected, Set(ids))
    }
}
