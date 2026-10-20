import SwiftUI

struct SearchScreen: View {
    @Environment(AppModel.self) private var app

    @State private var query = ""
    @State private var submitted = ""
    @State private var hits: [SearchHit] = []
    @State private var isSearching = false
    @State private var suggestions: [String] = []
    @State private var selection = SelectionModel()
    @State private var isSelecting = false
    @State private var viewer: ViewerRequest?
    @State private var toast: String?
    @State private var deleting = false
    @FocusState private var fieldFocused: Bool

    private let examples = ["강아지", "제주 바다", "2023년 8월", "영수증", "스타벅스", "작년 여름", "케이크", "노을"]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.cream.ignoresSafeArea()
                content
                if let toast {
                    Toast(text: toast).padding(.top, 8)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(item: $viewer) { request in
            PhotoViewer(request: request, selection: isSelecting ? selection : nil)
        }
        .task(id: app.indexer.revision) { await loadSuggestions() }
        .onAppear {
            if query.isEmpty, let demo = DemoHooks.query { query = demo }
        }
        .task(id: query) {
            // 입력을 잠깐 멈추면 검색한다
            try? await Task.sleep(for: .milliseconds(350))
            if !Task.isCancelled { await runSearch() }
        }
        .onChange(of: app.indexer.revision) {
            Task { await runSearch() }
        }
    }

    // MARK: - 화면

    @ViewBuilder
    private var content: some View {
        let ids = hits.map(\.id)
        if submitted.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    AnalysisBanner()
                    suggestionSection
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
        } else {
            PhotoGridView(
                sections: [PhotoSection(id: "results", ids: ids)],
                videoIDs: Set(hits.filter { $0.summary.mediaType == .video }.map(\.id)),
                selection: selection,
                isSelecting: isSelecting,
                onOpen: { viewer = ViewerRequest(ids: ids, startID: $0) }
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    resultSummary(ids: ids)
                }
                .padding(.horizontal, 4)
            } sectionHeader: { _ in
                EmptyView()
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                if isSelecting {
                    DeleteBar(
                        count: selection.count, bytes: bytes(of: selection.selected), isWorking: deleting,
                        onExclude: nil, onDelete: deleteSelected)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("어떤 사진을 찾을까요?")
                .font(.rounded(.title, weight: .bold))
                .foregroundStyle(Color.ink)
                .padding(.top, 12)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.rose)
                TextField("강아지, 제주 바다, 영수증…", text: $query)
                    .font(.rounded(.body))
                    .foregroundStyle(Color.ink)
                    .focused($fieldFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit {
                        app.remember(search: query)
                        Task { await runSearch() }
                    }
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.inkSoft)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Capsule().fill(Color.card))
            .overlay(Capsule().strokeBorder(fieldFocused ? Color.rose : Color.line, lineWidth: 1.5))
            .shadow(color: Color.rose.opacity(0.10), radius: 12, y: 5)
        }
    }

    private var suggestionSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !app.recentSearches.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        sectionTitle("최근 검색")
                        Spacer()
                        Button("지우기") { app.clearRecentSearches() }
                            .font(.rounded(.footnote, weight: .medium))
                            .foregroundStyle(Color.inkSoft)
                    }
                    FlowLayout {
                        ForEach(app.recentSearches, id: \.self) { word in
                            Chip(text: word, symbol: "clock", tint: .lavender) { pick(word) }
                        }
                    }
                }
            }
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("내 사진에 많은 것")
                    FlowLayout {
                        ForEach(suggestions, id: \.self) { word in
                            Chip(text: word, symbol: "sparkle", tint: .rose) { pick(word) }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("이렇게 찾아보세요")
                FlowLayout {
                    ForEach(examples, id: \.self) { word in
                        Chip(text: word, tint: .sage) { pick(word) }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    tip("tag.fill", "사물이나 장면: 강아지, 케이크, 노을")
                    tip("text.viewfinder", "사진 속 글자: 간판, 메뉴판, 영수증 내용")
                    tip("mappin.and.ellipse", "지역: 제주, 강남구, 오사카")
                    tip("calendar", "날짜: 2023년 8월, 작년, 여름")
                }
                .card(padding: 16, radius: 20)
                .padding(.top, 6)
            }
        }
    }

    private func resultSummary(ids: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isSearching ? "찾고 있어요…" : "\(Format.count(ids.count))장을 찾았어요")
                        .font(.rounded(.headline, weight: .bold))
                        .foregroundStyle(Color.ink)
                    if let reasons = reasonSummary() {
                        Text(reasons)
                            .font(.rounded(.caption))
                            .foregroundStyle(Color.inkSoft)
                    }
                }
                Spacer()
                if !ids.isEmpty {
                    Button(isSelecting ? "완료" : "선택") {
                        withAnimation(.snappy) {
                            isSelecting.toggle()
                            if !isSelecting { selection.deselectAll() }
                        }
                    }
                    .buttonStyle(PillButtonStyle(filled: isSelecting))
                }
            }
            if isSelecting {
                SelectionToolbar(ids: ids, selection: selection)
            }
            if ids.isEmpty && !isSearching {
                EmptyState(
                    symbol: "magnifyingglass", title: "아직 찾지 못했어요",
                    message: "다른 단어로 찾아보세요.\n분석이 끝나지 않았다면 조금 뒤에 더 많이 나와요.")
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.rounded(.subheadline, weight: .bold))
            .foregroundStyle(Color.inkSoft)
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).foregroundStyle(Color.ink)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Color.rose)
        }
        .font(.rounded(.footnote))
    }

    // MARK: - 동작

    private func pick(_ word: String) {
        query = word
        app.remember(search: word)
        fieldFocused = false
    }

    private func runSearch() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            submitted = ""
            hits = []
            isSelecting = false
            selection.deselectAll()
            return
        }
        isSearching = true
        let service = app.search
        let found = await Task.detached(priority: .userInitiated) {
            (try? service.search(text)) ?? []
        }.value
        submitted = text
        hits = found
        isSearching = false
        let valid = Set(found.map(\.id))
        selection.replace(with: selection.selected.intersection(valid))
    }

    private func loadSuggestions() async {
        let service = app.search
        suggestions = await Task.detached { (try? service.suggestions()) ?? [] }.value
    }

    private func reasonSummary() -> String? {
        var counts: [MatchReason: Int] = [:]
        for hit in hits {
            for reason in hit.reasons { counts[reason, default: 0] += 1 }
        }
        let parts = MatchReason.allCases.compactMap { reason -> String? in
            guard let count = counts[reason], reason != .date, reason != .kind else { return nil }
            return "\(reason.title) \(Format.count(count))"
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func bytes(of ids: Set<String>) -> Int64 {
        hits.reduce(0) { ids.contains($1.id) ? $0 + $1.summary.fileSize : $0 }
    }

    private func deleteSelected() {
        let ids = Array(selection.selected)
        let size = bytes(of: selection.selected)
        deleting = true
        Task {
            defer { deleting = false }
            do {
                if let freed = try await app.delete(ids: ids, bytes: size) {
                    hits.removeAll { selection.selected.contains($0.id) }
                    selection.deselectAll()
                    show("\(Format.bytes(freed))를 비웠어요 ✨")
                }
            } catch {
                show("삭제하지 못했어요. 다시 시도해 주세요")
            }
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
