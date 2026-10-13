import Foundation
import CoreGraphics

// Money's icon is a bitmap (Telegram-iOS "Settings/Gram": a flat-coloured gem with a white sparkle), while the
// money rig turns the sparkle on its own (`E.inner`, living-icons.js `RIGS.money`). This splits the bitmap into
// the gem (the sparkle's pixels filled with the gem's colour) and the sparkle (white, with the coverage it had),
// so that the sparkle drawn over the gem is exactly the bitmap again. Pure CoreGraphics. (The prototype draws the
// same two images, split the same way by tools/telegram-money.mjs.)

public enum LivingIconImageSplit {
    public struct Result {
        /// The image without its sparkle.
        public let base: CGImage
        /// The sparkle: white, premultiplied by its coverage.
        public let sparkle: CGImage
        /// The sparkle's centre (coverage-weighted), in pixels from the top-left.
        public let center: CGPoint
    }

    /// Splits a flat-coloured shape with a white mark on it. Every opaque pixel is the shape's colour mixed with
    /// white by a coverage `s`; the shape's colour is the commonest opaque colour. Returns nil if there is no mark.
    public static func split(_ image: CGImage) -> Result? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, width * height <= 1_000_000 else {
            return nil
        }
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else {
            return nil
        }

        // The shape's colour: the commonest fully opaque colour.
        var counts: [UInt32: Int] = [:]
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] == 255 {
            let key = UInt32(pixels[i]) << 16 | UInt32(pixels[i + 1]) << 8 | UInt32(pixels[i + 2])
            counts[key, default: 0] += 1
        }
        guard let shape = counts.max(by: { $0.value < $1.value })?.key else {
            return nil
        }
        let shapeColor = [Double((shape >> 16) & 0xff), Double((shape >> 8) & 0xff), Double(shape & 0xff)]
        // Measure the mix on the channel farthest from white.
        let channel = (0 ..< 3).min(by: { shapeColor[$0] < shapeColor[$1] }) ?? 0
        let span = 255.0 - shapeColor[channel]
        guard span > 32.0 else {
            return nil
        }

        var base = pixels
        var sparkle = [UInt8](repeating: 0, count: pixels.count)
        var weight = 0.0
        var sumX = 0.0
        var sumY = 0.0
        for y in 0 ..< height {
            for x in 0 ..< width {
                let i = y * bytesPerRow + x * 4
                guard pixels[i + 3] == 255 else {
                    continue
                }
                let s = max(0.0, min(1.0, (Double(pixels[i + channel]) - shapeColor[channel]) / span))
                if s <= 0.02 {
                    continue
                }
                base[i] = UInt8(shapeColor[0])
                base[i + 1] = UInt8(shapeColor[1])
                base[i + 2] = UInt8(shapeColor[2])
                let value = UInt8((s * 255.0).rounded())
                sparkle[i] = value
                sparkle[i + 1] = value
                sparkle[i + 2] = value
                sparkle[i + 3] = value
                weight += s
                sumX += s * (Double(x) + 0.5)
                sumY += s * (Double(y) + 0.5)
            }
        }
        guard weight > 1.0 else {
            return nil
        }

        func makeImage(_ bytes: [UInt8]) -> CGImage? {
            guard let provider = CGDataProvider(data: Data(bytes) as CFData) else {
                return nil
            }
            return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        }
        guard let baseImage = makeImage(base), let sparkleImage = makeImage(sparkle) else {
            return nil
        }
        return Result(base: baseImage, sparkle: sparkleImage, center: CGPoint(x: sumX / weight, y: sumY / weight))
    }
}
