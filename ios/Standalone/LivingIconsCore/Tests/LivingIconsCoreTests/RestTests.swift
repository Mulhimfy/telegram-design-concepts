import XCTest
import Foundation
import CoreGraphics
@testable import LivingIconsCore

/// At rest, every icon's parts cover exactly Telegram's own glyph (Telegram-iOS f1dd7a2, tools/telegram-glyphs.mjs):
/// the layers that play in place of the static icon start and end as that icon. Both are drawn with CoreGraphics at
/// 4 px per pt — the parts as the layer view stacks them (clips, cut-outs as holes, the stroke a shape is revealed
/// under) — and compared pixel by pixel. Antialiasing differs only where two parts overlap at an edge.
final class RestTests: XCTestCase {
    static let scale = 4
    static let side = 30 * RestTests.scale
    /// A pixel differs when its coverage differs by more than 0.3; a few may, where parts overlap at an edge.
    static let differing = 77
    static let maxDiffering = 16
    static let maxMeanDifference = 0.75

    static let telegram: [String: [String: Any]] = {
        let url = Bundle.module.url(forResource: "telegram-glyphs", withExtension: "json")!
        let data = try! Data(contentsOf: url)
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        return json["glyphs"] as! [String: [String: Any]]
    }()

    /// The coverage (alpha) of what `draw` paints in white, in the y-down 30 × 30 icon space.
    private func render(_ draw: (CGContext) -> Void) -> [UInt8] {
        let side = RestTests.side
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return
            }
            context.translateBy(x: 0.0, y: CGFloat(side))
            context.scaleBy(x: CGFloat(RestTests.scale), y: -CGFloat(RestTests.scale))
            context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))
            context.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))
            draw(context)
        }
        return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
    }

    /// The tree at rest, as LivingSettingsIconLayer stacks it.
    private func draw(_ nodes: [LivingIconNode], in context: CGContext) {
        for node in nodes {
            switch node {
            case let .group(_, children), let .typingDot(_, children):
                self.draw(children, in: context)
            case let .shape(shape):
                if shape.ref == .shine {
                    // Drawn on by its rig; nothing at rest.
                    continue
                }
                context.saveGState()
                if let clip = shape.clip {
                    context.addPath(clip.makePath())
                    context.clip()
                }
                if let reveal = shape.reveal {
                    context.addPath(reveal.path.makePath())
                    context.setLineWidth(CGFloat(reveal.width))
                    context.setLineCap(.butt)
                    context.replacePathWithStrokedPath()
                    context.clip()
                }
                context.addPath(shape.geometry.makePath())
                if let stroke = shape.stroke {
                    context.setLineWidth(CGFloat(stroke))
                    context.setLineCap(shape.roundCap ? .round : .butt)
                    context.setLineJoin(.miter)
                    context.setMiterLimit(4.0)
                    context.strokePath()
                } else {
                    context.fillPath(using: shape.evenOdd ? .evenOdd : .winding)
                }
                context.restoreGState()
            case let .clipped(geometry, children):
                context.saveGState()
                context.addPath(geometry.makePath())
                context.clip()
                self.draw(children, in: context)
                context.restoreGState()
            case let .cutout(white, holes):
                self.draw(white, in: context)
                context.saveGState()
                context.setBlendMode(.clear)
                self.draw(holes, in: context)
                context.restoreGState()
            case .paper:
                // Hidden until the folder opens.
                break
            case let .turningGlobe(rest):
                // At rest the glyph itself (the turning globe is faded out).
                self.draw(rest, in: context)
            }
        }
    }

    private func telegramGlyph(_ name: String) -> [UInt8]? {
        guard let paths = RestTests.telegram[name]?["paths"] as? [[String: Any]] else {
            return nil
        }
        return self.render { context in
            for path in paths {
                context.addPath(LivingIconPath.path(path["d"] as! String))
                if let stroke = path["stroke"] as? Double {
                    context.setLineWidth(CGFloat(stroke))
                    context.strokePath()
                } else {
                    context.fillPath(using: (path["evenOdd"] as? Bool ?? false) ? .evenOdd : .winding)
                }
            }
        }
    }

    func testEveryIconAtRestIsTelegramsGlyph() {
        var report: [String] = []
        for name in LivingIconRigs.all.keys.sorted() {
            guard let tree = LivingIconArtwork.tree(name) else {
                // Money turns the row's own image.
                XCTAssertEqual(name, "money")
                continue
            }
            guard let expected = self.telegramGlyph(name) else {
                XCTFail("\(name): no Telegram glyph")
                continue
            }
            let actual = self.render { context in
                self.draw(tree, in: context)
            }
            var differing = 0
            var total = 0
            for (a, e) in zip(actual, expected) {
                let d = abs(Int(a) - Int(e))
                total += d
                if d > RestTests.differing {
                    differing += 1
                }
            }
            let mean = Double(total) / Double(actual.count)
            report.append("\(name): \(differing) px differ, mean \(String(format: "%.3f", mean))")
            XCTAssertLessThanOrEqual(differing, RestTests.maxDiffering, "\(name): \(differing) pixels differ from Telegram's glyph")
            XCTAssertLessThan(mean, RestTests.maxMeanDifference, "\(name): mean difference \(mean)")
            // And it is not empty: the glyph covers a good part of the icon.
            XCTAssertGreaterThan(expected.reduce(0) { $0 + Int($1) }, 255 * RestTests.side * RestTests.side / 20, name)
        }
        print(report.joined(separator: "\n"))
    }
}
