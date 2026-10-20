import Foundation
import Observation
import Photos
import UIKit

/// 앱 전체에서 함께 쓰는 객체와 설정.
@MainActor
@Observable
final class AppModel {
    let store: AssetStore
    let library: PhotoLibrary
    let indexer: Indexer
    let search: SearchService
    let cleanup: CleanupService
    let analyzer = VisionAnalyzer()

    private(set) var authorization: PHAuthorizationStatus
    /// 지금까지 앱에서 비운 용량
    private(set) var freedBytes: Int64
    private(set) var recentSearches: [String]
    var keepScreenOn: Bool {
        didSet {
            UserDefaults.standard.set(keepScreenOn, forKey: Keys.keepScreenOn)
            updateIdleTimer()
        }
    }

    private enum Keys {
        static let freedBytes = "freedBytes"
        static let recentSearches = "recentSearches"
        static let keepScreenOn = "keepScreenOn"
    }

    init() {
        let store: AssetStore
        do {
            store = AssetStore(writer: try AppDatabase.openFile())
        } catch {
            // 색인 파일이 깨졌으면 지우고 새로 만든다 (사진에는 영향 없음)
            try? FileManager.default.removeItem(at: AppDatabase.fileURL)
            store = (try? AssetStore(writer: AppDatabase.openFile())) ?? (try! AssetStore.inMemory())
        }
        let library = PhotoLibrary.shared
        self.store = store
        self.library = library
        indexer = Indexer(store: store, library: library)
        search = SearchService(store: store, lexicon: .shared)
        cleanup = CleanupService(store: store)
        authorization = library.authorizationStatus

        let defaults = UserDefaults.standard
        defaults.register(defaults: [Keys.keepScreenOn: true])
        freedBytes = Int64(defaults.integer(forKey: Keys.freedBytes))
        recentSearches = defaults.stringArray(forKey: Keys.recentSearches) ?? []
        keepScreenOn = defaults.bool(forKey: Keys.keepScreenOn)

        library.onChange = { [weak self] in
            Task { @MainActor in self?.indexer.libraryChanged() }
        }
    }

    var hasAccess: Bool { authorization == .authorized || authorization == .limited }

    func requestAccess() async {
        authorization = await library.requestAuthorization()
        if hasAccess { activate() }
    }

    func refreshAuthorization() {
        authorization = library.authorizationStatus
    }

    /// 앱이 화면에 나올 때.
    func activate() {
        refreshAuthorization()
        guard hasAccess else { return }
        library.startObserving()
        indexer.start()
        updateIdleTimer()
    }

    /// 앱이 백그라운드로 갈 때.
    func deactivate() {
        indexer.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = keepScreenOn && indexer.isWorking
    }

    // MARK: - 삭제

    /// 시스템 확인 후 삭제. 비운 용량을 돌려준다 (취소하면 nil).
    func delete(ids: [String], bytes: Int64) async throws -> Int64? {
        guard !ids.isEmpty else { return nil }
        switch try await library.delete(ids: ids) {
        case .cancelled:
            return nil
        case .deleted:
            indexer.didDelete(ids: ids)
            freedBytes += bytes
            UserDefaults.standard.set(Int(freedBytes), forKey: Keys.freedBytes)
            return bytes
        }
    }

    func exclude(ids: [String]) {
        try? store.exclude(ids: ids)
    }

    // MARK: - 최근 검색어

    func remember(search query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        recentSearches.removeAll { $0 == trimmed }
        recentSearches.insert(trimmed, at: 0)
        recentSearches = Array(recentSearches.prefix(10))
        UserDefaults.standard.set(recentSearches, forKey: Keys.recentSearches)
    }

    func clearRecentSearches() {
        recentSearches = []
        UserDefaults.standard.removeObject(forKey: Keys.recentSearches)
    }

    // MARK: - 비슷한 사진 정밀 비교

    /// 두 사진이 비슷한지 Vision 특징 벡터로 판정한다.
    nonisolated func isSimilar(_ a: String, _ b: String) async -> Bool? {
        let library = PhotoLibrary.shared
        async let imageA = library.analysisImage(id: a, maxSide: 360)
        async let imageB = library.analysisImage(id: b, maxSide: 360)
        guard let first = await imageA, let second = await imageB else { return nil }
        guard let distance = try? VisionAnalyzer().featureDistance(first, second) else { return nil }
        return distance <= 0.4
    }

    // MARK: - 저장 공간

    /// 앱이 쓰는 색인 파일 크기.
    var indexFileBytes: Int64 {
        let base = AppDatabase.fileURL.path
        return ["", "-wal", "-shm"].reduce(Int64(0)) { total, suffix in
            let attributes = try? FileManager.default.attributesOfItem(atPath: base + suffix)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            return total + size
        }
    }
}
