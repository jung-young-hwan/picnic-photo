import Foundation
import Observation

/// 사진 선택 상태. 전체 선택·해제와 드래그 범위 선택을 담당한다.
@Observable
final class SelectionModel {
    private(set) var selected: Set<String> = []

    // 드래그 중 상태
    private var dragIDs: [String] = []
    private var dragAnchor: Int?
    private var dragSelects = true
    private var beforeDrag: Set<String> = []
    private(set) var lastDragIndex: Int?

    init(selected: Set<String> = []) {
        self.selected = selected
    }

    var count: Int { selected.count }
    var isDragging: Bool { dragAnchor != nil }

    func isSelected(_ id: String) -> Bool { selected.contains(id) }

    func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    func selectAll(_ ids: [String]) { selected.formUnion(ids) }

    func deselectAll() { selected.removeAll() }

    func deselect(_ ids: [String]) { selected.subtract(ids) }

    func replace(with ids: Set<String>) { selected = ids }

    /// 드래그 시작. 첫 칸이 선택돼 있지 않았으면 범위를 선택, 선택돼 있었으면 범위를 해제한다.
    func beginDrag(at index: Int, in ids: [String]) {
        guard ids.indices.contains(index) else { return }
        dragIDs = ids
        dragAnchor = index
        beforeDrag = selected
        dragSelects = !selected.contains(ids[index])
        lastDragIndex = nil
        updateDrag(to: index)
    }

    /// 손가락이 지나는 칸. 시작 칸~현재 칸 범위만 바뀌고 나머지는 드래그 전 상태로 돌아간다.
    /// 칸이 바뀌었으면 true (햅틱용).
    @discardableResult
    func updateDrag(to index: Int) -> Bool {
        guard let anchor = dragAnchor else { return false }
        let clamped = min(max(index, 0), dragIDs.count - 1)
        guard clamped != lastDragIndex else { return false }
        lastDragIndex = clamped
        var next = beforeDrag
        for i in min(anchor, clamped)...max(anchor, clamped) {
            if dragSelects { next.insert(dragIDs[i]) } else { next.remove(dragIDs[i]) }
        }
        selected = next
        return true
    }

    func endDrag() {
        dragAnchor = nil
        dragIDs = []
        beforeDrag = []
        lastDragIndex = nil
    }
}
