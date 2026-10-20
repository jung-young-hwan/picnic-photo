import CoreGraphics
import Foundation

/// 이미지에서 선명도와 지문(dHash)을 계산하는 순수 함수 모음.
enum ImageMath {
    /// 긴 변이 `maxSide` 이하가 되도록 비율을 유지해 줄인 크기.
    static func fittedSize(width: Int, height: Int, maxSide: Int) -> (width: Int, height: Int) {
        let longest = max(width, height)
        guard longest > maxSide else { return (width, height) }
        let scale = Double(maxSide) / Double(longest)
        return (max(1, Int(Double(width) * scale)), max(1, Int(Double(height) * scale)))
    }

    /// 이미지를 지정한 크기의 8비트 흑백 픽셀 배열로 그린다.
    static func grayscalePixels(_ image: CGImage, width: Int, height: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBytes { buffer in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return pixels
    }

    /// 선명도 = 라플라시안 응답의 분산. 값이 작을수록 흐린 사진이다.
    /// 크기에 따라 값이 달라지므로 항상 긴 변 `maxSide` 로 맞춰 계산한다.
    static func sharpness(of image: CGImage, maxSide: Int = 512) -> Double {
        let size = fittedSize(width: image.width, height: image.height, maxSide: maxSide)
        let w = size.width
        let h = size.height
        guard w >= 3, h >= 3 else { return 0 }
        let p = grayscalePixels(image, width: w, height: h)

        var sum = 0.0
        var sumSquares = 0.0
        var count = 0.0
        p.withUnsafeBufferPointer { px in
            for y in 1..<(h - 1) {
                let row = y * w
                for x in 1..<(w - 1) {
                    let i = row + x
                    let center = 4 * Int(px[i])
                    let neighbors = Int(px[i - 1]) + Int(px[i + 1]) + Int(px[i - w]) + Int(px[i + w])
                    let v = Double(center - neighbors)
                    sum += v
                    sumSquares += v * v
                    count += 1
                }
            }
        }
        let mean = sum / count
        return sumSquares / count - mean * mean
    }

    /// 64비트 차이 해시. 9×8 로 줄인 뒤 가로로 이웃한 픽셀의 밝기 차이를 비트로 기록한다.
    static func dHash(of image: CGImage) -> UInt64 {
        let p = grayscalePixels(image, width: 9, height: 8)
        var hash: UInt64 = 0
        var bit: UInt64 = 0
        for y in 0..<8 {
            for x in 0..<8 {
                if p[y * 9 + x] < p[y * 9 + x + 1] {
                    hash |= (1 << bit)
                }
                bit += 1
            }
        }
        return hash
    }

    static func hamming(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }
}
