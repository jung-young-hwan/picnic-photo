import Photos
import UIKit

/// PhotoKit 접근을 한곳에 모은다. 다른 모듈은 PhotoKit 을 직접 쓰지 않는다.
final class PhotoLibrary: NSObject, PHPhotoLibraryChangeObserver, @unchecked Sendable {
    static let shared = PhotoLibrary()

    let imageManager = PHCachingImageManager()
    /// 라이브러리가 바뀌면 호출된다 (메인 스레드 아님).
    var onChange: (@Sendable () -> Void)?
    private var registered = false

    // MARK: - 권한

    var authorizationStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    func startObserving() {
        guard !registered else { return }
        registered = true
        PHPhotoLibrary.shared().register(self)
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        onChange?()
    }

    // MARK: - 메타데이터

    /// 사진·동영상 전체의 메타데이터 (최신순). 파일 크기는 0 으로 두고 나중에 채운다.
    func fetchAllMetadata() -> [AssetMetadata] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(
            format: "mediaType == %d OR mediaType == %d",
            PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        let result = PHAsset.fetchAssets(with: options)
        var items: [AssetMetadata] = []
        items.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            items.append(Self.metadata(of: asset))
        }
        return items
    }

    static func metadata(of asset: PHAsset) -> AssetMetadata {
        let coordinate = asset.location?.coordinate
        let hasLocation = coordinate.map { CLLocationCoordinate2DIsValid($0) && ($0.latitude != 0 || $0.longitude != 0) } ?? false
        return AssetMetadata(
            id: asset.localIdentifier,
            mediaType: asset.mediaType == .video ? .video : .image,
            createdAt: asset.creationDate,
            lat: hasLocation ? coordinate?.latitude : nil,
            lon: hasLocation ? coordinate?.longitude : nil,
            isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
            fileSize: 0,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            duration: asset.duration)
    }

    /// 에셋의 파일 크기 (원본 + 라이브 포토 영상 등 딸린 파일 합계).
    /// PhotoKit 에 공개된 크기 API 가 없어 리소스의 fileSize 값을 읽고, 없으면 해상도로 추정한다.
    func fileSizes(ids: [String]) -> [String: Int64] {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var sizes: [String: Int64] = [:]
        assets.enumerateObjects { asset, _, _ in
            var total: Int64 = 0
            for resource in PHAssetResource.assetResources(for: asset) {
                if let size = resource.value(forKey: "fileSize") as? Int64 {
                    total += size
                } else if let size = resource.value(forKey: "fileSize") as? Int {
                    total += Int64(size)
                }
            }
            if total <= 0 {
                total = Self.estimatedSize(of: asset)
            }
            sizes[asset.localIdentifier] = max(1, total)
        }
        // 라이브러리에서 사라진 ID 는 1 로 표시해 다시 묻지 않는다
        for id in ids where sizes[id] == nil { sizes[id] = 1 }
        return sizes
    }

    static func estimatedSize(of asset: PHAsset) -> Int64 {
        if asset.mediaType == .video {
            let bytesPerSecond: Double = asset.pixelWidth * asset.pixelHeight > 2_500_000 ? 6_000_000 : 2_200_000
            return Int64(asset.duration * bytesPerSecond)
        }
        return Int64(Double(asset.pixelWidth * asset.pixelHeight) * 0.25)
    }

    // MARK: - 이미지

    /// 분석용 이미지 (긴 변 maxSide). iCloud 에 있으면 작은 미리보기를 받는다.
    func analysisImage(id: String, maxSide: CGFloat) async -> CGImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            return nil
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        let target = CGSize(width: maxSide, height: maxSide)
        let image: UIImage? = await withCheckedContinuation { continuation in
            imageManager.requestImage(for: asset, targetSize: target, contentMode: .aspectFit, options: options) {
                image, _ in
                continuation.resume(returning: image)
            }
        }
        return image.flatMap(Self.uprightCGImage)
    }

    /// 회전 정보가 있는 이미지를 똑바로 선 CGImage 로 만든다 (글자 인식에 필요).
    static func uprightCGImage(_ image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cg = image.cgImage { return cg }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }.cgImage
    }

    /// 화면 표시용 이미지. 저화질 → 고화질 순으로 여러 번 전달될 수 있다.
    func images(id: String, targetSize: CGSize, highQuality: Bool = false) -> AsyncStream<UIImage> {
        AsyncStream { continuation in
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
                continuation.finish()
                return
            }
            let options = PHImageRequestOptions()
            options.deliveryMode = highQuality ? .highQualityFormat : .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            let requestID = imageManager.requestImage(
                for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options
            ) { image, info in
                if let image { continuation.yield(image) }
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !degraded { continuation.finish() }
            }
            continuation.onTermination = { [imageManager] _ in
                imageManager.cancelImageRequest(requestID)
            }
        }
    }

    // MARK: - 삭제

    enum DeleteOutcome {
        case deleted
        case cancelled
    }

    /// 시스템 확인 창을 띄운 뒤 삭제한다. 삭제된 사진은 '최근 삭제된 항목'으로 간다.
    func delete(ids: [String]) async throws -> DeleteOutcome {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        guard assets.count > 0 else { return .deleted }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            return .deleted
        } catch let error as NSError {
            if error.domain == PHPhotosErrorDomain, error.code == PHPhotosError.userCancelled.rawValue {
                return .cancelled
            }
            // 일부 iOS 버전은 취소 시 Cocoa 오류 3072 를 돌려준다
            if error.domain == NSCocoaErrorDomain, error.code == 3072 {
                return .cancelled
            }
            throw error
        }
    }
}
