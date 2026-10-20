import CoreGraphics
import XCTest
@testable import Picnic

/// 테스트용 흑백 이미지를 픽셀 함수로 만든다.
func makeImage(width: Int, height: Int, pixel: (Int, Int) -> UInt8) -> CGImage {
    var data = [UInt8](repeating: 0, count: width * height)
    for y in 0..<height {
        for x in 0..<width { data[y * width + x] = pixel(x, y) }
    }
    let provider = CGDataProvider(data: Data(data) as CFData)!
    return CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
        provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
}

/// 작게 줄였다가 다시 키워 흐리게 만든다.
func blurred(_ image: CGImage, factor: Int) -> CGImage {
    let small = CGContext(
        data: nil, width: image.width / factor, height: image.height / factor, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
    small.interpolationQuality = .high
    small.draw(image, in: CGRect(x: 0, y: 0, width: small.width, height: small.height))
    let big = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
    big.interpolationQuality = .high
    big.draw(small.makeImage()!, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return big.makeImage()!
}

final class ImageMathTests: XCTestCase {
    let checker = makeImage(width: 256, height: 256) { x, y in ((x / 8 + y / 8) % 2 == 0) ? 230 : 20 }

    func testFittedSizeKeepsAspect() {
        XCTAssertEqual(ImageMath.fittedSize(width: 4032, height: 3024, maxSide: 512).width, 512)
        XCTAssertEqual(ImageMath.fittedSize(width: 4032, height: 3024, maxSide: 512).height, 384)
        XCTAssertEqual(ImageMath.fittedSize(width: 100, height: 50, maxSide: 512).width, 100)
    }

    func testSharpImageScoresHigherThanBlurred() {
        let sharp = ImageMath.sharpness(of: checker)
        let soft = ImageMath.sharpness(of: blurred(checker, factor: 8))
        XCTAssertGreaterThan(sharp, soft * 5, "sharp=\(sharp) soft=\(soft)")
    }

    func testFlatImageHasZeroSharpness() {
        let flat = makeImage(width: 64, height: 64) { _, _ in 128 }
        XCTAssertEqual(ImageMath.sharpness(of: flat), 0, accuracy: 0.001)
    }

    func testDHashIsStableAndDiscriminates() {
        let gradient = makeImage(width: 90, height: 80) { x, _ in UInt8(x * 255 / 89) }
        let reversed = makeImage(width: 90, height: 80) { x, _ in UInt8((89 - x) * 255 / 89) }
        XCTAssertEqual(ImageMath.dHash(of: gradient), ImageMath.dHash(of: gradient))
        XCTAssertEqual(ImageMath.hamming(ImageMath.dHash(of: gradient), ImageMath.dHash(of: gradient)), 0)
        XCTAssertGreaterThan(
            ImageMath.hamming(ImageMath.dHash(of: gradient), ImageMath.dHash(of: reversed)), 50)
    }

    func testDHashToleratesResize() {
        let scene = makeImage(width: 256, height: 256) { x, y in
            UInt8((sin(Double(x) / 30) + 1) * 90 + Double(y) / 4)
        }
        let small = blurred(scene, factor: 2)
        let distance = ImageMath.hamming(ImageMath.dHash(of: scene), ImageMath.dHash(of: small))
        XCTAssertLessThanOrEqual(distance, 10)
    }
}
