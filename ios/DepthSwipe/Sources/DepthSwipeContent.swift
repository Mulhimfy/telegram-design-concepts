import Foundation
import UIKit
import CoreText
import Display

// The flat pieces Depth Swipe replaces, measured and drawn once when the rig starts — the
// measuring half of prototype/src/chats/depth.js (units(), buildTitle: "every letter where the
// browser put it", buildLines / buildAvatar: the pictures) and chat-list.js meanColor (the colour of
// the disc's rim). DepthSwipeLayers puts them on layers.

private func isJoiningScript(_ scalar: Unicode.Scalar) -> Bool {
    // depth.js JOINING: Hebrew, Arabic, Syriac… (U+0590–08FF), Indic (U+0900–0DFF), presentation forms.
    switch scalar.value {
    case 0x0590 ... 0x08FF, 0x0900 ... 0x0DFF, 0xFB1D ... 0xFDFF, 0xFE70 ... 0xFEFF:
        return true
    default:
        return false
    }
}

/// depth.js units(): grapheme clusters, or words for scripts whose letters join (splitting those
/// would break their shaping). UTF-16 ranges, whitespace included (it is skipped later).
func depthSwipeTextUnits(_ string: NSString) -> [NSRange] {
    var ranges: [NSRange] = []
    let full = NSRange(location: 0, length: string.length)
    if (string as String).unicodeScalars.contains(where: isJoiningScript) {
        var start: Int?
        var startIsSpace = false
        for i in 0 ..< string.length {
            let isSpace = CharacterSet.whitespacesAndNewlines.contains(Unicode.Scalar(string.character(at: i)) ?? " ")
            if let current = start, isSpace != startIsSpace {
                ranges.append(NSRange(location: current, length: i - current))
                start = nil
            }
            if start == nil {
                start = i
                startIsSpace = isSpace
            }
        }
        if let current = start {
            ranges.append(NSRange(location: current, length: string.length - current))
        }
    } else {
        string.enumerateSubstrings(in: full, options: .byComposedCharacterSequences) { _, range, _, _ in
            ranges.append(range)
        }
    }
    return ranges
}

/// The name, letter by letter: each letter's advance box in the title node and its cell in one
/// atlas image holding every colour a letter needs (its face, its copy in shadow and the extrusion
/// copies), so all the letter layers share a single texture.
final class DepthSwipeTitleArt {
    struct Unit {
        /// The letter's left edge and width in the title node (its advances, as the line placed it).
        let x: CGFloat
        let width: CGFloat
        /// Its cell: the left edge in the title node (on the pixel grid, so at rest the letter lands
        /// on the same pixels as the flat name), the width, and the left edge in the atlas.
        let cellLeft: CGFloat
        let cellWidth: CGFloat
        let cellX: CGFloat
    }

    /// Atlas rows: the face, its copy in shadow, then extrusion copy j = 1 … layers (front to back).
    static let faceRow = 0
    static let shadeRow = 1
    static func copyRow(_ j: Int) -> Int {
        return 1 + j
    }

    /// Room around each letter for ink outside its advance (overhangs, accents, emoji).
    static let padding = CGSize(width: 4.0, height: 3.0)

    let units: [Unit]
    let image: CGImage
    let size: CGSize
    let nodeSize: CGSize
    let rowCount: Int

    private init(units: [Unit], image: CGImage, size: CGSize, nodeSize: CGSize, rowCount: Int) {
        self.units = units
        self.image = image
        self.size = size
        self.nodeSize = nodeSize
        self.rowCount = rowCount
    }

    /// The letter's layer frame in its glyph layer (whose bounds are the letter's advance box).
    func pieceFrame(_ unit: Unit) -> CGRect {
        let padding = DepthSwipeTitleArt.padding
        return CGRect(x: unit.cellLeft - unit.x, y: -padding.height, width: unit.cellWidth, height: self.nodeSize.height + padding.height * 2.0)
    }

    /// The letter's cell in a row, in unit coordinates of the atlas (CALayer.contentsRect).
    func contentsRect(_ unit: Unit, row: Int) -> CGRect {
        let padding = DepthSwipeTitleArt.padding
        let cellHeight = self.nodeSize.height + padding.height * 2.0
        return CGRect(
            x: unit.cellX / self.size.width,
            y: CGFloat(row) * cellHeight / self.size.height,
            width: unit.cellWidth / self.size.width,
            height: cellHeight / self.size.height
        )
    }

    /// The extrusion: lit next to the face, darker toward the back (depth.js buildTitle ramp).
    static func extrusionColor(_ u: CGFloat, isDark: Bool) -> UIColor {
        let a: [CGFloat] = isDark ? [200.0, 200.0, 206.0] : [64.0, 64.0, 68.0]
        let b: [CGFloat] = isDark ? [58.0, 58.0, 62.0] : [158.0, 158.0, 164.0]
        let c = (0 ..< 3).map { i in (a[i] + (b[i] - a[i]) * u).rounded() / 255.0 }
        return UIColor(red: c[0], green: c[1], blue: c[2], alpha: 1.0)
    }

    /// Rolled away from the light the face darkens: its copy in shadow (depth.js shadeColor).
    static func shadeColor(isDark: Bool) -> UIColor {
        return isDark ? UIColor(red: 0x55 / 255.0, green: 0x55 / 255.0, blue: 0x5b / 255.0, alpha: 1.0) : UIColor(red: 0x9a / 255.0, green: 0x9a / 255.0, blue: 0xa0 / 255.0, alpha: 1.0)
    }

    /// Splits the title node's rendered line(s) — the same CTLines TextNode drew, truncation token
    /// included — into letters and draws them. nil when there is nothing to draw.
    static func make(layout: TextNodeLayout, nodeSize: CGSize, isDark: Bool) -> DepthSwipeTitleArt? {
        guard let attributedString = layout.attributedString, attributedString.length != 0, nodeSize.width > 0.0, nodeSize.height > 0.0 else {
            return nil
        }
        let string = attributedString.string as NSString
        let unitRanges = depthSwipeTextUnits(string)
        if unitRanges.isEmpty {
            return nil
        }
        var unitOfIndex = [Int](repeating: unitRanges.count - 1, count: string.length)
        for (u, range) in unitRanges.enumerated() {
            for i in range.location ..< range.location + range.length {
                unitOfIndex[i] = u
            }
        }

        var lines: [(line: CTLine, origin: CGPoint)] = []
        layout.enumerateRenderedLines(in: CGRect(origin: CGPoint(), size: nodeSize)) { line, origin in
            lines.append((line, origin))
        }

        struct Segment {
            let line: Int
            let run: CTRun
            let start: Int
            var count: Int
            let usesContextColor: Bool
            let isColorGlyphs: Bool
        }
        struct Collected {
            var segments: [Segment] = []
            var minX: CGFloat = .greatestFiniteMagnitude
            var maxX: CGFloat = -.greatestFiniteMagnitude
            var hasToken = false
        }
        var collected = [Collected](repeating: Collected(), count: unitRanges.count)
        let contextColorKey = kCTForegroundColorFromContextAttributeName as String

        for (lineIndex, entry) in lines.enumerated() {
            let runs = (CTLineGetGlyphRuns(entry.line) as [AnyObject]) as! [CTRun]
            for run in runs {
                let count = CTRunGetGlyphCount(run)
                if count == 0 {
                    continue
                }
                var indices = [CFIndex](repeating: 0, count: count)
                var positions = [CGPoint](repeating: CGPoint(), count: count)
                var advances = [CGSize](repeating: CGSize(), count: count)
                CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
                CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                CTRunGetAdvances(run, CFRange(location: 0, length: 0), &advances)
                let attributes = CTRunGetAttributes(run) as NSDictionary
                let usesContextColor = attributes[contextColorKey] != nil
                // Colour emoji keep their colours in every copy (CSS `color` does not touch them);
                // told apart as TextNode does.
                let isColorGlyphs = (attributes["NSFont"] as? UIFont)?.fontName.contains("ColorEmoji") ?? false
                var lastUnit = -1
                for k in 0 ..< count {
                    let index = indices[k]
                    let unit = index >= 0 && index < string.length ? unitOfIndex[index] : unitRanges.count - 1
                    let x0 = entry.origin.x + positions[k].x
                    let x1 = x0 + advances[k].width
                    var target = collected[unit]
                    if unit == lastUnit, var last = target.segments.popLast() {
                        last.count += 1
                        target.segments.append(last)
                    } else {
                        target.segments.append(Segment(line: lineIndex, run: run, start: k, count: 1, usesContextColor: usesContextColor, isColorGlyphs: isColorGlyphs))
                    }
                    target.minX = min(target.minX, min(x0, x1))
                    target.maxX = max(target.maxX, max(x0, x1))
                    if usesContextColor {
                        target.hasToken = true
                    }
                    collected[unit] = target
                    lastUnit = unit
                }
            }
        }

        // Letters in visual order (for left-to-right names the prototype's string order); spaces
        // are skipped as in depth.js, the truncation "…" is a letter of its own.
        var kept: [(range: NSRange, collected: Collected)] = []
        for (u, range) in unitRanges.enumerated() {
            let c = collected[u]
            if c.segments.isEmpty || c.maxX <= c.minX {
                continue
            }
            let text = string.substring(with: range)
            if !c.hasToken && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }
            kept.append((range, c))
        }
        kept.sort { $0.collected.minX < $1.collected.minX }
        if kept.isEmpty {
            return nil
        }
        if layout.truncated && !kept.contains(where: { $0.collected.hasToken }) {
            // Its "…" is drawn as an extra trailing line (a name with a line break), which the
            // rendered lines leave out: the flat name stays.
            return nil
        }
        let hasColorGlyphs = kept.contains(where: { $0.collected.segments.contains(where: { $0.isColorGlyphs }) })

        let padding = DepthSwipeTitleArt.padding
        let scale = UIScreenScale
        var units: [Unit] = []
        var cellX: CGFloat = 0.0
        for entry in kept {
            let x = entry.collected.minX
            let width = entry.collected.maxX - x
            let cellLeft = floor((x - padding.width) * scale) / scale
            let cellWidth = ceil((x + width + padding.width) * scale) / scale - cellLeft
            units.append(Unit(x: x, width: width, cellLeft: cellLeft, cellWidth: cellWidth, cellX: cellX))
            cellX += ceil(cellWidth)
        }
        let cellHeight = nodeSize.height + padding.height * 2.0
        let rowCount = 2 + DepthSwipeLook.title.layers
        let size = CGSize(width: max(1.0, cellX), height: cellHeight * CGFloat(rowCount))

        // The "…" of a truncated name takes its colour from the context: the name's colour there.
        var tokenColor = UIColor.black
        if let color = attributedString.attribute(.foregroundColor, at: max(0, attributedString.length - 1), effectiveRange: nil) as? UIColor {
            tokenColor = color
        }

        // Every letter alone in its cell of a row starting at y = 0, at its place in the line:
        // all of its glyphs, or only its text (`false`) or only its colour emoji (`true`).
        func drawFaces(_ context: CGContext, _ colorGlyphs: Bool?) {
            // As TextNode draws.
            context.setAllowsAntialiasing(true)
            context.setAllowsFontSmoothing(false)
            context.setShouldSmoothFonts(false)
            context.setAllowsFontSubpixelPositioning(false)
            context.setShouldSubpixelPositionFonts(false)
            context.setAllowsFontSubpixelQuantization(true)
            context.setShouldSubpixelQuantizeFonts(true)
            for (i, unit) in units.enumerated() {
                let cell = CGRect(x: unit.cellX, y: 0.0, width: unit.cellWidth, height: cellHeight)
                context.saveGState()
                context.clip(to: cell)
                context.translateBy(x: unit.cellX - unit.cellLeft, y: padding.height)
                context.textMatrix = CGAffineTransform(scaleX: 1.0, y: -1.0)
                for segment in kept[i].collected.segments where colorGlyphs == nil || colorGlyphs == segment.isColorGlyphs {
                    if segment.usesContextColor {
                        context.setFillColor(tokenColor.cgColor)
                    }
                    context.textPosition = lines[segment.line].origin
                    CTRunDraw(segment.run, context, CFRange(location: segment.start, length: segment.count))
                }
                context.restoreGState()
            }
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { rendererContext in
            let context = rendererContext.cgContext

            // The faces: each letter alone in its cell, at its place in the line.
            drawFaces(context, nil)

            // The other rows: the faces again, recoloured (their alpha kept); colour emoji are laid
            // over them as they are.
            let rowSize = CGSize(width: size.width, height: cellHeight)
            var textFaces: UIImage?
            var colorFaces: UIImage?
            if hasColorGlyphs {
                let rowRenderer = UIGraphicsImageRenderer(size: rowSize, format: format)
                textFaces = rowRenderer.image { rowContext in
                    drawFaces(rowContext.cgContext, false)
                }
                colorFaces = rowRenderer.image { rowContext in
                    drawFaces(rowContext.cgContext, true)
                }
            } else if let full = context.makeImage(), let faces = full.cropping(to: CGRect(x: 0.0, y: 0.0, width: CGFloat(full.width), height: (cellHeight * scale).rounded())) {
                textFaces = UIImage(cgImage: faces, scale: scale, orientation: .up)
            }
            guard let tinted = textFaces else {
                return
            }
            func tint(row: Int, color: UIColor) {
                let rect = CGRect(origin: CGPoint(x: 0.0, y: CGFloat(row) * cellHeight), size: rowSize)
                tinted.draw(in: CGRect(origin: rect.origin, size: tinted.size))
                context.saveGState()
                context.setBlendMode(.sourceIn)
                context.setFillColor(color.cgColor)
                context.fill(rect)
                context.restoreGState()
                colorFaces?.draw(in: CGRect(origin: rect.origin, size: rowSize))
            }
            tint(row: DepthSwipeTitleArt.shadeRow, color: DepthSwipeTitleArt.shadeColor(isDark: isDark))
            let layers = DepthSwipeLook.title.layers
            for j in 1 ... layers {
                let u = CGFloat(j - 1) / CGFloat(max(1, layers - 1))
                tint(row: DepthSwipeTitleArt.copyRow(j), color: DepthSwipeTitleArt.extrusionColor(u, isDark: isDark))
            }
        }
        guard let cgImage = image.cgImage else {
            return nil
        }
        return DepthSwipeTitleArt(units: units, image: cgImage, size: size, nodeSize: nodeSize, rowCount: rowCount)
    }
}

/// A line of the message as a picture: one band of a snapshot of the text node it belongs to.
struct DepthSwipePlateArt {
    let image: CGImage
    /// The band in the snapshot (CALayer.contentsRect).
    let contentsRect: CGRect
    /// The band in the layer the text node sits in.
    let frame: CGRect
    /// The node's own opacity (a dimmed line stays dimmed).
    let opacity: Float
}

/// The photo as the disc's pictures: its picture (the face, with parallax) and where it sits in the
/// photo, the rest of its drawing (a story ring, printed on the face), its own corner radius (round,
/// or a forum's rounded square), the edges of the face and the back, and the rim's colour.
struct DepthSwipeDiscArt {
    let picture: CGImage
    let pictureFrame: CGRect
    let decorations: CGImage?
    let cornerRadius: CGFloat
    let faceEdge: CGImage?
    let backEdge: CGImage?
    let color: (r: CGFloat, g: CGFloat, b: CGFloat)
}

/// A flat badge of the row (verified, emoji status, muted, the online marker…) as a picture: the rig
/// moves its copy, the badge itself is only hidden (the row's layout keeps laying it out).
struct DepthSwipeBadgeArt {
    let original: CALayer
    let image: CGImage
}

enum DepthSwipeSnapshot {
    private static func renderer(size: CGSize) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreenScale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    /// A layer as it is drawn now (its contents and sublayers), without the layers in `hiding`
    /// (hidden only while it is drawn, inside one transaction: nothing changes on screen).
    static func image(of layer: CALayer, hiding: [CALayer] = []) -> CGImage? {
        let size = layer.bounds.size
        if size.width <= 0.0 || size.height <= 0.0 {
            return nil
        }
        let shown = hiding.filter { !$0.isHidden }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for hidden in shown {
            hidden.isHidden = true
        }
        let image = self.renderer(size: size).image { rendererContext in
            let context = rendererContext.cgContext
            context.translateBy(x: -layer.bounds.minX, y: -layer.bounds.minY)
            layer.render(in: context)
        }.cgImage
        for hidden in shown {
            hidden.isHidden = false
        }
        CATransaction.commit()
        return image
    }

    /// The message's lines: the text node drawn from its layout now (as TextNode draws, whether or
    /// not its asynchronous display has caught up), its inline emoji layers over it, cut into one
    /// band per rendered line at the midpoints between lines.
    static func lines(of textNode: TextNode, in parent: CALayer) -> [DepthSwipePlateArt] {
        guard let layout = textNode.cachedLayout else {
            return []
        }
        let layer = textNode.layer
        let size = layer.bounds.size
        if size.width <= 0.0 || size.height <= 0.0 {
            return []
        }
        var bands: [(top: CGFloat, bottom: CGFloat)] = []
        layout.enumerateRenderedLines(in: CGRect(origin: CGPoint(), size: size)) { line, origin in
            var ascent: CGFloat = 0.0
            var descent: CGFloat = 0.0
            var leading: CGFloat = 0.0
            let _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            bands.append((origin.y - ascent, origin.y + descent))
        }
        if bands.isEmpty {
            return []
        }
        let image = self.renderer(size: size).image { rendererContext in
            let context = rendererContext.cgContext
            TextNode.draw(CGRect(origin: CGPoint(), size: size), withParameters: TextNode.DrawingParameters(cachedLayout: layout, renderContentTypes: .all), isCancelled: { false }, isRasterizing: false)
            for sublayer in layer.sublayers ?? [] where !sublayer.isHidden && sublayer.opacity > 0.0 {
                context.saveGState()
                context.translateBy(x: sublayer.frame.minX, y: sublayer.frame.minY)
                sublayer.render(in: context)
                context.restoreGState()
            }
        }
        guard let cgImage = image.cgImage else {
            return []
        }
        let frame = layer.superlayer != nil ? layer.convert(layer.bounds, to: parent) : layer.frame
        let scale = UIScreenScale
        // Cut on the pixel grid, so at rest every plate shows the flat text's own pixels.
        func boundary(_ i: Int) -> CGFloat {
            if i == 0 {
                return 0.0
            } else if i == bands.count {
                return size.height
            }
            return min(size.height, max(0.0, ((bands[i - 1].bottom + bands[i].top) * 0.5 * scale).rounded() / scale))
        }
        var plates: [DepthSwipePlateArt] = []
        for i in 0 ..< bands.count {
            let top = boundary(i)
            let bottom = boundary(i + 1)
            if bottom <= top {
                continue
            }
            plates.append(DepthSwipePlateArt(
                image: cgImage,
                contentsRect: CGRect(x: 0.0, y: top / size.height, width: 1.0, height: (bottom - top) / size.height),
                frame: CGRect(x: frame.minX, y: frame.minY + top, width: frame.width, height: bottom - top),
                opacity: layer.opacity
            ))
        }
        return plates
    }

    /// A one-line node (the author's line in groups) as one plate.
    static func plate(of layer: CALayer, in parent: CALayer) -> DepthSwipePlateArt? {
        guard let image = self.image(of: layer) else {
            return nil
        }
        return DepthSwipePlateArt(image: image, contentsRect: CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0), frame: layer.convert(layer.bounds, to: parent), opacity: layer.opacity)
    }

    /// chat-list.js meanColor: the photo's average colour (8 × 8, transparent corners ignored).
    static func meanColor(_ image: CGImage) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        guard let average = self.average(image), average.a >= 1.0 / 255.0 else {
            return nil
        }
        return (average.r, average.g, average.b)
    }

    /// The average colour (un-premultiplied) and coverage of an image, from an 8 × 8 copy.
    private static func average(_ image: CGImage) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)? {
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        if !drawn {
            return nil
        }
        var r = 0.0
        var g = 0.0
        var b = 0.0
        var a = 0.0
        for i in 0 ..< side * side {
            r += Double(pixels[i * 4])
            g += Double(pixels[i * 4 + 1])
            b += Double(pixels[i * 4 + 2])
            a += Double(pixels[i * 4 + 3])
        }
        if a <= 0.0 {
            return (0.0, 0.0, 0.0, 0.0)
        }
        return (CGFloat(r / a), CGFloat(g / a), CGFloat(b / a), CGFloat(a / Double(side * side * 255)))
    }

    /// The photo's own clip, as a fraction of its height: AvatarNode clips the picture round (0.5)
    /// or, for forums, to a rounded square (0.25). Round when no clipping layer says otherwise.
    static func cornerFraction(of layer: CALayer) -> CGFloat {
        var fraction: CGFloat = 0.5
        for candidate in [layer] + (layer.sublayers ?? []) where candidate.masksToBounds && candidate.cornerRadius > 0.0 && candidate.bounds.height > 0.0 {
            fraction = min(fraction, candidate.cornerRadius / candidate.bounds.height)
        }
        return fraction
    }

    /// The disc's outline: a circle, or a rounded square with circular corners (CALayer.cornerRadius).
    static func outline(_ rect: CGRect, cornerRadius: CGFloat) -> CGPath {
        let radius = min(cornerRadius, min(rect.width, rect.height) * 0.5)
        if radius >= min(rect.width, rect.height) * 0.5 - 1e-3 {
            return CGPath(ellipseIn: rect, transform: nil)
        }
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    /// The face's edge (depth.js `rim`: inset 0.75 pt white 35 %, inner shadow 6 pt black 25 %) or
    /// the back's (`backShade`: white 30 %, 8 pt black 30 %).
    static func edgeImage(size: CGSize, cornerRadius: CGFloat, ringAlpha: CGFloat, shadowBlur: CGFloat, shadowAlpha: CGFloat) -> CGImage? {
        if size.width <= 0.0 || size.height <= 0.0 {
            return nil
        }
        return self.renderer(size: size).image { rendererContext in
            let context = rendererContext.cgContext
            let rect = CGRect(origin: CGPoint(), size: size)
            let outline = self.outline(rect, cornerRadius: cornerRadius)
            context.addPath(outline)
            context.clip()
            // Inner shadow: the outside of the outline, filled with a shadow that falls inward.
            context.saveGState()
            context.setShadow(offset: CGSize(), blur: shadowBlur, color: UIColor(white: 0.0, alpha: shadowAlpha).cgColor)
            context.addRect(rect.insetBy(dx: -shadowBlur * 4.0, dy: -shadowBlur * 4.0))
            context.addPath(outline)
            context.setFillColor(UIColor.black.cgColor)
            context.fillPath(using: .evenOdd)
            context.restoreGState()
            // The ring.
            let ring: CGFloat = 0.75
            context.setStrokeColor(UIColor(white: 1.0, alpha: ringAlpha).cgColor)
            context.setLineWidth(ring)
            context.addPath(self.outline(rect.insetBy(dx: ring * 0.5, dy: ring * 0.5), cornerRadius: max(0.0, cornerRadius - ring * 0.5)))
            context.strokePath()
        }.cgImage
    }
}
