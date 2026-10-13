import Foundation
import UIKit
import Display

/// One icon while it plays: the inline SVG that `LivingIcons.play()` puts in the glyph's place
/// (prototype/src/settings/living-icons.js), as layers.
///
/// · The tile (Telegram's own, without its glyph: `LivingSettingsIconTile`) pops on a spring, clipped to its
///   rounded square; the glyph lies in it, then the moving cut-outs, then the sheen crossing it.
/// · The glyph is the icon's parts (`LivingIconArtwork`) as nested layers whose affine transforms are exactly
///   the SVG group transforms the rig sets; clip paths are shape-layer masks.
/// · Cut-outs (the prototype's masks, whose black shapes move) are drawn as holes: a copy of the tile's own
///   image masked by the moving shapes (a mirror of the part layers), so they show exactly what a hole in the
///   glyph would show — at rest the icon is pixel for pixel the static image.
/// · Effects in the glyph (waves, rays, the paint stroke, the flash, paper) are shape layers added the first
///   time a rig asks for them (Ask a Question's dots and the turning globe are parts of their glyphs); the
///   glyph's glow is its shadow, its hue turn recolours its layers, its 3D turn is a perspective transform.
///   Particles (sparkles, confetti, the halo) fly outside the tile, in `fxLayer`.
/// All layers are Display's `Simple*` layers: no implicit animations; frames are applied without actions.
final class LivingSettingsIconLayer: SimpleLayer {
    struct Style {
        /// The glyph's colour (white on a tile, the accent colour for the profile's own rows).
        var glyphColor: UIColor
        /// The tile's colour, for what the prototype draws in `tileColor`.
        var tileColor: UIColor
        /// The tile without its glyph, or nil (no tile).
        var tileImage: UIImage?
        /// Money: the row's own image, turned as a whole.
        var elementImage: UIImage?
    }

    private static let glyphSize = CGSize(width: 30.0, height: 30.0)

    let rig: LivingIconRig
    private let iconStyle: Style
    private let screenScale: CGFloat

    private var tileLayer: SimpleLayer?
    private var sheenLayer: SimpleGradientLayer?
    /// The glyph: the prototype's `<svg viewBox="0 0 30 30">`.
    private let glyphLayer = SimpleLayer()
    /// Money: the image itself.
    private var elementLayer: SimpleLayer?
    /// Around the tile (or the glyph), unclipped: sparkles, confetti, the halo.
    private let fxLayer = SimpleLayer()

    /// The layers of each named part (a part inside a cut-out also has a layer in the hole's mask).
    private var parts: [String: [CALayer]] = [:]
    /// Stroked shapes under each part (`P[name].dash(v)`).
    private var dashTargets: [String: [CAShapeLayer]] = [:]
    private var bookmarkLayer: CAShapeLayer?
    private var shineLayer: CAShapeLayer?
    private var paperLayer: CAShapeLayer?
    /// Telegram's dotted bubble: the dots (as holes) that bounce with `fx.dots`.
    private var typingDotLayers: [Int: [CALayer]] = [:]
    /// Telegram's globe turning: the moving meridians and the layer that cross-fades them in.
    private var turningGlobeLayer: CALayer?
    private var turningMeridianLayers: [CAShapeLayer] = []
    /// Money: the sparkle cut out of its image (`E.inner`) and the point it turns round.
    private var innerSparkleLayer: CALayer?
    /// Everything drawn in a colour inside the glyph (for the hue turn).
    private var colored: [(layer: CAShapeLayer, color: UIColor, isStroke: Bool)] = []

    private var waveLayers: [CAShapeLayer]?
    private var rayLayers: [CAShapeLayer]?
    private var strokeLayer: CAShapeLayer?
    private var flashLayer: CAShapeLayer?
    private var haloLayer: CAShapeLayer?
    private var sparkleLayers: [CAShapeLayer]?
    private var confettiLayers: [CALayer]?

    /// - Parameters:
    ///   - tree: the icon's parts (nil for Money, whose image turns as a whole).
    ///   - size: the static icon's size (30 × 30, or Money's image).
    init(rig: LivingIconRig, tree: [LivingIconNode]?, style: Style, size: CGSize, screenScale: CGFloat) {
        self.rig = rig
        self.iconStyle = style
        self.screenScale = screenScale

        super.init()

        self.bounds = CGRect(origin: CGPoint(), size: size)
        let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)

        // The glyph's box is centred on the icon (the prototype's svg sits exactly over the glyph).
        self.glyphLayer.bounds = CGRect(origin: CGPoint(), size: LivingSettingsIconLayer.glyphSize)
        self.glyphLayer.position = center
        self.glyphLayer.contentsScale = screenScale

        if let tileImage = style.tileImage {
            let tileLayer = SimpleLayer()
            tileLayer.bounds = CGRect(origin: CGPoint(), size: LivingSettingsIconLayer.glyphSize)
            tileLayer.position = center
            tileLayer.contentsScale = screenScale
            // The tile's overflow is hidden behind its rounded corners.
            let tileMask = SimpleShapeLayer()
            tileMask.frame = tileLayer.bounds
            tileMask.contentsScale = screenScale
            tileMask.path = LivingSettingsIconTile.outline
            tileLayer.mask = tileMask

            let background = SimpleLayer()
            background.frame = tileLayer.bounds
            background.contents = tileImage.cgImage
            background.contentsScale = tileImage.scale
            tileLayer.addSublayer(background)

            self.glyphLayer.position = CGPoint(x: 15.0, y: 15.0)
            tileLayer.addSublayer(self.glyphLayer)
            self.addSublayer(tileLayer)
            self.tileLayer = tileLayer
        } else if let elementImage = style.elementImage {
            let elementLayer = SimpleLayer()
            elementLayer.bounds = CGRect(origin: CGPoint(), size: size)
            elementLayer.position = center
            elementLayer.contentsScale = elementImage.scale
            if let cgImage = elementImage.cgImage, let split = LivingSettingsIconLayer.split(cgImage) {
                // The gem and, over it, its sparkle, which turns on its own (exactly the image at rest).
                elementLayer.contents = split.base
                let sparkle = SimpleLayer()
                sparkle.contents = split.sparkle
                sparkle.contentsScale = elementImage.scale
                let pointCenter = CGPoint(x: split.center.x / elementImage.scale, y: split.center.y / elementImage.scale)
                sparkle.bounds = CGRect(origin: CGPoint(), size: size)
                sparkle.anchorPoint = CGPoint(x: pointCenter.x / max(1.0, size.width), y: pointCenter.y / max(1.0, size.height))
                sparkle.position = pointCenter
                elementLayer.addSublayer(sparkle)
                self.innerSparkleLayer = sparkle
            } else {
                elementLayer.contents = elementImage.cgImage
            }
            self.addSublayer(elementLayer)
            self.elementLayer = elementLayer
        } else {
            self.addSublayer(self.glyphLayer)
        }

        if let tree = tree {
            var cutouts: [(ancestors: [LivingIconNode], holes: [LivingIconNode])] = []
            self.build(tree, into: self.glyphLayer, ancestors: [], cutouts: &cutouts)
            if let tileLayer = self.tileLayer, let tileImage = style.tileImage {
                for cutout in cutouts {
                    tileLayer.addSublayer(self.makeHole(cutout.ancestors, cutout.holes, tileImage: tileImage))
                }
            }
        }

        if let tileLayer = self.tileLayer {
            // The sheen: inset -40 %, a 115° band of white 0.55 between 40 % and 60 %, starting one width to the left.
            let sheen = SimpleGradientLayer()
            sheen.frame = CGRect(x: -12.0, y: -12.0, width: 54.0, height: 54.0)
            sheen.contentsScale = screenScale
            sheen.colors = [UIColor(white: 1.0, alpha: 0.0).cgColor, UIColor(white: 1.0, alpha: 0.55).cgColor, UIColor(white: 1.0, alpha: 0.0).cgColor]
            sheen.locations = [0.4, 0.5, 0.6]
            // CSS linear-gradient(115deg): direction (sin 115°, -cos 115°) in a y-down box; on a square box the
            // gradient line is |sin| + |cos| widths long, through the centre.
            let angle = 115.0 * Double.pi / 180.0
            let dx = sin(angle)
            let dy = -cos(angle)
            let half = (abs(dx) + abs(dy)) / 2.0
            sheen.startPoint = CGPoint(x: 0.5 - dx * half, y: 0.5 - dy * half)
            sheen.endPoint = CGPoint(x: 0.5 + dx * half, y: 0.5 + dy * half)
            sheen.setAffineTransform(CGAffineTransform(translationX: -54.0, y: 0.0))
            tileLayer.addSublayer(sheen)
            self.sheenLayer = sheen
        }

        self.fxLayer.bounds = self.bounds
        self.fxLayer.position = center
        self.addSublayer(self.fxLayer)
    }

    override init(layer: Any) {
        guard let layer = layer as? LivingSettingsIconLayer else {
            preconditionFailure()
        }
        self.rig = layer.rig
        self.iconStyle = layer.iconStyle
        self.screenScale = layer.screenScale
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static var splitCache: [(image: CGImage, result: LivingIconImageSplit.Result)] = []

    /// Money's image split into its gem and its sparkle, once per image (main thread).
    private static func split(_ image: CGImage) -> LivingIconImageSplit.Result? {
        if let cached = LivingSettingsIconLayer.splitCache.first(where: { $0.image === image }) {
            return cached.result
        }
        guard let result = LivingIconImageSplit.split(image) else {
            return nil
        }
        LivingSettingsIconLayer.splitCache = Array(LivingSettingsIconLayer.splitCache.suffix(3)) + [(image: image, result: result)]
        return result
    }

    // MARK: - Building

    /// A layer with the coordinates of its parent (the SVG `<g>`): its affine transform is the group's.
    private func makeGroupLayer() -> SimpleLayer {
        let layer = SimpleLayer()
        layer.anchorPoint = CGPoint()
        layer.bounds = CGRect(origin: CGPoint(), size: LivingSettingsIconLayer.glyphSize)
        layer.position = CGPoint()
        layer.contentsScale = self.screenScale
        return layer
    }

    private func makeShapeLayer(path: CGPath?) -> SimpleShapeLayer {
        let layer = SimpleShapeLayer()
        layer.anchorPoint = CGPoint()
        layer.bounds = CGRect(origin: CGPoint(), size: LivingSettingsIconLayer.glyphSize)
        layer.position = CGPoint()
        layer.contentsScale = self.screenScale
        layer.path = path
        return layer
    }

    private func color(_ paint: LivingIconShape.Paint) -> UIColor {
        switch paint {
        case .glyph:
            return self.iconStyle.glyphColor
        case .tile:
            return self.iconStyle.tileColor
        }
    }

    /// Fills or strokes a shape layer as the prototype's `c.path` / `add` do (SVG defaults: butt caps, miter
    /// joins with limit 4).
    private func paint(_ layer: CAShapeLayer, color: UIColor, stroke: Double?, roundCap: Bool, evenOdd: Bool) {
        if let stroke = stroke {
            layer.fillColor = nil
            layer.strokeColor = color.cgColor
            layer.lineWidth = CGFloat(stroke)
            layer.lineCap = roundCap ? .round : .butt
            layer.lineJoin = .miter
            layer.miterLimit = 4.0
        } else {
            layer.fillColor = color.cgColor
            layer.strokeColor = nil
            layer.fillRule = evenOdd ? .evenOdd : .nonZero
        }
        self.colored.append((layer, color, stroke != nil))
    }

    /// A shape shown only under a stroke along its centre line, which its part's `dash(v)` draws back and on.
    private func addReveal(_ reveal: (path: LivingIconGeometry, width: Double), to layer: CAShapeLayer, ancestors: [LivingIconNode]) {
        let mask = self.makeShapeLayer(path: reveal.path.makePath())
        mask.fillColor = nil
        mask.strokeColor = UIColor.black.cgColor
        mask.lineWidth = CGFloat(reveal.width)
        mask.lineCap = .butt
        layer.mask = mask
        for case let .group(name?, _) in ancestors {
            self.dashTargets[name, default: []].append(mask)
        }
    }

    private func build(_ nodes: [LivingIconNode], into parent: CALayer, ancestors: [LivingIconNode], cutouts: inout [(ancestors: [LivingIconNode], holes: [LivingIconNode])]) {
        for node in nodes {
            switch node {
            case let .group(name, children):
                let layer = self.makeGroupLayer()
                parent.addSublayer(layer)
                if let name = name {
                    self.parts[name, default: []].append(layer)
                }
                self.build(children, into: layer, ancestors: ancestors + [node], cutouts: &cutouts)
            case let .shape(shape):
                let layer = self.makeShapeLayer(path: shape.geometry.makePath())
                self.paint(layer, color: self.color(shape.paint), stroke: shape.stroke, roundCap: shape.roundCap, evenOdd: shape.evenOdd)
                if let clip = shape.clip {
                    let mask = self.makeShapeLayer(path: clip.makePath())
                    mask.fillColor = UIColor.black.cgColor
                    layer.mask = mask
                }
                if let reveal = shape.reveal {
                    self.addReveal(reveal, to: layer, ancestors: ancestors)
                }
                switch shape.ref {
                case .bookmark:
                    self.bookmarkLayer = layer
                case .shine:
                    // Drawn back to nothing until the rig draws it on.
                    layer.strokeEnd = 0.0
                    layer.opacity = 0.0
                    self.shineLayer = layer
                case nil:
                    break
                }
                if shape.stroke != nil {
                    for case let .group(name?, _) in ancestors {
                        self.dashTargets[name, default: []].append(layer)
                    }
                }
                parent.addSublayer(layer)
            case let .clipped(geometry, children):
                let layer = self.makeGroupLayer()
                let mask = self.makeShapeLayer(path: geometry.makePath())
                mask.fillColor = UIColor.black.cgColor
                layer.mask = mask
                parent.addSublayer(layer)
                self.build(children, into: layer, ancestors: ancestors + [node], cutouts: &cutouts)
            case let .cutout(white, holes):
                self.build(white, into: parent, ancestors: ancestors, cutouts: &cutouts)
                cutouts.append((ancestors, holes))
            case .paper:
                let layer = self.makeShapeLayer(path: nil)
                self.paint(layer, color: self.iconStyle.glyphColor, stroke: nil, roundCap: false, evenOdd: false)
                layer.opacity = 0.0
                parent.addSublayer(layer)
                self.paperLayer = layer
            case let .typingDot(index, children):
                let layer = self.makeGroupLayer()
                parent.addSublayer(layer)
                self.typingDotLayers[index, default: []].append(layer)
                self.build(children, into: layer, ancestors: ancestors + [node], cutouts: &cutouts)
            case let .turningGlobe(rest):
                self.build(rest, into: parent, ancestors: ancestors, cutouts: &cutouts)
                parent.addSublayer(self.makeTurningGlobe())
            }
        }
    }

    /// Telegram's globe as a disc cut by its latitudes and two meridians (holes onto the tile's image), drawn over
    /// the glyph and faded in and out as a whole (`LivingIconArtwork.TurningGlobe`).
    private func makeTurningGlobe() -> CALayer {
        typealias G = LivingIconArtwork.TurningGlobe
        let globe = self.makeGroupLayer()
        globe.allowsGroupOpacity = true
        globe.opacity = 0.0

        let disc = self.makeShapeLayer(path: LivingIconPath.circle(cx: G.center.0, cy: G.center.1, r: G.radius))
        self.paint(disc, color: self.iconStyle.glyphColor, stroke: nil, roundCap: false, evenOdd: false)
        globe.addSublayer(disc)

        if let tileImage = self.iconStyle.tileImage {
            let holes = self.makeGroupLayer()
            holes.contents = tileImage.cgImage
            holes.contentsScale = tileImage.scale
            let mask = self.makeGroupLayer()
            let latitudes = CGMutablePath()
            for y in G.latitudes {
                latitudes.move(to: CGPoint(x: 3.0, y: y))
                latitudes.addLine(to: CGPoint(x: 27.0, y: y))
            }
            let lines = self.makeShapeLayer(path: latitudes)
            lines.fillColor = nil
            lines.strokeColor = UIColor.black.cgColor
            lines.lineWidth = CGFloat(G.gap)
            mask.addSublayer(lines)
            for _ in 0 ..< 2 {
                let meridian = self.makeShapeLayer(path: nil)
                meridian.fillColor = nil
                meridian.strokeColor = UIColor.black.cgColor
                meridian.lineWidth = CGFloat(G.gap)
                mask.addSublayer(meridian)
                self.turningMeridianLayers.append(meridian)
            }
            holes.mask = mask
            globe.addSublayer(holes)
        }
        self.turningGlobeLayer = globe
        return globe
    }

    /// A hole: the tile's image, seen through the moving shapes (and the groups and clips around them).
    private func makeHole(_ ancestors: [LivingIconNode], _ holes: [LivingIconNode], tileImage: UIImage) -> CALayer {
        let hole = SimpleLayer()
        hole.frame = CGRect(origin: CGPoint(), size: LivingSettingsIconLayer.glyphSize)
        hole.contents = tileImage.cgImage
        hole.contentsScale = tileImage.scale

        let root = self.makeGroupLayer()
        var parent: CALayer = root
        for ancestor in ancestors {
            let layer = self.makeGroupLayer()
            switch ancestor {
            case let .group(name, _):
                if let name = name {
                    self.parts[name, default: []].append(layer)
                }
            case let .clipped(geometry, _):
                let mask = self.makeShapeLayer(path: geometry.makePath())
                mask.fillColor = UIColor.black.cgColor
                layer.mask = mask
            default:
                break
            }
            parent.addSublayer(layer)
            parent = layer
        }
        self.buildMask(holes, into: parent, ancestors: ancestors)
        hole.mask = root
        return hole
    }

    /// The holes' shapes as an opaque mask, their part layers registered with the visible ones.
    private func buildMask(_ nodes: [LivingIconNode], into parent: CALayer, ancestors: [LivingIconNode]) {
        for node in nodes {
            switch node {
            case let .group(name, children):
                let layer = self.makeGroupLayer()
                parent.addSublayer(layer)
                if let name = name {
                    self.parts[name, default: []].append(layer)
                }
                self.buildMask(children, into: layer, ancestors: ancestors + [node])
            case let .shape(shape):
                let layer = self.makeShapeLayer(path: shape.geometry.makePath())
                if let stroke = shape.stroke {
                    layer.fillColor = nil
                    layer.strokeColor = UIColor.black.cgColor
                    layer.lineWidth = CGFloat(stroke)
                    layer.lineCap = shape.roundCap ? .round : .butt
                    layer.miterLimit = 4.0
                } else {
                    layer.fillColor = UIColor.black.cgColor
                    layer.fillRule = shape.evenOdd ? .evenOdd : .nonZero
                }
                if let clip = shape.clip {
                    let mask = self.makeShapeLayer(path: clip.makePath())
                    mask.fillColor = UIColor.black.cgColor
                    layer.mask = mask
                }
                if let reveal = shape.reveal {
                    self.addReveal(reveal, to: layer, ancestors: ancestors)
                }
                parent.addSublayer(layer)
            case let .clipped(geometry, children):
                let layer = self.makeGroupLayer()
                let mask = self.makeShapeLayer(path: geometry.makePath())
                mask.fillColor = UIColor.black.cgColor
                layer.mask = mask
                parent.addSublayer(layer)
                self.buildMask(children, into: layer, ancestors: ancestors + [node])
            case let .cutout(white, _):
                self.buildMask(white, into: parent, ancestors: ancestors)
            case let .typingDot(index, children):
                let layer = self.makeGroupLayer()
                parent.addSublayer(layer)
                self.typingDotLayers[index, default: []].append(layer)
                self.buildMask(children, into: layer, ancestors: ancestors + [node])
            case let .turningGlobe(rest):
                self.buildMask(rest, into: parent, ancestors: ancestors)
            case .paper:
                break
            }
        }
    }

    // MARK: - A frame

    /// Draws the rig's frame at its time `frame.t` (`update()` + `run()`), the tile's pop and sheen included.
    func apply(_ frame: LivingIconFrame) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer {
            CATransaction.commit()
        }

        for (name, transform) in frame.parts {
            let m = transform.matrix
            let affine = CGAffineTransform(a: CGFloat(m.a), b: CGFloat(m.b), c: CGFloat(m.c), d: CGFloat(m.d), tx: CGFloat(m.tx), ty: CGFloat(m.ty))
            for layer in self.parts[name] ?? [] {
                layer.setAffineTransform(affine)
                layer.opacity = Float(transform.o)
            }
        }
        for (name, value) in frame.dashes {
            // A stroked part drawn back (0: whole … 1: none); fully drawn back it is gone (no round-cap dot).
            for layer in self.dashTargets[name] ?? [] {
                layer.strokeEnd = CGFloat(1.0 - LivingIconCurves.clamp(value))
                layer.opacity = value >= 0.995 ? 0.0 : 1.0
            }
        }
        if let bookmark = frame.bookmark {
            self.bookmarkLayer?.path = LivingIconPath.path(LivingIconArtwork.bookmark(bookmark.n, bookmark.f, bookmark.g))
        }
        if let shine = frame.shine, let layer = self.shineLayer {
            layer.strokeEnd = CGFloat(1.0 - LivingIconCurves.clamp(shine.dashOffset))
            layer.opacity = Float(shine.opacity)
        }
        if let inner = frame.inner, let layer = self.innerSparkleLayer {
            // rotate(r) and scale(s) round the sparkle's centre.
            let scale = CGFloat(inner.scale)
            layer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(inner.rotation * Double.pi / 180.0)).scaledBy(x: scale, y: scale))
        }

        var glint: Double?
        var glyphShadow: (radius: Double, alpha: Double)?
        var hue: Double?
        var spin: Double?
        for call in frame.effects {
            switch call {
            case let .waves(t, t0, n):
                self.applyWaves(LivingIconFX.waves(t, t0, n))
            case let .glow(t, t0, k):
                glyphShadow = LivingIconFX.glow(t, t0, k)
            case let .glint(t, t0):
                glint = LivingIconFX.glint(t, t0)
            case let .halo(t, t0):
                self.applyHalo(LivingIconFX.halo(t, t0))
            case let .sparkles(t, t0, n, color):
                self.applySparkles(LivingIconFX.sparkles(t, t0, n), color: UIColor(livingIconRGB: color))
            case let .confetti(t, t0):
                self.applyConfetti(LivingIconFX.confetti(t, t0))
            case let .dots(t, t0):
                self.applyDots(LivingIconFX.dots(t, t0))
            case let .rays(t, t0):
                self.applyRays(LivingIconFX.rays(t, t0))
            case let .stroke(t, t0):
                self.applyStroke(LivingIconFX.stroke(t, t0))
            case let .paper(open):
                let paper = LivingIconFX.paper(open)
                self.paperLayer?.path = CGPath(roundedRect: CGRect(x: 9.0, y: paper.y, width: 12.0, height: 9.0), cornerWidth: 1.2, cornerHeight: 1.2, transform: nil)
                self.paperLayer?.opacity = Float(paper.opacity)
            case let .flash(t, t0):
                self.applyFlash(LivingIconFX.flash(t, t0))
            case let .hue(t, d):
                hue = LivingIconFX.hue(t, d)
            case let .spin3d(t, t0, d):
                spin = LivingIconFX.spin3d(t, t0, d)
            case let .globe(u):
                let globe = LivingIconFX.globe(u)
                if let turningGlobe = self.turningGlobeLayer {
                    typealias G = LivingIconArtwork.TurningGlobe
                    for (index, rx) in [globe.rx0, globe.rx1].enumerated() where index < self.turningMeridianLayers.count {
                        let width = max(0.01, rx * G.meridianScale)
                        self.turningMeridianLayers[index].path = CGPath(ellipseIn: CGRect(x: G.center.0 - width, y: G.center.1 - G.meridianHeight, width: 2.0 * width, height: 2.0 * G.meridianHeight), transform: nil)
                    }
                    if self.turningMeridianLayers.count > 1 {
                        self.turningMeridianLayers[1].opacity = Float(globe.opacity1)
                    }
                    // Over the banded globe, opaque where it is drawn (its gaps show the tile): fading it in and
                    // out is the prototype's cross-fade.
                    turningGlobe.opacity = Float(LivingIconFX.globeCrossFade(frame.t, duration: self.rig.duration))
                }
            }
        }

        // The glyph's filters: a white drop shadow (CSS blur radius = 2σ; a layer's shadow radius is σ).
        if let glyphShadow = glyphShadow {
            self.glyphLayer.shadowColor = UIColor.white.cgColor
            self.glyphLayer.shadowOffset = CGSize()
            self.glyphLayer.shadowRadius = CGFloat(glyphShadow.radius / 2.0)
            self.glyphLayer.shadowOpacity = Float(glyphShadow.alpha)
        } else {
            self.glyphLayer.shadowOpacity = 0.0
        }
        self.applyHue(hue)
        // perspective(60px) rotateY(a) about the centre: the glyph (or Money's image) turns round.
        let turning = self.elementLayer ?? self.glyphLayer
        if let spin = spin {
            var perspective = CATransform3DIdentity
            perspective.m34 = -1.0 / CGFloat(LivingIconFX.spinPerspective)
            turning.transform = CATransform3DConcat(CATransform3DMakeRotation(CGFloat(spin * Double.pi / 180.0), 0.0, 1.0, 0.0), perspective)
        } else {
            turning.transform = CATransform3DIdentity
        }

        // The tile: a spring pop, and the sheen crossing it (a glint sends it across again).
        if let tileLayer = self.tileLayer {
            let scale = CGFloat(LivingIconFX.tileScale(frame.t))
            tileLayer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        }
        if let sheenLayer = self.sheenLayer {
            let offset = glint ?? LivingIconFX.sheenOffset(frame.t)
            sheenLayer.setAffineTransform(CGAffineTransform(translationX: CGFloat(offset / 100.0) * sheenLayer.bounds.width, y: 0.0))
        }
    }

    // MARK: - Effects

    private func applyWaves(_ arcs: [LivingIconFX.Arc]) {
        if self.waveLayers == nil {
            // Sound waves: arcs on both sides (stroke 1.4, round caps).
            self.waveLayers = arcs.map { arc -> CAShapeLayer in
                let layer = self.makeShapeLayer(path: LivingIconPath.path(arc.side > 0.0 ? "M25 10.5a6 6 0 0 1 0 9" : "M5 10.5a6 6 0 0 0 0 9"))
                self.paint(layer, color: self.iconStyle.glyphColor, stroke: 1.4, roundCap: true, evenOdd: false)
                self.glyphLayer.addSublayer(layer)
                return layer
            }
        }
        for (layer, arc) in zip(self.waveLayers ?? [], arcs) {
            layer.opacity = Float(arc.opacity)
            layer.setAffineTransform(CGAffineTransform(translationX: CGFloat(arc.dx), y: 0.0))
        }
    }

    private func applyHalo(_ halo: (opacity: Double, scale: Double)) {
        let layer: CAShapeLayer
        if let current = self.haloLayer {
            layer = current
        } else {
            // A 2 pt ring of the tile's colour round the tile (box-shadow 0 0 0 2px on a 9 pt-round box).
            layer = SimpleShapeLayer()
            layer.bounds = CGRect(origin: CGPoint(), size: LivingSettingsIconLayer.glyphSize)
            layer.position = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
            layer.contentsScale = self.screenScale
            let path = CGMutablePath()
            path.addRoundedRect(in: CGRect(x: -2.0, y: -2.0, width: 34.0, height: 34.0), cornerWidth: 11.0, cornerHeight: 11.0)
            path.addRoundedRect(in: CGRect(x: 0.0, y: 0.0, width: 30.0, height: 30.0), cornerWidth: 9.0, cornerHeight: 9.0)
            layer.path = path
            layer.fillRule = .evenOdd
            layer.fillColor = self.iconStyle.tileColor.cgColor
            self.fxLayer.addSublayer(layer)
            self.haloLayer = layer
        }
        layer.opacity = Float(halo.opacity)
        layer.setAffineTransform(CGAffineTransform(scaleX: CGFloat(halo.scale), y: CGFloat(halo.scale)))
    }

    private func applySparkles(_ sparkles: [LivingIconFX.Sparkle], color: UIColor) {
        if self.sparkleLayers == nil {
            // 7 × 7 four-point stars: polygon(50% 0, 62% 38%, 100% 50%, 62% 62%, 50% 100%, 38% 62%, 0 50%, 38% 38%).
            let star = CGMutablePath()
            let points: [(CGFloat, CGFloat)] = [(0.5, 0.0), (0.62, 0.38), (1.0, 0.5), (0.62, 0.62), (0.5, 1.0), (0.38, 0.62), (0.0, 0.5), (0.38, 0.38)]
            for (i, p) in points.enumerated() {
                let point = CGPoint(x: p.0 * 7.0, y: p.1 * 7.0)
                if i == 0 {
                    star.move(to: point)
                } else {
                    star.addLine(to: point)
                }
            }
            star.closeSubpath()
            self.sparkleLayers = sparkles.map { _ -> CAShapeLayer in
                let layer = SimpleShapeLayer()
                layer.bounds = CGRect(x: 0.0, y: 0.0, width: 7.0, height: 7.0)
                layer.contentsScale = self.screenScale
                layer.path = star
                layer.fillColor = color.cgColor
                layer.opacity = 0.0
                self.fxLayer.addSublayer(layer)
                return layer
            }
        }
        let center = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
        for (layer, sparkle) in zip(self.sparkleLayers ?? [], sparkles) {
            layer.opacity = Float(sparkle.opacity)
            layer.position = CGPoint(x: center.x + CGFloat(sparkle.x), y: center.y + CGFloat(sparkle.y))
            layer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(sparkle.rotation * Double.pi / 180.0)).scaledBy(x: CGFloat(sparkle.scale), y: CGFloat(sparkle.scale)))
        }
    }

    private func applyConfetti(_ pieces: [LivingIconFX.Confetto]) {
        if self.confettiLayers == nil {
            // 4 × 6 pieces, corner 1, from (50 %, 42 %) of the box 20 pt round the tile.
            self.confettiLayers = pieces.indices.map { i -> CALayer in
                let layer = SimpleLayer()
                layer.bounds = CGRect(x: 0.0, y: 0.0, width: 4.0, height: 6.0)
                layer.cornerRadius = 1.0
                layer.backgroundColor = UIColor(livingIconRGB: LivingIconFX.confettiColors[i % LivingIconFX.confettiColors.count]).cgColor
                layer.opacity = 0.0
                self.fxLayer.addSublayer(layer)
                return layer
            }
        }
        let origin = CGPoint(x: self.bounds.midX, y: -20.0 + 0.42 * (self.bounds.height + 40.0))
        for (layer, piece) in zip(self.confettiLayers ?? [], pieces) where piece.isLaunched {
            layer.opacity = Float(piece.opacity)
            layer.position = CGPoint(x: origin.x + CGFloat(piece.x), y: origin.y + CGFloat(piece.y))
            layer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(piece.rotation * Double.pi / 180.0)))
        }
    }

    /// The bubble's own dots (holes in it) bounce: `translate(0 dy)`.
    private func applyDots(_ offsets: [Double]) {
        for (index, dy) in offsets.enumerated() {
            for layer in self.typingDotLayers[index] ?? [] {
                layer.setAffineTransform(CGAffineTransform(translationX: 0.0, y: CGFloat(dy)))
            }
        }
    }

    private func applyRays(_ opacity: Double) {
        if self.rayLayers == nil {
            // Five rays over the lamp, from radius 10.5 to 13.5 round (15, 11), 38° apart.
            self.rayLayers = (0 ..< 5).map { i -> CAShapeLayer in
                let a = (-90.0 + Double(i - 2) * 38.0) * Double.pi / 180.0
                let path = CGMutablePath()
                path.move(to: CGPoint(x: 15.0 + cos(a) * 10.5, y: 11.0 + sin(a) * 10.5))
                path.addLine(to: CGPoint(x: 15.0 + cos(a) * 13.5, y: 11.0 + sin(a) * 13.5))
                let layer = self.makeShapeLayer(path: path)
                self.paint(layer, color: self.iconStyle.glyphColor, stroke: 1.5, roundCap: true, evenOdd: false)
                self.glyphLayer.addSublayer(layer)
                return layer
            }
        }
        for layer in self.rayLayers ?? [] {
            layer.opacity = Float(opacity)
        }
    }

    private func applyStroke(_ stroke: (dashOffset: Double, opacity: Double)) {
        let layer: CAShapeLayer
        if let current = self.strokeLayer {
            layer = current
        } else {
            // The brush's paint stroke (stroke 1.6, round caps), drawn on along its length.
            layer = self.makeShapeLayer(path: LivingIconPath.path("M4.5 26.2c3-1 6.5-1.2 9.8-.4"))
            self.paint(layer, color: self.iconStyle.glyphColor, stroke: 1.6, roundCap: true, evenOdd: false)
            self.glyphLayer.addSublayer(layer)
            self.strokeLayer = layer
        }
        layer.strokeEnd = CGFloat(1.0 - stroke.dashOffset)
        layer.opacity = Float(stroke.opacity)
    }

    private func applyFlash(_ flash: (opacity: Double, radius: Double)) {
        let layer: CAShapeLayer
        if let current = self.flashLayer {
            layer = current
        } else {
            layer = self.makeShapeLayer(path: nil)
            self.paint(layer, color: self.iconStyle.glyphColor, stroke: nil, roundCap: false, evenOdd: false)
            self.glyphLayer.addSublayer(layer)
            self.flashLayer = layer
        }
        layer.path = LivingIconPath.circle(cx: 15.0, cy: 15.3, r: flash.radius)
        layer.opacity = Float(flash.opacity)
    }

    /// `hue-rotate(degrees) saturate(1.4)` over the glyph: every colour in it turned (nil: their own colours).
    private func applyHue(_ degrees: Double?) {
        for item in self.colored {
            var color = item.color
            if let degrees = degrees {
                var r: CGFloat = 0.0
                var g: CGFloat = 0.0
                var b: CGFloat = 0.0
                var a: CGFloat = 0.0
                if item.color.getRed(&r, green: &g, blue: &b, alpha: &a) {
                    let turned = LivingIconFX.filterColor(red: Double(r), green: Double(g), blue: Double(b), hueDegrees: degrees, saturation: LivingIconFX.hueSaturation)
                    color = UIColor(red: CGFloat(turned.red), green: CGFloat(turned.green), blue: CGFloat(turned.blue), alpha: a)
                }
            } else if !self.rig.flags.contains(.hue) {
                continue
            }
            if item.isStroke {
                item.layer.strokeColor = color.cgColor
            } else {
                item.layer.fillColor = color.cgColor
            }
        }
    }
}
