import SwiftUI

/// 전체 선택 / 전체 해제 버튼 줄. 두 버튼은 항상 함께 보인다.
struct SelectionToolbar<Extra: View>: View {
    var ids: [String]
    var selection: SelectionModel
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        FlowLayout(spacing: 8) {
                Button {
                    selection.selectAll(ids)
                } label: {
                    Label("전체 선택", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(PillButtonStyle())
                .disabled(ids.isEmpty)

                Button {
                    selection.deselectAll()
                } label: {
                    Label("전체 해제", systemImage: "circle")
                }
                .buttonStyle(PillButtonStyle(tint: .inkSoft))
                .disabled(selection.count == 0)

                extra()
        }
    }
}

extension SelectionToolbar where Extra == EmptyView {
    init(ids: [String], selection: SelectionModel) {
        self.init(ids: ids, selection: selection) { EmptyView() }
    }
}

/// 화면 아래 고정 바: 선택 개수·용량과 삭제 버튼.
struct DeleteBar: View {
    var count: Int
    var bytes: Int64
    var isWorking: Bool
    var onExclude: (() -> Void)?
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(count == 0 ? "사진을 골라 주세요" : "\(Format.count(count))장 선택")
                    .font(.rounded(.subheadline, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .contentTransition(.numericText())
                if count > 0 {
                    Text("\(Format.bytes(bytes)) 비울 수 있어요")
                        .font(.rounded(.caption))
                        .foregroundStyle(Color.inkSoft)
                        .contentTransition(.numericText())
                }
            }
            Spacer()
            if let onExclude, count > 0 {
                Button("제외", action: onExclude)
                    .buttonStyle(PillButtonStyle(tint: .inkSoft))
            }
            Button(action: onDelete) {
                HStack(spacing: 6) {
                    if isWorking {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "trash.fill")
                    }
                    Text("삭제")
                }
            }
            .buttonStyle(PillButtonStyle(filled: true))
            .disabled(count == 0 || isWorking)
            .opacity(count == 0 ? 0.5 : 1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.line, lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .animation(.snappy, value: count)
    }
}
