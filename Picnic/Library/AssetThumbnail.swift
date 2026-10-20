import SwiftUI

/// PhotoKit 미리보기 이미지. 직접 저장하지 않고 사진 앱의 캐시를 빌려 쓴다.
struct AssetThumbnail: View {
    var id: String
    var pixelSize: CGFloat
    var contentMode: ContentMode = .fill
    var highQuality = false

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.roseSoft.opacity(0.5)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            }
        }
        .task(id: id) {
            image = nil
            let size = CGSize(width: pixelSize, height: pixelSize)
            for await next in PhotoLibrary.shared.images(id: id, targetSize: size, highQuality: highQuality) {
                image = next
            }
        }
    }
}
