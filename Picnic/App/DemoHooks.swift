import Foundation

/// 개발용 화면 캡처를 위한 시작 옵션 (Debug 빌드에서만 동작).
/// 예) 실행 인자 `-PicnicInitialTab 1 -PicnicDemoCategory similar`
enum DemoHooks {
    static var initialTab: Int {
        #if DEBUG
        return UserDefaults.standard.integer(forKey: "PicnicInitialTab")
        #else
        return 0
        #endif
    }

    static var query: String? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "PicnicDemoQuery")
        #else
        return nil
        #endif
    }

    static var category: CleanupCategory? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "PicnicDemoCategory").flatMap(CleanupCategory.init(rawValue:))
        #else
        return nil
        #endif
    }
}
