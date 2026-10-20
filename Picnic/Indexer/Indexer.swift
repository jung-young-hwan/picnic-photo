import Foundation
import Observation
import OSLog
import UIKit

let indexLog = Logger(subsystem: "com.jungyounghwan.picnic", category: "indexer")

/// 라이브러리 동기화 → 사진 분석 → 지명 변환을 차례로 진행한다.
/// 앱이 화면에 있는 동안만 돌고, 다시 켜면 이어서 한다.
@MainActor
@Observable
final class Indexer {
    enum Phase: Equatable {
        case idle
        case syncing
        case measuring
        case analyzing
        case pausedHot
        case done
    }

    private(set) var phase: Phase = .idle
    private(set) var progress = AnalysisProgress(analyzed: 0, total: 0)
    /// 색인 내용이 바뀔 때마다 올라간다. 화면은 이 값을 보고 새로 고친다.
    private(set) var revision = 0

    private let store: AssetStore
    private let library: PhotoLibrary
    private let analyzer = VisionAnalyzer()
    private let places = PlaceResolver()
    private var mainTask: Task<Void, Never>?
    private var placeTask: Task<Void, Never>?
    private var needsResync = false

    init(store: AssetStore, library: PhotoLibrary) {
        self.store = store
        self.library = library
    }

    var isWorking: Bool {
        switch phase {
        case .syncing, .measuring, .analyzing, .pausedHot: return true
        case .idle, .done: return false
        }
    }

    func start() {
        guard mainTask == nil else {
            needsResync = true
            return
        }
        let runID = UUID()
        currentRun = runID
        mainTask = Task { [weak self] in
            await self?.run()
            if self?.currentRun == runID { self?.mainTask = nil }
        }
        if placeTask == nil {
            placeTask = Task { [weak self] in
                await self?.resolvePlaces()
                if self?.currentRun == runID { self?.placeTask = nil }
            }
        }
    }

    /// 앱이 백그라운드로 갈 때. 지금 하던 사진까지만 마치고 멈춘다.
    func stop() {
        currentRun = nil
        mainTask?.cancel()
        placeTask?.cancel()
        mainTask = nil
        placeTask = nil
        if phase != .done { phase = .idle }
    }

    private var currentRun: UUID?

    /// 라이브러리가 바뀌었을 때 (새 사진, 삭제 등).
    func libraryChanged() {
        if mainTask == nil {
            start()
        } else {
            needsResync = true
        }
    }

    /// 앱에서 사진을 지운 직후 색인에서도 바로 뺀다.
    func didDelete(ids: [String]) {
        try? store.removeAssets(ids: ids)
        refreshProgress()
        revision += 1
    }

    func reset() {
        stop()
        try? store.resetAll()
        progress = AnalysisProgress(analyzed: 0, total: 0)
        phase = .idle
        revision += 1
    }

    // MARK: - 진행

    private func run() async {
        repeat {
            needsResync = false
            phase = .syncing
            indexLog.notice("sync start")
            await sync()
            indexLog.notice("sync done")
            if Task.isCancelled { return }
            phase = .measuring
            await measureFileSizes()
            indexLog.notice("measure done")
            if Task.isCancelled { return }
            phase = .analyzing
            await analyzeAll()
            if Task.isCancelled { return }
        } while needsResync
        phase = .done
        revision += 1
    }

    private func sync() async {
        let store = self.store
        let library = self.library
        await Task.detached(priority: .utility) {
            let metadata = library.fetchAllMetadata()
            for start in stride(from: 0, to: metadata.count, by: 1000) {
                try? store.upsertMetadata(Array(metadata[start..<min(start + 1000, metadata.count)]))
            }
            _ = try? store.removeAssets(notIn: Set(metadata.map(\.id)))
        }.value
        refreshProgress()
        revision += 1
    }

    private func measureFileSizes() async {
        let store = self.store
        let library = self.library
        while !Task.isCancelled {
            let done = await Task.detached(priority: .utility) { () -> Bool in
                guard let ids = try? store.idsMissingFileSize(limit: 300), !ids.isEmpty else { return true }
                indexLog.notice("measure batch \(ids.count)")
                let sizes = library.fileSizes(ids: ids)
                indexLog.notice("measured \(sizes.count) total \(sizes.values.reduce(0, +))")
                do {
                    try store.saveFileSizes(sizes)
                } catch {
                    indexLog.error("save sizes failed \(String(describing: error), privacy: .public)")
                    return true
                }
                return false
            }.value
            if done { break }
        }
        revision += 1
    }

    private func analyzeAll() async {
        let version = VisionAnalyzer.version
        var batches = 0
        while !Task.isCancelled {
            if ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue {
                phase = .pausedHot
                try? await Task.sleep(for: .seconds(30))
                continue
            }
            phase = .analyzing
            guard let ids = try? store.pendingAnalysisIDs(version: version, limit: 8), !ids.isEmpty else { break }

            // 2장씩 동시에 분석한다
            for start in stride(from: 0, to: ids.count, by: 2) {
                if Task.isCancelled { return }
                let pair = Array(ids[start..<min(start + 2, ids.count)])
                await withTaskGroup(of: Void.self) { group in
                    for id in pair {
                        group.addTask { [store, library, analyzer] in
                            await Self.analyze(id: id, store: store, library: library, analyzer: analyzer, version: version)
                        }
                    }
                }
            }
            refreshProgress()
            indexLog.notice("analyzed \(self.progress.analyzed) / \(self.progress.total)")
            batches += 1
            if batches % 5 == 0 { revision += 1 }
        }
        refreshProgress()
        revision += 1
    }

    private nonisolated static func analyze(
        id: String, store: AssetStore, library: PhotoLibrary, analyzer: VisionAnalyzer, version: Int
    ) async {
        guard let image = await library.analysisImage(id: id, maxSide: VisionAnalyzer.imageSide) else {
            try? store.markAnalysisFailed(id: id)
            return
        }
        do {
            let result = try analyzer.analyze(image)
            try store.saveAnalysis(id: id, result: result, version: version)
            indexLog.debug("labels \(result.labels.count) text \(result.ocrText?.count ?? 0) utility \(String(describing: result.isUtility))")
        } catch {
            try? store.markAnalysisFailed(id: id)
        }
    }

    private func resolvePlaces() async {
        while !Task.isCancelled {
            guard let tasks = try? store.pendingPlaceTasks(limit: 20), !tasks.isEmpty else {
                // 동기화가 아직이면 잠시 뒤 다시 본다
                if phase == .syncing || phase == .idle {
                    try? await Task.sleep(for: .seconds(5))
                    continue
                }
                return
            }
            for task in tasks {
                if Task.isCancelled { return }
                switch await places.resolve(lat: task.lat, lon: task.lon) {
                case .resolved(let info):
                    try? store.savePlace(gridKey: task.gridKey, info: info)
                case .retryLater:
                    // 인터넷이 없거나 제한에 걸림 → 이번 실행에서는 그만
                    return
                }
                try? await Task.sleep(for: places.interval)
            }
            revision += 1
        }
    }

    private func refreshProgress() {
        if let value = try? store.analysisProgress(version: VisionAnalyzer.version) {
            progress = value
        }
    }
}
