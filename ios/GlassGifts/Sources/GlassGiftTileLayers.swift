import Foundation
import UIKit
import Display

/// The glass's own layers: the prototype's `.gift-*` rules (prototype/styles/telegram.css, "profile + glass gifts") as
/// Core Animation layers. They are sublayers of the tile view (GiftItemComponent.View), next to its own:
///
///     shadow                    .gift-shadow  — below everything, flat under the leaning glass
///     backgroundLayer           (GiftItemComponent: the tile colour, or a collectible's backdrop colour)
///     pattern view              (GiftItemComponent: a collectible's radial backdrop and symbol rings)
///     glaze                     .gift-body's glass gradient (regular gifts; a collectible keeps its backdrop)
///     holo                      .gift-holo    — the prismatic streak (screen blend; multiply in the light theme)
///     sheen                     .gift-sheen   — the specular sheen
///     shards                    .gift-shard   — the light fragments of a touch (screen blend)
///     rim                       .gift-rim     — the 1 pt lit edge
///     sticker, ribbon, badges   (GiftItemComponent, floating above the glass: GlassGiftTile sets their depth)
///     sparkles                  .gift-sparkle — at the four corners
///
/// Everything here is in the tile's own coordinates (its bounds, at the tile's size); the tile view's sublayer transform
/// leans them all together. Nothing animates by itself: `GlassGiftTile` writes every frame.
final class GlassGiftTileLayers {
    /// `.gift-shadow`: left / right 8, top 10, bottom −4, radius 20, black 0.55 (light theme 0.22), blur(9px).
    static let shadowInsets = UIEdgeInsets(top: 10.0, left: 8.0, bottom: -4.0, right: 8.0)
    static let shadowCornerRadius: CGFloat = 20.0
    /// CSS `filter: blur(9px)` is a Gaussian with σ = 9; `CALayer.shadowRadius` is σ as well.
    static let shadowBlur: CGFloat = 9.0
    /// `.gift-sheen { inset: -35% }`: the sheen's box is 170 % of the tile.
    static let sheenBoxScale: CGFloat = 1.7
    /// `.gift-holo { background-size: 300% 300% }`.
    static let holoBoxScale: CGFloat = 3.0
    /// `.gift-shard { width: 34%; height: 220%; top: -60% + k · 28% }`.
    static let shardWidth: CGFloat = 0.34
    static let shardHeight: CGFloat = 2.2
    /// `.gift-sparkle`: 10 × 10.
    static let sparkleSize: CGFloat = 10.0

    let shadow = SimpleLayer()
    let glaze = SimpleGradientLayer()
    let holo = SimpleLayer()
    private let holoTiles: [SimpleGradientLayer] = (0 ..< 4).map { _ in SimpleGradientLayer() }
    /// The sheen's radial gradient is clear past 50 % of its radius (0.68 w on a square tile), inside its 170 % box
    /// but for the box's top edge (0.65 w above the centre), where the box trims a fringe under 1 % white: one
    /// tile-sized gradient whose centre moves draws the same without a clipping container.
    let sheen = SimpleGradientLayer()
    let shards = SimpleLayer()
    private let shardLayers: [SimpleGradientLayer] = (0 ..< GlassGiftLook.shardCount).map { _ in SimpleGradientLayer() }
    let rim = SimpleGradientLayer()
    private let rimMask = SimpleShapeLayer()
    let sparkles: [SimpleShapeLayer] = (0 ..< GlassGiftLook.sparkleCount).map { _ in SimpleShapeLayer() }

    /// The layers right above the backdrop, bottom to top.
    var glassLayers: [CALayer] {
        return [self.glaze, self.holo, self.sheen, self.shards, self.rim]
    }

    private(set) var size: CGSize = .zero
    private var cornerRadius: CGFloat = 0.0
    private var isDark: Bool?
    private var isCollectible: Bool?
    private var isResting = false

    init() {
        self.shadow.shadowColor = UIColor.black.cgColor
        self.shadow.shadowOffset = .zero
        self.shadow.shadowRadius = GlassGiftTileLayers.shadowBlur

        // The prismatic streak: linear-gradient(115deg, transparent 30%, pink 40%, gold 46%, mint 52%, blue 58%,
        // transparent 68%) at 0.55 alpha, tiled (background-repeat) on a 300 % box. The transparent ends carry their
        // neighbour's hue so the edges fade like CSS's premultiplied interpolation.
        let pink = UIColor(red: 1.0, green: 64.0 / 255.0, blue: 160.0 / 255.0, alpha: 0.55)
        let gold = UIColor(red: 1.0, green: 210.0 / 255.0, blue: 70.0 / 255.0, alpha: 0.55)
        let mint = UIColor(red: 70.0 / 255.0, green: 1.0, blue: 200.0 / 255.0, alpha: 0.55)
        let blue = UIColor(red: 80.0 / 255.0, green: 150.0 / 255.0, blue: 1.0, alpha: 0.55)
        for tile in self.holoTiles {
            tile.type = .axial
            tile.colors = [pink.withAlphaComponent(0.0), pink, gold, mint, blue, blue.withAlphaComponent(0.0)].map(\.cgColor)
            tile.locations = [0.30, 0.40, 0.46, 0.52, 0.58, 0.68]
            self.holo.addSublayer(tile)
        }
        self.holo.masksToBounds = true

        // radial-gradient(circle at 50% 38%, white 0.34, white 0.08 28%, white 0 50%).
        self.sheen.type = .radial
        self.sheen.colors = [UIColor(white: 1.0, alpha: 0.34), UIColor(white: 1.0, alpha: 0.08), UIColor(white: 1.0, alpha: 0.0)].map(\.cgColor)
        self.sheen.locations = [0.0, 0.28, 0.5]
        self.sheen.masksToBounds = true

        // linear-gradient(90deg, white 0, white 0.7 50%, white 0), screen-blended.
        for shard in self.shardLayers {
            shard.type = .axial
            shard.startPoint = CGPoint(x: 0.0, y: 0.5)
            shard.endPoint = CGPoint(x: 1.0, y: 0.5)
            shard.colors = [UIColor(white: 1.0, alpha: 0.0), UIColor(white: 1.0, alpha: 0.7), UIColor(white: 1.0, alpha: 0.0)].map(\.cgColor)
            shard.locations = [0.0, 0.5, 1.0]
            self.shards.addSublayer(shard)
        }
        self.shards.masksToBounds = true
        self.shards.compositingFilter = "screenBlendMode"
        self.shards.isHidden = true

        // The glass edge: a 1 pt ring, brighter where it faces the light.
        self.rim.type = .axial
        self.rimMask.fillColor = UIColor.clear.cgColor
        self.rimMask.strokeColor = UIColor.black.cgColor
        self.rimMask.lineWidth = 1.0
        self.rim.mask = self.rimMask

        // clip-path: polygon(50% 0, 62% 38%, 100% 50%, 62% 62%, 50% 100%, 38% 62%, 0 50%, 38% 38%), white.
        let side = GlassGiftTileLayers.sparkleSize
        let star = CGMutablePath()
        let points: [(CGFloat, CGFloat)] = [(0.5, 0.0), (0.62, 0.38), (1.0, 0.5), (0.62, 0.62), (0.5, 1.0), (0.38, 0.62), (0.0, 0.5), (0.38, 0.38)]
        for (index, point) in points.enumerated() {
            let p = CGPoint(x: point.0 * side, y: point.1 * side)
            if index == 0 {
                star.move(to: p)
            } else {
                star.addLine(to: p)
            }
        }
        star.closeSubpath()
        for sparkle in self.sparkles {
            sparkle.bounds = CGRect(x: 0.0, y: 0.0, width: side, height: side)
            sparkle.path = star
            sparkle.fillColor = UIColor.white.cgColor
            sparkle.opacity = 0.0
            sparkle.isHidden = true
        }

        for layer in [self.glaze, self.holo, self.sheen, self.shards] as [CALayer] {
            if #available(iOS 13.0, *) {
                layer.cornerCurve = .circular
            }
        }
    }

    /// Size, corner, theme. Cheap when nothing changed.
    func update(size: CGSize, cornerRadius: CGFloat, isDark: Bool, isCollectible: Bool) {
        let sizeUpdated = self.size != size || self.cornerRadius != cornerRadius
        let themeUpdated = self.isDark != isDark || self.isCollectible != isCollectible
        if !sizeUpdated && !themeUpdated {
            return
        }
        self.size = size
        self.cornerRadius = cornerRadius
        self.isDark = isDark
        self.isCollectible = isCollectible
        let bounds = CGRect(origin: .zero, size: size)

        // Shadow. Its transform (flat under the leaning glass) is GlassGiftTile's.
        let insets = GlassGiftTileLayers.shadowInsets
        let shadowSize = CGSize(width: max(1.0, size.width - insets.left - insets.right), height: max(1.0, size.height - insets.top - insets.bottom))
        self.shadow.bounds = CGRect(origin: .zero, size: shadowSize)
        self.shadow.position = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        self.shadow.shadowPath = CGPath(roundedRect: CGRect(origin: .zero, size: shadowSize), cornerWidth: min(GlassGiftTileLayers.shadowCornerRadius, shadowSize.width / 2.0), cornerHeight: min(GlassGiftTileLayers.shadowCornerRadius, shadowSize.height / 2.0), transform: nil)
        self.shadow.shadowOpacity = isDark ? 0.55 : 0.22

        // The glass gradient of a regular tile: linear-gradient(160deg, white 0.09, white 0.02 55%) over the tile colour;
        // in the light theme #fff → #f2f2f7, i.e. rgb(0, 0, 98) at 0 → 13/255 over white.
        self.glaze.frame = bounds
        self.glaze.cornerRadius = cornerRadius
        self.glaze.masksToBounds = true
        self.glaze.isHidden = isCollectible
        let glazePoints = GlassGiftTileLayers.cssLinearGradientPoints(angle: 160.0, size: size)
        self.glaze.startPoint = glazePoints.start
        self.glaze.endPoint = glazePoints.end
        if isDark {
            self.glaze.colors = [UIColor(white: 1.0, alpha: 0.09), UIColor(white: 1.0, alpha: 0.02)].map(\.cgColor)
            self.glaze.locations = [0.0, 0.55]
        } else {
            let tint = UIColor(red: 0.0, green: 0.0, blue: 98.0 / 255.0, alpha: 1.0)
            self.glaze.colors = [tint.withAlphaComponent(0.0), tint.withAlphaComponent(13.0 / 255.0)].map(\.cgColor)
            self.glaze.locations = [0.0, 1.0]
        }

        // Prismatic streak.
        self.holo.frame = bounds
        self.holo.cornerRadius = cornerRadius
        self.holo.compositingFilter = isDark ? "screenBlendMode" : "multiplyBlendMode"
        let holoSize = CGSize(width: size.width * GlassGiftTileLayers.holoBoxScale, height: size.height * GlassGiftTileLayers.holoBoxScale)
        let holoPoints = GlassGiftTileLayers.cssLinearGradientPoints(angle: 115.0, size: holoSize)
        for tile in self.holoTiles {
            tile.bounds = CGRect(origin: .zero, size: holoSize)
            tile.anchorPoint = .zero
            tile.startPoint = holoPoints.start
            tile.endPoint = holoPoints.end
        }

        // Sheen (its centre and radius are `apply`'s).
        self.sheen.frame = bounds
        self.sheen.cornerRadius = cornerRadius

        // Shards.
        self.shards.frame = bounds
        self.shards.cornerRadius = cornerRadius
        for (index, shard) in self.shardLayers.enumerated() {
            let shardSize = CGSize(width: size.width * GlassGiftTileLayers.shardWidth, height: size.height * GlassGiftTileLayers.shardHeight)
            shard.bounds = CGRect(origin: .zero, size: shardSize)
            let top = size.height * (-0.6 + 0.28 * CGFloat(index))
            shard.position = CGPoint(x: shardSize.width / 2.0, y: top + shardSize.height / 2.0)
        }

        // Rim: the ring between the rounded tile and its 1 pt inset.
        self.rim.frame = bounds
        self.rimMask.frame = bounds
        let inset: CGFloat = 0.5
        let ring = bounds.insetBy(dx: inset, dy: inset)
        let ringRadius = max(0.0, min(cornerRadius - inset, min(ring.width, ring.height) / 2.0))
        self.rimMask.path = CGPath(roundedRect: ring, cornerWidth: ringRadius, cornerHeight: ringRadius, transform: nil)
        let rimStops: [(location: CGFloat, color: GlassGiftRGBA)]
        if isDark {
            rimStops = [(0.0, GlassGiftRGBA(1.0, 1.0, 1.0, 0.7)), (0.32, GlassGiftRGBA(1.0, 1.0, 1.0, 0.1)), (0.68, GlassGiftRGBA(1.0, 1.0, 1.0, 0.06)), (1.0, GlassGiftRGBA(1.0, 1.0, 1.0, 0.45))]
        } else {
            rimStops = [(0.0, GlassGiftRGBA(1.0, 1.0, 1.0, 1.0)), (0.32, GlassGiftRGBA(0.0, 0.0, 0.0, 0.06)), (0.68, GlassGiftRGBA(0.0, 0.0, 0.0, 0.08)), (1.0, GlassGiftRGBA(1.0, 1.0, 1.0, 0.9))]
        }
        let sampled = GlassGiftTileLayers.premultipliedStops(rimStops, samples: 24)
        self.rim.colors = sampled.colors
        self.rim.locations = sampled.locations

        // Sparkles: left / top 8, 8 · w − 18, 10 · 10, h − 20 · w − 16, h − 18 (profile-page.js).
        let half = GlassGiftTileLayers.sparkleSize / 2.0
        let origins = [CGPoint(x: 8.0, y: 8.0), CGPoint(x: size.width - 18.0, y: 10.0), CGPoint(x: 10.0, y: size.height - 20.0), CGPoint(x: size.width - 16.0, y: size.height - 18.0)]
        for (sparkle, origin) in zip(self.sparkles, origins) {
            sparkle.position = CGPoint(x: origin.x + half, y: origin.y + half)
        }
    }

    /// The light of one frame: sheen, streak, rim, shards, sparkles (the tile's transform, shadow and depth are
    /// GlassGiftTile's).
    func apply(_ state: GlassTileState) {
        let size = self.size
        guard size.width > 0.0, size.height > 0.0 else {
            return
        }

        // The sheen's box is 170 % of the tile, centred, moved by translate(sheenX %, sheenY %) of itself; its circle
        // sits at (50 %, 38 %) of the box and reaches the box's farthest corner (CSS `farthest-corner`).
        let box = CGSize(width: size.width * GlassGiftTileLayers.sheenBoxScale, height: size.height * GlassGiftTileLayers.sheenBoxScale)
        let boxOrigin = CGPoint(x: (size.width - box.width) / 2.0 + CGFloat(state.sheenX / 100.0) * box.width, y: (size.height - box.height) / 2.0 + CGFloat(state.sheenY / 100.0) * box.height)
        let centre = CGPoint(x: boxOrigin.x + 0.5 * box.width, y: boxOrigin.y + 0.38 * box.height)
        let radius = hypot(0.5 * box.width, 0.62 * box.height)
        self.sheen.startPoint = CGPoint(x: centre.x / size.width, y: centre.y / size.height)
        self.sheen.endPoint = CGPoint(x: (centre.x + radius) / size.width, y: (centre.y + radius) / size.height)
        self.sheen.opacity = Float(state.sheenOpacity)

        // background-position: (container − image) · p, repeated: two tiles each way cover the glass.
        let holoWidth = size.width * GlassGiftTileLayers.holoBoxScale
        let holoHeight = size.height * GlassGiftTileLayers.holoBoxScale
        let offsetX = GlassGiftTileLayers.wrap((size.width - holoWidth) * CGFloat(state.holoX / 100.0), period: holoWidth)
        let offsetY = GlassGiftTileLayers.wrap((size.height - holoHeight) * CGFloat(state.holoY / 100.0), period: holoHeight)
        for (index, tile) in self.holoTiles.enumerated() {
            tile.position = CGPoint(x: offsetX + CGFloat(index % 2) * holoWidth, y: offsetY + CGFloat(index / 2) * holoHeight)
        }
        self.holo.opacity = Float(state.holoOpacity)

        let rimPoints = GlassGiftTileLayers.cssLinearGradientPoints(angle: state.rimAngle, size: size)
        self.rim.startPoint = rimPoints.start
        self.rim.endPoint = rimPoints.end

        if let shards = state.shards {
            self.shards.isHidden = false
            for (layer, shard) in zip(self.shardLayers, shards) {
                // translateX(t %) rotate(r): rotated about its centre, then moved along the tile.
                let translation = CGFloat(shard.translation / 100.0) * layer.bounds.width
                layer.transform = CATransform3DConcat(CATransform3DMakeRotation(CGFloat(shard.rotation * Double.pi / 180.0), 0.0, 0.0, 1.0), CATransform3DMakeTranslation(translation, 0.0, 0.0))
                layer.opacity = Float(shard.opacity)
            }
        } else {
            self.shards.isHidden = true
        }

        if let sparkles = state.sparkles {
            for (layer, sparkle) in zip(self.sparkles, sparkles) {
                // scale(s) rotate(r) about its centre.
                layer.transform = CATransform3DConcat(CATransform3DMakeRotation(CGFloat(sparkle.rotation * Double.pi / 180.0), 0.0, 0.0, 1.0), CATransform3DMakeScale(CGFloat(sparkle.scale), CGFloat(sparkle.scale), 1.0))
                layer.opacity = Float(sparkle.opacity)
                layer.isHidden = sparkle.opacity <= 0.0
            }
        } else {
            for layer in self.sparkles {
                layer.isHidden = true
            }
        }
    }

    /// While the tile rests, the blended streak and the masked rim are kept as bitmaps, so a still grid scrolls
    /// without their offscreen passes; while the light moves they draw live.
    func setResting(_ isResting: Bool) {
        if self.isResting == isResting {
            return
        }
        self.isResting = isResting
        for layer in [self.holo, self.rim] as [CALayer] {
            layer.rasterizationScale = UIScreenScale
            layer.shouldRasterize = isResting
        }
    }

    /// `x` moved by whole periods into (−period, 0]: where a repeated background's first copy starts.
    static func wrap(_ x: CGFloat, period: CGFloat) -> CGFloat {
        guard period > 0.0 else {
            return 0.0
        }
        var value = x.truncatingRemainder(dividingBy: period)
        if value > 0.0 {
            value -= period
        }
        return value
    }

    /// CSS `linear-gradient(<angle>)` over a box: 0deg points up, 90deg right; the gradient line runs through the
    /// centre and is |w·sin a| + |h·cos a| long, so the corners get the 0 % and 100 % colours. In unit coordinates.
    static func cssLinearGradientPoints(angle: Double, size: CGSize) -> (start: CGPoint, end: CGPoint) {
        let a = angle * Double.pi / 180.0
        let w = Double(max(size.width, 1.0))
        let h = Double(max(size.height, 1.0))
        let dx = sin(a)
        let dy = -cos(a)
        let length = abs(w * sin(a)) + abs(h * cos(a))
        let start = CGPoint(x: (w / 2.0 - dx * length / 2.0) / w, y: (h / 2.0 - dy * length / 2.0) / h)
        let end = CGPoint(x: (w / 2.0 + dx * length / 2.0) / w, y: (h / 2.0 + dy * length / 2.0) / h)
        return (start, end)
    }

    /// CSS interpolates gradient colours premultiplied (white → transparent black stays white while it fades);
    /// CAGradientLayer doesn't. Sampling the CSS gradient finely gives the same ramp either way.
    static func premultipliedStops(_ stops: [(location: CGFloat, color: GlassGiftRGBA)], samples: Int) -> (colors: [CGColor], locations: [NSNumber]) {
        guard let first = stops.first, let last = stops.last else {
            return ([], [])
        }
        var locations = Set<CGFloat>(stops.map(\.location))
        for i in 0 ... samples {
            locations.insert(first.location + (last.location - first.location) * CGFloat(i) / CGFloat(samples))
        }
        var colors: [CGColor] = []
        var numbers: [NSNumber] = []
        for location in locations.sorted() {
            var color = first.color
            for (lower, upper) in zip(stops, stops.dropFirst()) where location >= lower.location && location <= upper.location {
                let span = upper.location - lower.location
                let t = span > 0.0 ? (location - lower.location) / span : 0.0
                color = GlassGiftRGBA.premultipliedMix(lower.color, upper.color, t)
                break
            }
            if location > last.location {
                color = last.color
            }
            colors.append(color.cgColor)
            numbers.append(NSNumber(value: Double(location)))
        }
        return (colors, numbers)
    }
}

/// A straight (not premultiplied) RGBA colour, 0…1.
struct GlassGiftRGBA {
    var r: CGFloat
    var g: CGFloat
    var b: CGFloat
    var a: CGFloat

    init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    var cgColor: CGColor {
        return UIColor(red: self.r, green: self.g, blue: self.b, alpha: self.a).cgColor
    }

    static func premultipliedMix(_ x: GlassGiftRGBA, _ y: GlassGiftRGBA, _ t: CGFloat) -> GlassGiftRGBA {
        let a = x.a + (y.a - x.a) * t
        guard a > 0.0 else {
            return GlassGiftRGBA(x.r + (y.r - x.r) * t, x.g + (y.g - x.g) * t, x.b + (y.b - x.b) * t, 0.0)
        }
        let r = (x.r * x.a + (y.r * y.a - x.r * x.a) * t) / a
        let g = (x.g * x.a + (y.g * y.a - x.g * x.a) * t) / a
        let b = (x.b * x.a + (y.b * y.a - x.b * x.a) * t) / a
        return GlassGiftRGBA(r, g, b, a)
    }
}
