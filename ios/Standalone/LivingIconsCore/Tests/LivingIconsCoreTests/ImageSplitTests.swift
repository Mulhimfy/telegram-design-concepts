import XCTest
import Foundation
import CoreGraphics
@testable import LivingIconsCore

/// Money's bitmap split into its gem and its sparkle: the sparkle drawn over the gem is the bitmap again, and the
/// sparkle's centre is found (top-left pixel coordinates, as the layer view uses it).
final class ImageSplitTests: XCTestCase {
    /// Colours in the bitmap's own (device RGB) space, so that drawing does not convert them.
    private func deviceColor(_ red: Double, _ green: Double, _ blue: Double) -> CGColor {
        return CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [CGFloat(red), CGFloat(green), CGFloat(blue), 1.0])!
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return bytes
    }

    /// A gem-like image: a rounded rect in Telegram's gem colour (48, 160, 244) with a white four-point star centred
    /// at (60, 25) from the top-left (antialiased).
    private func makeGem() -> CGImage {
        let width = 87
        let height = 73
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(self.deviceColor(48.0 / 255.0, 160.0 / 255.0, 244.0 / 255.0))
        context.addPath(CGPath(roundedRect: CGRect(x: 4.0, y: 4.0, width: 79.0, height: 65.0), cornerWidth: 12.0, cornerHeight: 12.0, transform: nil))
        context.fillPath()
        // CoreGraphics' origin is the bottom-left: 25 px from the top is y = 73 - 25.
        let center = CGPoint(x: 60.0, y: 48.0)
        let star = CGMutablePath()
        for i in 0 ..< 8 {
            let angle = Double(i) * Double.pi / 4.0
            let radius = i % 2 == 0 ? 11.0 : 3.5
            let point = CGPoint(x: center.x + CGFloat(cos(angle) * radius), y: center.y + CGFloat(sin(angle) * radius))
            if i == 0 {
                star.move(to: point)
            } else {
                star.addLine(to: point)
            }
        }
        star.closeSubpath()
        context.setFillColor(self.deviceColor(1.0, 1.0, 1.0))
        context.addPath(star)
        context.fillPath()
        return context.makeImage()!
    }

    func testSparkleOverGemIsTheImage() {
        let image = self.makeGem()
        guard let split = LivingIconImageSplit.split(image) else {
            XCTFail("no split")
            return
        }
        XCTAssertEqual(Double(split.center.x), 60.0, accuracy: 0.6)
        XCTAssertEqual(Double(split.center.y), 25.0, accuracy: 0.6)

        let original = self.pixels(image)
        let base = self.pixels(split.base)
        let sparkle = self.pixels(split.sparkle)
        var worst = 0
        var sparkled = 0
        for i in stride(from: 0, to: original.count, by: 4) {
            let alpha = Int(sparkle[i + 3])
            if alpha > 0 {
                sparkled += 1
            }
            for c in 0 ..< 4 {
                // Premultiplied source-over: sparkle + base · (1 − sparkle alpha).
                let composed = Int(sparkle[i + c]) + (Int(base[i + c]) * (255 - alpha) + 127) / 255
                worst = max(worst, abs(composed - Int(original[i + c])))
            }
        }
        XCTAssertGreaterThan(sparkled, 40, "the sparkle was found")
        XCTAssertLessThanOrEqual(worst, 3, "the sparkle over the gem is the image")
        // The gem alone has no sparkle left: where the sparkle was, it is the gem's colour (as far from the star).
        let centerIndex = (25 * image.width + 60) * 4
        let gemIndex = (36 * image.width + 20) * 4
        for c in 0 ..< 4 {
            XCTAssertEqual(Int(base[centerIndex + c]), Int(original[gemIndex + c]), accuracy: 1)
        }
        XCTAssertGreaterThan(Int(original[centerIndex]), 250, "the star is white at its centre")
    }

    func testNoMarkNoSplit() {
        let context = CGContext(data: nil, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 80, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(self.deviceColor(48.0 / 255.0, 160.0 / 255.0, 244.0 / 255.0))
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        XCTAssertNil(LivingIconImageSplit.split(context.makeImage()!))
    }
}
