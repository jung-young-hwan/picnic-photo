import CoreGraphics
import OSLog
import Vision

let analysisLog = Logger(subsystem: "com.jungyounghwan.picnic", category: "analysis")

/// Vision 으로 사진 1장을 분석한다. 모든 처리는 기기 안에서 이뤄진다.
struct VisionAnalyzer: Sendable {
    /// 분석 알고리즘이 바뀌면 올린다. 낮은 버전으로 분석된 사진은 다시 분석된다.
    static let version = 1
    /// 분석 이미지 긴 변 (글자 인식을 위해 선명도 계산보다 크게 받는다)
    static let imageSide: CGFloat = 1024

    var labelLimit = 10
    var minLabelConfidence: Float = 0.3

    func analyze(_ image: CGImage) throws -> AnalysisResult {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        let classify = VNClassifyImageRequest()
        let quickText = VNRecognizeTextRequest()
        quickText.recognitionLevel = .fast
        quickText.usesLanguageCorrection = false
        try handler.perform([classify, quickText])

        let observations = classify.results ?? []
        let labels = observations
            .filter { $0.confidence >= minLabelConfidence && $0.hasMinimumRecall(0.01, forPrecision: 0.8) }
            .sorted { $0.confidence > $1.confidence }
            .prefix(labelLimit)
            .map { LabelScore(keyword: $0.identifier, confidence: Double($0.confidence)) }
        #if DEBUG
        let top = observations.sorted { $0.confidence > $1.confidence }.prefix(6)
            .map { "\($0.identifier)=\(String(format: "%.2f", $0.confidence))\($0.hasMinimumRecall(0.01, forPrecision: 0.8) ? "*" : "")" }
            .joined(separator: " ")
        analysisLog.notice("classify \(observations.count) kept \(labels.count): \(top, privacy: .public)")
        #endif

        // 글자가 있을 때만 한국어 정밀 인식을 한다 (느리기 때문)
        var ocrText: String?
        if let found = quickText.results, !found.isEmpty {
            let accurate = VNRecognizeTextRequest()
            accurate.recognitionLevel = .accurate
            accurate.recognitionLanguages = ["ko-KR", "en-US"]
            accurate.usesLanguageCorrection = true
            try handler.perform([accurate])
            let lines = (accurate.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            let joined = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            ocrText = joined.isEmpty ? nil : joined
        }

        // 미적 점수는 지원하지 않는 환경(시뮬레이터 등)에서 실패할 수 있어 따로 돌린다
        var aesthetic: Double?
        var isUtility: Bool?
        let aesthetics = VNCalculateImageAestheticsScoresRequest()
        if (try? handler.perform([aesthetics])) != nil,
            let observation = aesthetics.results?.first
        {
            aesthetic = Double(observation.overallScore)
            isUtility = observation.isUtility
        }

        return AnalysisResult(
            labels: Array(labels), ocrText: ocrText, sharpness: ImageMath.sharpness(of: image),
            aesthetic: aesthetic, isUtility: isUtility, dhash: ImageMath.dHash(of: image))
    }

    /// 두 이미지의 특징 벡터 거리. 작을수록 비슷하다.
    func featureDistance(_ a: CGImage, _ b: CGImage) throws -> Float {
        let printA = try featurePrint(a)
        let printB = try featurePrint(b)
        var distance: Float = 0
        try printA.computeDistance(&distance, to: printB)
        return distance
    }

    private func featurePrint(_ image: CGImage) throws -> VNFeaturePrintObservation {
        let request = VNGenerateImageFeaturePrintRequest()
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        guard let observation = request.results?.first else {
            throw VisionError.noResult
        }
        return observation
    }

    enum VisionError: Error {
        case noResult
    }
}
