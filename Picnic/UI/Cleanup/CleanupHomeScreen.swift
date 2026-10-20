import SwiftUI

struct CleanupHomeScreen: View {
    @Environment(AppModel.self) private var app
    @State private var overview: [CleanupCategory: CleanupResult] = [:]
    @State private var loading = true

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("정리")
                            .font(.rounded(.largeTitle, weight: .bold))
                            .foregroundStyle(Color.ink)
                        Text("오늘도 가볍게 정리해 볼까요?")
                            .font(.rounded(.subheadline))
                            .foregroundStyle(Color.inkSoft)
                    }
                    .padding(.top, 12)

                    heroCard
                    AnalysisBanner()

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(CleanupCategory.allCases) { category in
                            NavigationLink(value: category) {
                                CategoryCard(category: category, result: overview[category], loading: loading)
                            }
                            .buttonStyle(SoftPressStyle())
                        }
                    }

                    Text("삭제한 사진은 사진 앱의 '최근 삭제된 항목'에 30일 동안 남아 있어서 언제든 되살릴 수 있어요.")
                        .font(.rounded(.caption))
                        .foregroundStyle(Color.inkSoft)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .background(Color.cream.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: CleanupCategory.self) { category in
                CleanupDetailScreen(category: category)
            }
        }
        .task(id: app.indexer.revision) { await load() }
    }

    private var reclaimable: Int64 {
        // 여러 탭에 겹친 사진은 한 번만 센다
        var sizes: [String: Int64] = [:]
        for (category, result) in overview {
            let ids = (category == .blurry || category == .similar) ? result.defaultSelected : Set(result.items.map(\.id))
            for item in result.items where ids.contains(item.id) { sizes[item.id] = item.fileSize }
        }
        return sizes.values.reduce(0, +)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .bold))
                Text("정리하면 최대")
                    .font(.rounded(.subheadline, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.95))
            Text(loading && overview.isEmpty ? "…" : Format.bytes(reclaimable))
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.snappy, value: reclaimable)
            Text("를 비울 수 있어요")
                .font(.rounded(.subheadline, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
            if app.freedBytes > 0 {
                Text("지금까지 \(Format.bytes(app.freedBytes))를 비웠어요 💗")
                    .font(.rounded(.caption, weight: .semibold))
                    .foregroundStyle(Color.roseDeep)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.9)))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            LinearGradient(
                colors: [Color.rose, Color.lavender], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .overlay(alignment: .topTrailing) {
            Image(systemName: "heart.fill")
                .font(.system(size: 64))
                .foregroundStyle(.white.opacity(0.16))
                .rotationEffect(.degrees(14))
                .padding(18)
        }
        .shadow(color: Color.rose.opacity(0.3), radius: 18, y: 8)
    }

    private func load() async {
        let service = app.cleanup
        let result = await Task.detached(priority: .utility) {
            (try? await service.overview()) ?? [:]
        }.value
        withAnimation(.snappy) {
            overview = result
            loading = false
        }
    }
}

private struct CategoryCard: View {
    var category: CleanupCategory
    var result: CleanupResult?
    var loading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Circle().fill(category.softTint).frame(width: 46, height: 46)
                Image(systemName: category.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(category.tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(category.title)
                    .font(.rounded(.headline, weight: .bold))
                    .foregroundStyle(Color.ink)
                if let result {
                    Text(category == .similar ? "\(Format.count(result.groups.count))묶음 · \(Format.count(result.items.count))장" : "\(Format.count(result.items.count))장")
                        .font(.rounded(.subheadline, weight: .semibold))
                        .foregroundStyle(category.tint)
                    Text(Format.bytes(result.totalBytes))
                        .font(.rounded(.caption))
                        .foregroundStyle(Color.inkSoft)
                } else {
                    Text(loading ? "세는 중…" : "-")
                        .font(.rounded(.subheadline))
                        .foregroundStyle(Color.inkSoft)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .card(padding: 16, radius: 22)
    }
}
