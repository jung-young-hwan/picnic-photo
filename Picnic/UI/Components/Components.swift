import SwiftUI

/// 칩을 여러 줄로 흘려 배치한다.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// 둥근 칩.
struct Chip: View {
    var text: String
    var symbol: String?
    var tint: Color = .rose
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).font(.caption.weight(.semibold))
                }
                Text(text)
            }
            .font(.rounded(.subheadline, weight: .medium))
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(Capsule().fill(tint.opacity(0.16)))
        }
        .buttonStyle(SoftPressStyle())
    }
}

/// 분석 진행 배너. 분석이 끝나면 숨는다.
struct AnalysisBanner: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let indexer = app.indexer
        if indexer.isWorking || !indexer.progress.isComplete && indexer.phase != .idle {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.roseSoft).frame(width: 38, height: 38)
                    Image(systemName: indexer.phase == .pausedHot ? "thermometer.medium" : "sparkles")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.rose)
                        .symbolEffect(.pulse, isActive: indexer.phase == .analyzing)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(title(indexer))
                        .font(.rounded(.subheadline, weight: .semibold))
                        .foregroundStyle(Color.ink)
                    if indexer.phase == .analyzing || indexer.phase == .pausedHot {
                        ProgressView(value: indexer.progress.fraction)
                            .tint(.rose)
                        Text("\(Format.count(indexer.progress.analyzed)) / \(Format.count(indexer.progress.total))장")
                            .font(.rounded(.caption))
                            .foregroundStyle(Color.inkSoft)
                    }
                }
            }
            .card(padding: 14, radius: 18)
        }
    }

    private func title(_ indexer: Indexer) -> String {
        switch indexer.phase {
        case .syncing: return "사진 목록을 불러오고 있어요"
        case .measuring: return "사진 용량을 확인하고 있어요"
        case .analyzing: return "사진을 하나씩 살펴보고 있어요"
        case .pausedHot: return "기기가 뜨거워서 잠깐 쉬고 있어요"
        case .idle, .done: return "분석을 이어서 할게요"
        }
    }
}

/// 화면 아래에 잠깐 떠오르는 알림.
struct Toast: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.rounded(.subheadline, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.roseDeep))
            .shadow(color: Color.rose.opacity(0.35), radius: 12, y: 6)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// 빈 화면 안내.
struct EmptyState: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.roseSoft).frame(width: 84, height: 84)
                Image(systemName: symbol)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Color.rose)
            }
            Text(title)
                .font(.rounded(.headline, weight: .bold))
                .foregroundStyle(Color.ink)
            Text(message)
                .font(.rounded(.subheadline))
                .foregroundStyle(Color.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
