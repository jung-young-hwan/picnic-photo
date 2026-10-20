import SwiftUI

/// 크게 보기 요청.
struct ViewerRequest: Identifiable {
    var ids: [String]
    var startID: String
    var id: String { startID }
}

/// 사진을 크게 보고 좌우로 넘기며 비교한다.
struct PhotoViewer: View {
    var request: ViewerRequest
    /// 선택 화면에서 열었을 때만 선택 버튼을 보여 준다
    var selection: SelectionModel?

    @Environment(\.dismiss) private var dismiss
    @State private var currentID: String?
    @State private var showInfo = true

    var body: some View {
        let current = currentID ?? request.startID
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(request.ids, id: \.self) { id in
                        ViewerPage(id: id)
                            .containerRelativeFrame([.horizontal, .vertical])
                            .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { showInfo.toggle() } }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentID)
            .scrollIndicators(.hidden)
            .ignoresSafeArea()

            if showInfo {
                VStack {
                    topBar(current: current)
                    Spacer()
                    ViewerInfo(id: current)
                }
                .transition(.opacity)
            }
        }
        .onAppear { currentID = request.startID }
        .statusBarHidden(!showInfo)
    }

    private func topBar(current: String) -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.black.opacity(0.35)))
            }
            Spacer()
            if let index = request.ids.firstIndex(of: current) {
                Text("\(index + 1) / \(request.ids.count)")
                    .font(.rounded(.subheadline, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Spacer()
            if let selection {
                let selected = selection.isSelected(current)
                Button {
                    selection.toggle(current)
                } label: {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(selected ? Color.rose : .white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(.black.opacity(0.35)))
                }
                .sensoryFeedback(.selection, trigger: selected)
            } else {
                Color.clear.frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

private struct ViewerPage: View {
    var id: String
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        AssetThumbnail(id: id, pixelSize: 1400 * displayScale / 2, contentMode: .fit, highQuality: true)
            .background(Color.black)
    }
}

/// 사진 아래 정보: 날짜, 지역, 인식된 사물, 글자.
private struct ViewerInfo: View {
    var id: String
    @Environment(AppModel.self) private var app
    @State private var info: Info?

    struct Info {
        var record: AssetRecord?
        var place: String?
        var labels: [String]
        var text: String?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let record = info?.record {
                HStack(spacing: 8) {
                    if let date = record.createdAt {
                        Text(Format.fullDate.string(from: date))
                    }
                    if record.mediaType == .video {
                        Text("· 동영상 \(Format.duration(record.duration))")
                    }
                    Spacer()
                    Text(Format.bytes(record.fileSize))
                }
                .font(.rounded(.footnote, weight: .semibold))
            }
            if let place = info?.place {
                Label(place, systemImage: "mappin.and.ellipse")
                    .font(.rounded(.footnote))
            }
            if let labels = info?.labels, !labels.isEmpty {
                Text(labels.map { "#\($0)" }.joined(separator: " "))
                    .font(.rounded(.footnote))
                    .foregroundStyle(Color.roseSoft)
            }
            if let text = info?.text {
                Text("“\(text)”")
                    .font(.rounded(.caption))
                    .lineLimit(2)
                    .opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .task(id: id) {
            let store = app.store
            let lexicon = Lexicon.shared
            info = await Task.detached {
                let labels = ((try? store.labels(for: id)) ?? [])
                    .filter { $0.confidence >= 0.4 }
                    .compactMap { lexicon.korean(for: $0.keyword) }
                var unique: [String] = []
                for label in labels where !unique.contains(label) { unique.append(label) }
                return Info(
                    record: try? store.asset(id: id),
                    place: (try? store.place(forAsset: id))?.displayName,
                    labels: Array(unique.prefix(6)),
                    text: try? store.ocrText(for: id))
            }.value
        }
    }
}
