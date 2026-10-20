import SwiftUI
import UIKit

/// 그리드의 한 묶음 (비슷한 사진 그룹 또는 전체 목록).
struct PhotoSection: Identifiable, Equatable {
    var id: String
    var ids: [String]
    /// 추천 배지를 붙일 사진
    var bestID: String?
}

/// 사진 그리드. 선택 모드에서는 탭으로 하나씩, 가로로 쓸어서 여러 장을 연속 선택한다.
struct PhotoGridView<Header: View, SectionHeader: View>: View {
    var sections: [PhotoSection]
    var videoIDs: Set<String> = []
    var selection: SelectionModel
    var isSelecting: Bool
    var onOpen: (String) -> Void
    @ViewBuilder var header: () -> Header
    @ViewBuilder var sectionHeader: (PhotoSection) -> SectionHeader

    @State private var tracker = DragTracker()
    @State private var position = ScrollPosition()
    @State private var hapticTick = 0
    @State private var autoScroll: Task<Void, Never>?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)
    private static var space: String { "photoGridContent" }

    var body: some View {
        let allIDs = sections.flatMap(\.ids)
        let starts = sectionStarts()

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header()
                ForEach(Array(sections.enumerated()), id: \.element.id) { sectionIndex, section in
                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader(section)
                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(Array(section.ids.enumerated()), id: \.element) { offset, id in
                                let index = starts[sectionIndex] + offset
                                PhotoCell(
                                    id: id,
                                    isSelected: selection.isSelected(id),
                                    isSelecting: isSelecting,
                                    isVideo: videoIDs.contains(id),
                                    isBest: section.bestID == id
                                )
                                .onGeometryChange(for: CGRect.self) { proxy in
                                    proxy.frame(in: .named(Self.space))
                                } action: { frame in
                                    tracker.frames[index] = frame
                                }
                                .onTapGesture {
                                    if isSelecting { selection.toggle(id) } else { onOpen(id) }
                                }
                                .onLongPressGesture(minimumDuration: 0.35) { onOpen(id) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 24)
            .coordinateSpace(.named(Self.space))
            .gesture(
                DragSelectRecognizer(
                    isEnabled: isSelecting,
                    onBegan: { start, current in beginDrag(start: start, current: current, ids: allIDs) },
                    onChanged: { point in moveDrag(to: point) },
                    onEnded: endDrag))
        }
        .scrollPosition($position)
        .onScrollGeometryChange(for: CGRect.self) { geometry in
            geometry.visibleRect
        } action: { _, visible in
            tracker.visibleRect = visible
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentSize.height
        } action: { _, height in
            tracker.contentHeight = height
        }
        .scrollDisabled(selection.isDragging)
        .sensoryFeedback(.selection, trigger: hapticTick)
    }

    private func sectionStarts() -> [Int] {
        var starts: [Int] = []
        var running = 0
        for section in sections {
            starts.append(running)
            running += section.ids.count
        }
        return starts
    }

    // MARK: - 드래그 선택

    private func beginDrag(start: CGPoint, current: CGPoint, ids: [String]) {
        guard let index = tracker.index(at: start) ?? tracker.index(at: current) else { return }
        tracker.fingerOffsetInView = current.y - tracker.visibleRect.minY
        selection.beginDrag(at: index, in: ids)
        hapticTick += 1
        moveDrag(to: current)
        startAutoScroll()
    }

    private func moveDrag(to point: CGPoint) {
        guard selection.isDragging else { return }
        tracker.fingerX = point.x
        tracker.fingerOffsetInView = point.y - tracker.visibleRect.minY
        if let index = tracker.index(at: point), selection.updateDrag(to: index) {
            hapticTick += 1
        }
    }

    private func endDrag() {
        autoScroll?.cancel()
        autoScroll = nil
        selection.endDrag()
    }

    /// 손가락이 화면 위·아래 가장자리 60pt 안에 있으면 자동으로 스크롤한다.
    private func startAutoScroll() {
        autoScroll?.cancel()
        autoScroll = Task { @MainActor in
            while !Task.isCancelled, selection.isDragging {
                let visible = tracker.visibleRect
                let finger = tracker.fingerOffsetInView
                let edge: CGFloat = 60
                var speed: CGFloat = 0
                if finger < edge {
                    speed = -max(4, (edge - finger) / 3)
                } else if finger > visible.height - edge {
                    speed = max(4, (finger - (visible.height - edge)) / 3)
                }
                if speed != 0 {
                    let maxY = max(0, tracker.contentHeight - visible.height)
                    let target = min(max(0, visible.minY + speed), maxY)
                    if target != visible.minY {
                        position.scrollTo(y: target)
                        let point = CGPoint(x: tracker.fingerX, y: target + finger)
                        if let index = tracker.index(at: point), selection.updateDrag(to: index) {
                            hapticTick += 1
                        }
                    }
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }
}

/// 드래그 중 계산에 쓰는 값. 화면을 다시 그릴 필요가 없어 관찰하지 않는다.
final class DragTracker {
    /// 칸 번호 → 그리드 콘텐츠 좌표의 위치
    var frames: [Int: CGRect] = [:]
    var visibleRect: CGRect = .zero
    var contentHeight: CGFloat = 0
    var fingerOffsetInView: CGFloat = 0
    var fingerX: CGFloat = 0

    func index(at point: CGPoint) -> Int? {
        var nearest: (index: Int, distance: CGFloat)?
        for (index, frame) in frames {
            if frame.contains(point) { return index }
            // 칸 사이 틈에 손가락이 있으면 가장 가까운 칸
            let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
            let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
            let distance = dx + dy
            if distance < 6, distance < (nearest?.distance ?? .infinity) {
                nearest = (index, distance)
            }
        }
        return nearest?.index
    }
}

/// 가로 방향으로 시작한 드래그만 잡는 UIKit 제스처. 세로로 시작하면 스크롤에 양보한다.
struct DragSelectRecognizer: UIGestureRecognizerRepresentable {
    var isEnabled: Bool
    var onBegan: (_ start: CGPoint, _ current: CGPoint) -> Void
    var onChanged: (CGPoint) -> Void
    var onEnded: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        recognizer.isEnabled = isEnabled
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let point = context.converter.localLocation
        switch recognizer.state {
        case .began:
            let moved = recognizer.translation(in: recognizer.view)
            onBegan(CGPoint(x: point.x - moved.x, y: point.y - moved.y), point)
        case .changed:
            onChanged(point)
        case .ended, .cancelled, .failed:
            onEnded()
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.2
        }
    }
}

/// 그리드 한 칸.
struct PhotoCell: View {
    var id: String
    var isSelected: Bool
    var isSelecting: Bool
    var isVideo: Bool
    var isBest: Bool

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { AssetThumbnail(id: id, pixelSize: 140 * displayScale) }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.rose.opacity(0.18))
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.rose, lineWidth: 3)
                }
            }
            .overlay(alignment: .topLeading) {
                if isBest {
                    Label("추천", systemImage: "heart.fill")
                        .font(.rounded(.caption2, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.sage))
                        .padding(5)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if isVideo {
                    Image(systemName: "play.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isSelecting {
                    ZStack {
                        Circle()
                            .fill(isSelected ? Color.rose : Color.black.opacity(0.18))
                        Circle()
                            .strokeBorder(.white, lineWidth: 1.5)
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 22, height: 22)
                    .padding(6)
                }
            }
            .scaleEffect(isSelected ? 0.93 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
            .contentShape(Rectangle())
    }
}
