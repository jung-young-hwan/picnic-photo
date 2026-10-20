import SwiftUI

struct SettingsScreen: View {
    @Environment(AppModel.self) private var app
    @State private var indexBytes: Int64 = 0
    @State private var exclusions = 0
    @State private var confirmReset = false

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("설정")
                        .font(.rounded(.largeTitle, weight: .bold))
                        .foregroundStyle(Color.ink)
                        .padding(.top, 12)

                    progressCard

                    group("저장 공간") {
                        row("internaldrive.fill", .lavender, "앱이 쓰는 공간", value: Format.bytes(indexBytes))
                        Text("사진 미리보기는 따로 저장하지 않고, 검색용 색인만 저장해요.")
                            .font(.rounded(.caption))
                            .foregroundStyle(Color.inkSoft)
                    }

                    group("분석") {
                        Toggle(isOn: $app.keepScreenOn) {
                            label("sun.max.fill", .butter, "분석하는 동안 화면 켜두기")
                        }
                        .tint(.rose)
                        Text("충전기에 꽂아 두고 켜 두면 더 빨리 끝나요.")
                            .font(.rounded(.caption))
                            .foregroundStyle(Color.inkSoft)
                    }

                    group("정리") {
                        HStack {
                            label("eye.slash.fill", .sage, "정리에서 제외한 사진")
                            Spacer()
                            Text("\(Format.count(exclusions))장")
                                .font(.rounded(.subheadline))
                                .foregroundStyle(Color.inkSoft)
                        }
                        if exclusions > 0 {
                            Button("제외 목록 비우기") {
                                try? app.store.clearExclusions()
                                refresh()
                            }
                            .buttonStyle(PillButtonStyle(tint: .sage))
                        }
                    }

                    group("사진 접근") {
                        HStack {
                            label("photo.on.rectangle.angled", .rose, accessTitle)
                            Spacer()
                        }
                        if app.authorization == .limited {
                            Text("일부 사진만 허용돼 있어요. 전체 사진을 검색하려면 '모든 사진'으로 바꿔 주세요.")
                                .font(.rounded(.caption))
                                .foregroundStyle(Color.inkSoft)
                        }
                        Button("설정 앱에서 바꾸기") { openSettings() }
                            .buttonStyle(PillButtonStyle())
                    }

                    group("개인정보") {
                        Text("사진 분석은 모두 아이폰 안에서 이뤄지고, 사진은 기기 밖으로 나가지 않아요. 지역 이름을 찾을 때만 촬영 위치 좌표를 애플 지도 서비스에 보내요.")
                            .font(.rounded(.footnote))
                            .foregroundStyle(Color.ink)
                    }

                    group("색인") {
                        Button(role: .destructive) {
                            confirmReset = true
                        } label: {
                            label("arrow.counterclockwise", .peach, "색인 초기화하고 다시 분석")
                        }
                        Text("사진에는 아무 영향이 없어요.")
                            .font(.rounded(.caption))
                            .foregroundStyle(Color.inkSoft)
                    }

                    Text("피크닉 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                        .font(.rounded(.caption))
                        .foregroundStyle(Color.inkSoft)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .background(Color.cream.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .confirmationDialog("색인을 지우고 처음부터 다시 분석할까요?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("초기화", role: .destructive) {
                app.indexer.reset()
                app.activate()
                refresh()
            }
        }
        .task(id: app.indexer.revision) { refresh() }
    }

    private var progressCard: some View {
        let progress = app.indexer.progress
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                label("sparkles", .rose, "사진 분석")
                Spacer()
                Text(statusText)
                    .font(.rounded(.caption, weight: .semibold))
                    .foregroundStyle(Color.rose)
            }
            ProgressView(value: progress.fraction).tint(.rose)
            Text("\(Format.count(progress.total))장 중 \(Format.count(progress.analyzed))장을 살펴봤어요")
                .font(.rounded(.footnote))
                .foregroundStyle(Color.inkSoft)
        }
        .card()
    }

    private var statusText: String {
        switch app.indexer.phase {
        case .syncing, .measuring: return "준비 중"
        case .analyzing: return "분석 중"
        case .pausedHot: return "잠깐 쉬는 중"
        case .done: return "완료"
        case .idle: return app.indexer.progress.isComplete ? "완료" : "대기 중"
        }
    }

    private var accessTitle: String {
        switch app.authorization {
        case .authorized: return "모든 사진 허용됨"
        case .limited: return "일부 사진만 허용됨"
        default: return "허용되지 않음"
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.rounded(.subheadline, weight: .bold))
                .foregroundStyle(Color.inkSoft)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 16, radius: 20)
        }
    }

    private func label(_ symbol: String, _ tint: Color, _ text: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.opacity(0.18))
                    .frame(width: 32, height: 32)
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(text)
                .font(.rounded(.subheadline, weight: .medium))
                .foregroundStyle(Color.ink)
        }
    }

    private func row(_ symbol: String, _ tint: Color, _ text: String, value: String) -> some View {
        HStack {
            label(symbol, tint, text)
            Spacer()
            Text(value)
                .font(.rounded(.subheadline))
                .foregroundStyle(Color.inkSoft)
        }
    }

    private func refresh() {
        indexBytes = app.indexFileBytes
        exclusions = (try? app.store.exclusionCount()) ?? 0
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
