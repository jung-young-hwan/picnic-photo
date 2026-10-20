import Photos
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch app.authorization {
            case .authorized, .limited:
                MainTabView()
            case .notDetermined:
                WelcomeScreen()
            default:
                PermissionDeniedScreen()
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: app.activate()
            case .background: app.deactivate()
            default: break
            }
        }
        .onChange(of: app.indexer.isWorking) { app.updateIdleTimer() }
    }
}

struct MainTabView: View {
    @State private var tab = DemoHooks.initialTab

    var body: some View {
        TabView(selection: $tab) {
            Tab("검색", systemImage: "magnifyingglass", value: 0) {
                SearchScreen()
            }
            Tab("정리", systemImage: "sparkles", value: 1) {
                CleanupHomeScreen()
            }
            Tab("설정", systemImage: "gearshape.fill", value: 2) {
                SettingsScreen()
            }
        }
        .tint(.rose)
    }
}

/// 첫 실행 화면.
struct WelcomeScreen: View {
    @Environment(AppModel.self) private var app
    @State private var appear = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)
            illustration
                .scaleEffect(appear ? 1 : 0.85)
                .opacity(appear ? 1 : 0)
            VStack(spacing: 10) {
                Text("사진 정리,\n이제 가볍게")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(Color.ink)
                Text("피크닉이 사진을 살펴보고\n찾기 쉽게, 비우기 쉽게 도와드려요")
                    .font(.rounded(.body))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(Color.inkSoft)
            }
            VStack(alignment: .leading, spacing: 14) {
                feature("magnifyingglass", .rose, "한국어로 찾기", "강아지, 제주 바다, 영수증 글자까지")
                feature("sparkles", .lavender, "흐리고 비슷한 사진 정리", "지울 만한 사진을 골라 모아 드려요")
                feature("lock.fill", .sage, "사진은 기기 안에만", "분석은 모두 아이폰 안에서 해요")
            }
            .card(padding: 18, radius: 24)
            .padding(.horizontal, 24)
            Spacer(minLength: 8)
            Button {
                Task { await app.requestAccess() }
            } label: {
                Text("사진 연결하기")
                    .font(.rounded(.headline, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(Color.rose))
                    .shadow(color: Color.rose.opacity(0.4), radius: 14, y: 6)
            }
            .buttonStyle(SoftPressStyle())
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cream.ignoresSafeArea())
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { appear = true }
        }
    }

    private var illustration: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.lavenderSoft)
                .frame(width: 110, height: 130)
                .rotationEffect(.degrees(12))
                .offset(x: 26, y: 4)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.card)
                .frame(width: 110, height: 130)
                .overlay(
                    Image(systemName: "photo.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.rose)
                )
                .shadow(color: Color.rose.opacity(0.25), radius: 14, y: 8)
                .rotationEffect(.degrees(-6))
            Image(systemName: "sparkle")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.butter)
                .offset(x: 78, y: -74)
            Image(systemName: "heart.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color.rose)
                .offset(x: -72, y: 64)
        }
        .scaleEffect(0.85)
        .frame(height: 150)
    }

    private func feature(_ symbol: String, _ tint: Color, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(tint.opacity(0.18)).frame(width: 40, height: 40)
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.rounded(.subheadline, weight: .bold))
                    .foregroundStyle(Color.ink)
                Text(detail)
                    .font(.rounded(.caption))
                    .foregroundStyle(Color.inkSoft)
            }
        }
    }
}

/// 사진 접근을 거부했을 때.
struct PermissionDeniedScreen: View {
    var body: some View {
        VStack(spacing: 20) {
            EmptyState(
                symbol: "photo.badge.exclamationmark", title: "사진에 접근할 수 없어요",
                message: "설정 앱 → 피크닉 → 사진에서\n'모든 사진'을 허용해 주세요.")
            Button("설정 열기") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(PillButtonStyle(filled: true))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cream.ignoresSafeArea())
    }
}
