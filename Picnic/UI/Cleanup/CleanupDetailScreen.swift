import SwiftUI

struct CleanupDetailScreen: View {
    var category: CleanupCategory

    @Environment(AppModel.self) private var app
    @State private var result: CleanupResult?
    @State private var selection = SelectionModel()
    @State private var viewer: ViewerRequest?
    @State private var deleting = false
    @State private var toast: String?
    @State private var confirmExclude = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.cream.ignoresSafeArea()
            if let result {
                if result.items.isEmpty {
                    ScrollView {
                        intro(result)
                            .padding(.horizontal, 18)
                        EmptyState(
                            symbol: "checkmark.seal.fill", title: "깔끔해요!",
                            message: "\(category.title)이 없어요.\n분석이 진행되면 더 찾아볼게요.")
                    }
                } else {
                    grid(result)
                }
            } else {
                VStack(spacing: 14) {
                    ProgressView().tint(.rose)
                    Text(category == .similar ? "비슷한 사진을 비교하고 있어요…" : "사진을 모으고 있어요…")
                        .font(.rounded(.subheadline))
                        .foregroundStyle(Color.inkSoft)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let toast {
                Toast(text: toast).padding(.top, 8)
            }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.cream, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if let result, !result.items.isEmpty {
                DeleteBar(
                    count: selection.count, bytes: result.bytes(of: selection.selected), isWorking: deleting,
                    onExclude: { confirmExclude = true }, onDelete: deleteSelected)
            }
        }
        .confirmationDialog(
            "선택한 \(selection.count)장을 정리 대상에서 뺄까요?", isPresented: $confirmExclude, titleVisibility: .visible
        ) {
            Button("정리에서 제외") { excludeSelected() }
        } message: {
            Text("사진은 지워지지 않아요. 설정에서 제외 목록을 비울 수 있어요.")
        }
        .fullScreenCover(item: $viewer) { request in
            PhotoViewer(request: request, selection: selection)
        }
        .task { await load() }
    }

    // MARK: - 화면

    private func intro(_ result: CleanupResult) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(category.softTint).frame(width: 44, height: 44)
                Image(systemName: category.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(category.tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(category.subtitle)
                    .font(.rounded(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Text("\(Format.count(result.items.count))장 · \(Format.bytes(result.totalBytes))")
                    .font(.rounded(.caption))
                    .foregroundStyle(Color.inkSoft)
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    private func grid(_ result: CleanupResult) -> some View {
        let ids = result.items.map(\.id)
        let sections: [PhotoSection] =
            category == .similar
            ? result.groups.map { PhotoSection(id: $0.id, ids: $0.items.map(\.id), bestID: $0.bestID) }
            : [PhotoSection(id: "all", ids: ids)]
        let videos = Set(result.items.filter { $0.mediaType == .video }.map(\.id))

        return PhotoGridView(
            sections: sections,
            videoIDs: videos,
            selection: selection,
            isSelecting: true,
            onOpen: { viewer = ViewerRequest(ids: ids, startID: $0) }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                intro(result)
                SelectionToolbar(ids: ids, selection: selection) {
                    if category == .similar {
                        Button {
                            selection.replace(with: result.defaultSelected)
                        } label: {
                            Label("추천만 남기기", systemImage: "heart.fill")
                        }
                        .buttonStyle(PillButtonStyle(tint: .sage))
                    }
                }
                Text("가로로 쓸어서 여러 장을 한 번에 고를 수 있어요 · 길게 누르면 크게 보여요")
                    .font(.rounded(.caption2))
                    .foregroundStyle(Color.inkSoft)
            }
            .padding(.horizontal, 4)
        } sectionHeader: { section in
            if category == .similar {
                groupHeader(section)
            }
        }
    }

    private func groupHeader(_ section: PhotoSection) -> some View {
        let allSelected = section.ids.allSatisfy { selection.isSelected($0) }
        return HStack {
            Text("\(section.ids.count)장")
                .font(.rounded(.subheadline, weight: .bold))
                .foregroundStyle(Color.ink)
            Spacer()
            Button(allSelected ? "그룹 해제" : "그룹 전체 선택") {
                if allSelected { selection.deselect(section.ids) } else { selection.selectAll(section.ids) }
            }
            .font(.rounded(.footnote, weight: .semibold))
            .foregroundStyle(Color.rose)
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    // MARK: - 동작

    private func load() async {
        let service = app.cleanup
        let model = app
        let loaded = await Task.detached(priority: .userInitiated) {
            try? await service.candidates(category) { a, b in await model.isSimilar(a, b) }
        }.value
        withAnimation(.snappy) {
            result = loaded ?? CleanupResult(category: category, items: [], groups: [], defaultSelected: [])
            selection.replace(with: result?.defaultSelected ?? [])
        }
    }

    private func deleteSelected() {
        guard let result else { return }
        let ids = Array(selection.selected)
        let size = result.bytes(of: selection.selected)
        deleting = true
        Task {
            defer { deleting = false }
            do {
                if let freed = try await app.delete(ids: ids, bytes: size) {
                    remove(ids: Set(ids))
                    show("\(Format.bytes(freed))를 비웠어요 ✨")
                }
            } catch {
                show("삭제하지 못했어요. 다시 시도해 주세요")
            }
        }
    }

    private func excludeSelected() {
        let ids = Array(selection.selected)
        app.exclude(ids: ids)
        remove(ids: Set(ids))
        show("\(ids.count)장을 정리에서 뺐어요")
    }

    private func remove(ids: Set<String>) {
        guard var current = result else { return }
        current.items.removeAll { ids.contains($0.id) }
        current.groups = current.groups.compactMap { group in
            var group = group
            group.items.removeAll { ids.contains($0.id) }
            return group.items.count >= 2 ? group : nil
        }
        if category == .similar {
            let kept = Set(current.groups.flatMap { $0.items.map(\.id) })
            current.items.removeAll { !kept.contains($0.id) }
        }
        current.defaultSelected.subtract(ids)
        withAnimation(.snappy) {
            result = current
            selection.deselect(Array(ids))
        }
    }

    private func show(_ message: String) {
        withAnimation(.spring) { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(.easeOut) { toast = nil }
        }
    }
}
