import Foundation
import UIKit
import AsyncDisplayKit
import Display

/// The light a glass element's rim catches (see `GlassLightWaveNode.spillTargets`).
public struct GlassLightSpill: Equatable {
    /// The light's colour (opaque) and strength, 0…0.95.
    public var color: UIColor
    public var alpha: CGFloat
    /// Unit vector from the element's centre toward the light (the avatar): the rim on that side catches it.
    public var direction: CGPoint

    public init(color: UIColor, alpha: CGFloat, direction: CGPoint) {
        self.color = color
        self.alpha = alpha
        self.direction = direction
    }
}

/// An rgb colour, 0…1 per channel (light.js / turn-light.js colour arithmetic).
struct GlassLightRGB: Equatable {
    var r: Double
    var g: Double
    var b: Double

    static let white = GlassLightRGB(r: 1.0, g: 1.0, b: 1.0)

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(_ color: UIColor) {
        var r: CGFloat = 1.0, g: CGFloat = 1.0, b: CGFloat = 1.0, a: CGFloat = 1.0
        if !color.getRed(&r, green: &g, blue: &b, alpha: &a) {
            var white: CGFloat = 1.0
            if color.getWhite(&white, alpha: &a) {
                r = white
                g = white
                b = white
            }
        }
        self.init(r: Double(max(0.0, min(1.0, r))), g: Double(max(0.0, min(1.0, g))), b: Double(max(0.0, min(1.0, b))))
    }

    init(_ rgb: SIMD3<Float>) {
        self.init(r: Double(max(0.0, min(1.0, rgb.x))), g: Double(max(0.0, min(1.0, rgb.y))), b: Double(max(0.0, min(1.0, rgb.z))))
    }

    /// light.js `lighten`: v + (1 − v)·k.
    func lightened(_ k: Double) -> GlassLightRGB {
        return GlassLightRGB(r: self.r + (1.0 - self.r) * k, g: self.g + (1.0 - self.g) * k, b: self.b + (1.0 - self.b) * k)
    }

    /// turn-light.js `mix`: self + (other − self)·t.
    func mixed(with other: GlassLightRGB, _ t: Double) -> GlassLightRGB {
        return GlassLightRGB(r: self.r + (other.r - self.r) * t, g: self.g + (other.g - self.g) * t, b: self.b + (other.b - self.b) * t)
    }

    func color(alpha: Double) -> UIColor {
        return UIColor(red: CGFloat(self.r), green: CGFloat(self.g), blue: CGFloat(self.b), alpha: CGFloat(max(0.0, min(1.0, alpha))))
    }

    /// Rounded components, to tell a real colour change from float noise (light.js keys colours by `toFixed`).
    func key(_ digits: Double) -> SIMD3<Double> {
        return SIMD3<Double>((self.r * digits).rounded(), (self.g * digits).rounded(), (self.b * digits).rounded())
    }
}

/// One colour stop of a radial gradient: `offset` 0…1 from the inner to the outer radius.
struct GlassLightGradientStop {
    var offset: CGFloat
    var color: GlassLightRGB
    var alpha: Double
}

/// canvas `createRadialGradient(c, r0, c, r1)` on a radial `CAGradientLayer` whose frame is already set: inside r0 the
/// first stop's colour, past r1 the last one's. `center` is in the layer's own coordinates.
func glassLightSetRadialGradient(_ layer: CAGradientLayer, center: CGPoint, innerRadius r0: CGFloat, outerRadius r1: CGFloat, stops: [GlassLightGradientStop]) {
    let size = layer.bounds.size
    guard size.width > 0.0, size.height > 0.0, r1 > 0.0, let first = stops.first else {
        layer.isHidden = true
        return
    }
    layer.startPoint = CGPoint(x: center.x / size.width, y: center.y / size.height)
    layer.endPoint = CGPoint(x: (center.x + r1) / size.width, y: (center.y + r1) / size.height)
    var locations: [NSNumber] = [0.0]
    var colors: [CGColor] = [first.color.color(alpha: first.alpha).cgColor]
    var last: CGFloat = 0.0
    for stop in stops {
        // Locations must not decrease; equal ones make a hard step, as coincident canvas stops do.
        let location = max(last, min(1.0, (r0 + stop.offset * (r1 - r0)) / r1))
        last = location
        locations.append(NSNumber(value: Double(location)))
        colors.append(stop.color.color(alpha: stop.alpha).cgColor)
    }
    layer.locations = locations
    layer.colors = colors
}

/// The light of the glass colour — the native twin of prototype/src/ui/light.js (same timings and curves).
///
/// Picking a glass colour sends a ring of that colour's light from the avatar across the screen (1.1 s: ~0.35 s across
/// the header, the rest of the screen by the end) with a flash where it starts, an optional glint on the cover's emoji
/// pattern (`setPatternMask`), and light on the rims of glass elements facing the avatar (`spillTargets` →
/// `spillUpdated`, drawn by `GlassLightSpillLayer` in the navigation buttons). A soft glow of the colour stays around the
/// avatar, cross-fading from the previous colour over the first 35 % of the wave and brighter while the photo is held
/// (`setLift`).
///
/// Dark theme: every layer is screen-blended (`screenBlendMode`), so the node only adds light. Light theme: screen would
/// vanish on white, so the light is a soft coloured band blended normally, the ring at 0.42 of its strength (light.js).
/// The node belongs right above the profile cover: the avatar, title and buttons sit above it, so the avatar stays clear
/// (light.js cuts a hole there). The ring draws only while it runs (`SharedDisplayLinkDriver`); the glow and the rim
/// lights are fixed gradients and shadows whose opacity changes (light.js: "scrolling and holding cost no repaint").
public final class GlassLightWaveNode: ASDisplayNode {
    /// light.js `WAVE`.
    public static let waveDuration: Double = 1.1
    /// light.js `GLOW`: radius of the glow layer.
    private static let glowRadius: CGFloat = 180.0

    /// Frames, in this node's coordinates, of glass elements whose rims catch the light (empty: none); read on every
    /// frame of the wave and on every static update.
    public var spillTargets: (() -> [CGRect])?
    /// The light on each of `spillTargets` (nil: none), whenever it changes.
    public var spillUpdated: (([GlassLightSpill?]) -> Void)?

    private struct Wave {
        var start: Double
        var color: GlassLightRGB
        var strength: Double
    }

    /// light.js `ring(u)`: the ring's radius, width and intensity (pt) at wave progress u.
    private struct Ring {
        var u: Double
        var radius: CGFloat
        var width: CGFloat
        var intensity: Double
    }

    private var color = GlassLightRGB.white
    private var tint: Double = 0.0
    private var fromColor = GlassLightRGB.white
    private var fromTint: Double = 0.0
    private var wave: Wave?
    private var origin = CGPoint()
    private var radius: CGFloat = 50.0
    private var visibility: CGFloat = 1.0
    /// The glass while the photo is held (light.js `setLift`): the glow and the rims' rest light brighten.
    private var lift: CGFloat = 0.0
    private var isDark = true
    private var patternFrame: CGRect = .zero
    private var displayLink: SharedDisplayLinkDriver.Link?
    private var lastSpill: [GlassLightSpill?] = []

    /// The glow around the avatar: two layers (the colour, and the one it replaces fading out).
    private let glowLayers: [SimpleGradientLayer] = [SimpleGradientLayer(), SimpleGradientLayer()]
    private var glowColors: [GlassLightRGB] = [.white, .white]
    private var frontGlow = 0
    private let ringLayer = SimpleGradientLayer()
    private let flashLayer = SimpleGradientLayer()
    private let glintLayer = SimpleGradientLayer()
    private let glintMaskLayer = SimpleLayer()

    override public init() {
        super.init()

        self.isUserInteractionEnabled = false
        self.layer.masksToBounds = true
        for layer in self.glowLayers {
            layer.type = .radial
            // radial-gradient(circle closest-side, …): centred, reaching the sides of the square.
            layer.startPoint = CGPoint(x: 0.5, y: 0.5)
            layer.endPoint = CGPoint(x: 1.0, y: 1.0)
            layer.locations = [0.17, 0.45, 0.97]
            layer.opacity = 0.0
            self.layer.addSublayer(layer)
        }
        for layer in [self.ringLayer, self.flashLayer, self.glintLayer] {
            layer.type = .radial
            layer.isHidden = true
            self.layer.addSublayer(layer)
        }
        self.glintLayer.mask = self.glintMaskLayer
        self.updateBlending()
        self.paintGlow(0, color: self.color)
    }

    deinit {
        self.displayLink?.invalidate()
    }

    /// The light's origin (the avatar centre, in this node's coordinates), the avatar's radius as shown, how much of
    /// the light shows (light.js `setOrigin`: the header fades it as it collapses or expands) and the appearance. The
    /// ring crosses the node's bounds (the screen).
    public func update(origin: CGPoint, radius: CGFloat, visibility: CGFloat, isDark: Bool) {
        let visibility = max(0.0, min(1.0, visibility))
        if origin == self.origin && radius == self.radius && visibility == self.visibility && isDark == self.isDark {
            return
        }
        self.origin = origin
        self.radius = radius
        self.visibility = visibility
        if isDark != self.isDark {
            self.isDark = isDark
            self.updateBlending()
            self.paintGlow(0, color: self.glowColors[0])
            self.paintGlow(1, color: self.glowColors[1])
        }
        if self.displayLink == nil {
            self.draw(at: CACurrentMediaTime())
        }
    }

    /// The glass while the photo is held, 0…1 (light.js `setLift`; `GlassCoinAvatarNode.lightUpdated` gives it every
    /// frame): the glow brightens up to 1.8×, the rims' rest light up to (0.55 + 0.35) / 0.55.
    public func setLift(_ lift: CGFloat) {
        let value = max(0.0, min(1.0, lift))
        if abs(value - self.lift) < 0.004 && (value > 0.0 || self.lift == 0.0) {
            return
        }
        self.lift = value
        if self.displayLink == nil {
            self.draw(at: CACurrentMediaTime())
        }
    }

    /// A new glass colour (nil: clear glass). Animated: the wave (light.js `change`); otherwise the glow is just set
    /// (light.js `set`: restoring a saved choice). With Reduce Motion there is no wave.
    public func change(to color: UIColor?, animated: Bool) {
        let rgb = color.map { GlassLightRGB($0) } ?? .white
        let tint: Double = color != nil ? 1.0 : 0.0
        if !animated || UIAccessibility.isReduceMotionEnabled {
            self.color = rgb
            self.tint = tint
            self.fromColor = rgb
            self.fromTint = 0.0
            self.wave = nil
            self.stopDisplayLink()
            self.paintGlow(self.frontGlow, color: rgb)
            self.draw(at: CACurrentMediaTime())
            return
        }
        self.fromColor = self.color
        self.fromTint = self.tint
        self.color = rgb
        self.tint = tint
        // The old glow stays on the other layer and fades.
        self.frontGlow = 1 - self.frontGlow
        self.paintGlow(self.frontGlow, color: rgb)
        self.wave = Wave(start: CACurrentMediaTime(), color: rgb.lightened(color != nil ? 0.18 : 0.6), strength: color != nil ? 1.0 : 0.55)
        if self.displayLink == nil {
            self.displayLink = SharedDisplayLinkDriver.shared.add(framesPerSecond: .max, { [weak self] _ in
                self?.tick()
            })
        }
        self.draw(at: CACurrentMediaTime())
    }

    /// The cover's emoji pattern as a mask (its alpha) and its frame in this node: the pattern glints as the ring
    /// passes it (light.js `glint`). Optional; nil removes it.
    public func setPatternMask(_ image: UIImage?, frame: CGRect) {
        self.glintMaskLayer.contents = image?.cgImage
        self.patternFrame = image != nil ? frame : .zero
    }

    private func stopDisplayLink() {
        self.displayLink?.invalidate()
        self.displayLink = nil
    }

    private func tick() {
        let time = CACurrentMediaTime()
        if let wave = self.wave, time - wave.start >= GlassLightWaveNode.waveDuration {
            // One last draw without the ring.
            self.wave = nil
            self.stopDisplayLink()
        }
        self.draw(at: time)
    }

    /// Dark: light adds (screen). Light theme: normal blending (light.js `mix-blend-mode`).
    private func updateBlending() {
        let filter: String? = self.isDark ? "screenBlendMode" : nil
        for layer in self.glowLayers + [self.ringLayer, self.flashLayer, self.glintLayer] {
            layer.compositingFilter = filter
        }
    }

    /// light.js `paintGlow`: radial, the colour at (dark 0.2 / light 0.1) × 1.8 to 17 % of the radius, 0.55 of it at
    /// 45 %, nothing at 97 % — its strength at full lift; the layer's opacity scales it down.
    private func paintGlow(_ index: Int, color: GlassLightRGB) {
        self.glowColors[index] = color
        let a = (self.isDark ? 0.2 : 0.1) * 1.8
        self.glowLayers[index].colors = [
            color.color(alpha: a).cgColor,
            color.color(alpha: a * 0.55).cgColor,
            color.color(alpha: 0.0).cgColor
        ]
    }

    private func ring(_ u: Double) -> Ring {
        let size = self.bounds.size
        let x0 = Double(self.origin.x)
        let y0 = Double(self.origin.y)
        let x1 = Double(size.width) - x0
        let y1 = Double(size.height) - y0
        // The farthest screen corner.
        let far = max(max(x0 * x0 + y0 * y0, x1 * x1 + y0 * y0), max(x0 * x0 + y1 * y1, x1 * x1 + y1 * y1)).squareRoot()
        // Steady, gathering pace once past the header.
        let travel = 0.62 * u + 0.38 * u * u
        let radius = Double(self.radius)
        let r = radius + (far + 80.0 - radius) * travel
        let w = 30.0 + 100.0 * u
        let intensity = min(1.0, u / 0.06) * pow(1.0 - u, 1.5)
        return Ring(u: u, radius: CGFloat(r), width: CGFloat(w), intensity: intensity)
    }

    private func draw(at time: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer {
            CATransaction.commit()
        }

        // The glow cross-fades from the previous colour as the wave leaves the avatar (smoothstep over 35 %).
        var k = 1.0
        var ring: Ring?
        if let wave = self.wave {
            let u = max(0.0, min(1.0, (time - wave.start) / GlassLightWaveNode.waveDuration))
            let s = min(1.0, u / 0.35)
            k = s * s * (3.0 - 2.0 * s)
            ring = self.ring(u)
        }
        self.placeGlow(k)
        self.drawWave(ring)
        self.updateSpill(ring: self.wave != nil ? ring : nil)
    }

    /// light.js `placeGlow`: the glow layers follow the avatar; their opacity is the colour's amount × visibility ×
    /// (1 + 0.8 · lift) / 1.8.
    private func placeGlow(_ k: Double) {
        let half = GlassLightWaveNode.glowRadius
        let frame = CGRect(x: self.origin.x - half, y: self.origin.y - half, width: half * 2.0, height: half * 2.0)
        let boost = (1.0 + 0.8 * Double(self.lift)) / 1.8
        func place(_ layer: SimpleGradientLayer, amount: Double) {
            let opacity = max(0.0, min(1.0, amount * Double(self.visibility) * boost))
            layer.opacity = opacity < 0.003 ? 0.0 : Float(opacity)
            if layer.frame != frame {
                layer.frame = frame
            }
        }
        place(self.glowLayers[self.frontGlow], amount: self.tint * k)
        place(self.glowLayers[1 - self.frontGlow], amount: self.fromTint * (1.0 - k))
    }

    /// light.js `drawWave`: the ring (only the annulus it covers), the flash where it starts and the pattern glint.
    private func drawWave(_ ring: Ring?) {
        let visibility = Double(self.visibility)
        guard let wave = self.wave, let ring, ring.intensity > 0.0, visibility > 0.0 else {
            self.ringLayer.isHidden = true
            self.flashLayer.isHidden = true
            self.glintLayer.isHidden = true
            return
        }
        let c = wave.color
        // Light theme: a soft band at 0.42 of the strength (light.js `this.strength`).
        let a = 0.7 * ring.intensity * wave.strength * visibility * (self.isDark ? 1.0 : 0.42)

        let outer = ring.radius + ring.width * 0.7
        let ringFrame = CGRect(x: self.origin.x - outer, y: self.origin.y - outer, width: outer * 2.0, height: outer * 2.0).intersection(self.bounds)
        if ringFrame.isNull || ringFrame.isEmpty {
            self.ringLayer.isHidden = true
        } else {
            self.ringLayer.isHidden = false
            self.ringLayer.frame = ringFrame
            GlassLightWaveNode.setRingGradient(self.ringLayer, center: CGPoint(x: self.origin.x - ringFrame.minX, y: self.origin.y - ringFrame.minY), color: c, alpha: a, radius: ring.radius, width: ring.width)
        }

        // The flash where it starts.
        let f = max(0.0, 1.0 - ring.u / 0.22)
        if f > 0.0 {
            let half: CGFloat = 130.0
            self.flashLayer.isHidden = false
            self.flashLayer.frame = CGRect(x: self.origin.x - half, y: self.origin.y - half, width: half * 2.0, height: half * 2.0)
            glassLightSetRadialGradient(self.flashLayer, center: CGPoint(x: half, y: half), innerRadius: self.radius * 0.8, outerRadius: self.radius + 70.0, stops: [
                GlassLightGradientStop(offset: 0.0, color: c, alpha: 0.5 * f * f * wave.strength * visibility),
                GlassLightGradientStop(offset: 1.0, color: c, alpha: 0.0)
            ])
        } else {
            self.flashLayer.isHidden = true
        }

        // The emoji pattern glints as the light passes it (nothing to light once the ring has passed it).
        let pattern = self.patternFrame
        let near = hypot(max(abs(pattern.minX - self.origin.x), abs(pattern.maxX - self.origin.x)), max(abs(pattern.minY - self.origin.y), abs(pattern.maxY - self.origin.y)))
        if !pattern.isEmpty && ring.radius - ring.width <= near {
            self.glintLayer.isHidden = false
            self.glintLayer.frame = pattern
            self.glintMaskLayer.frame = CGRect(origin: CGPoint(), size: pattern.size)
            let center = CGPoint(x: self.origin.x - pattern.minX, y: self.origin.y - pattern.minY)
            GlassLightWaveNode.setRingGradient(self.glintLayer, center: center, color: c.lightened(0.5), alpha: min(1.0, a * 2.2), radius: ring.radius, width: ring.width * 0.8)
        } else {
            self.glintLayer.isHidden = true
        }
    }

    /// light.js `ringGradient`: transparent at r − w, 0.3 of the light at r − 0.4w, the core (the colour lightened by
    /// half) at r, 0.35 at r + w/4, transparent at r + 0.7w.
    private static func setRingGradient(_ layer: CAGradientLayer, center: CGPoint, color: GlassLightRGB, alpha: Double, radius r: CGFloat, width w: CGFloat) {
        let outer = r + w * 0.7
        guard outer > 0.0 else {
            layer.isHidden = true
            return
        }
        func at(_ x: CGFloat) -> CGFloat {
            return max(0.0, min(1.0, x / outer))
        }
        glassLightSetRadialGradient(layer, center: center, innerRadius: 0.0, outerRadius: outer, stops: [
            GlassLightGradientStop(offset: at(r - w), color: color, alpha: 0.0),
            GlassLightGradientStop(offset: at(r - w * 0.4), color: color, alpha: alpha * 0.3),
            GlassLightGradientStop(offset: at(r), color: color.lightened(0.5), alpha: alpha),
            GlassLightGradientStop(offset: at(r + w * 0.25), color: color, alpha: alpha * 0.35),
            GlassLightGradientStop(offset: 1.0, color: color, alpha: 0.0)
        ])
    }

    /// light.js `spill`: a faint constant light from the glow on rims near the avatar (brighter while the photo is
    /// held), and a bright pass when the ring crosses them.
    private func updateSpill(ring: Ring?) {
        guard let spillUpdated = self.spillUpdated else {
            return
        }
        if self.tint <= 0.0 && ring == nil && self.lastSpill.allSatisfy({ $0 == nil }) {
            // Nothing lit, and nothing was: no work (and no layers) for a glass without colour.
            return
        }
        let targets = self.spillTargets?() ?? []
        let o = self.origin
        var result: [GlassLightSpill?] = []
        for frame in targets {
            if frame.isEmpty {
                result.append(nil)
                continue
            }
            let dx = Double(o.x - frame.midX)
            let dy = Double(o.y - frame.midY)
            let d = (dx * dx + dy * dy).squareRoot()
            let nx = dx / max(1.0, d)
            let ny = dy / max(1.0, d)
            let near = max(0.0, d - 60.0) / 150.0
            let rest = self.tint * (0.55 + 0.35 * Double(self.lift)) * exp(-near * near)
            var pass = 0.0
            var color = self.color
            if let wave = self.wave, let ring, ring.intensity > 0.0 {
                let edge = d - Double(max(frame.width, frame.height)) * 0.3
                let x = (edge - Double(ring.radius)) / (Double(ring.width) * 0.6)
                pass = ring.intensity * exp(-x * x) * wave.strength
                color = wave.color
            }
            let a = min(0.95, (rest + pass * 1.2) * Double(self.visibility))
            if a < 0.01 {
                result.append(nil)
            } else {
                result.append(GlassLightSpill(color: color.lightened(0.25).color(alpha: 1.0), alpha: CGFloat(a), direction: CGPoint(x: nx, y: ny)))
            }
        }
        if result != self.lastSpill {
            self.lastSpill = result
            spillUpdated(result)
        }
    }
}

/// The light on a glass element's rim, as the prototype draws it (light.js `spillLayer`: an inset box-shadow of the
/// light's colour, offset 5 pt away from the light, 10 pt blur, −3 pt spread, on a layer whose opacity is the light's
/// strength). Add it to the element above its glass background and below its content, size it to the element and pass
/// it the element's spill: the shadow is rebuilt only when the colour, the direction or the shape change; otherwise
/// only the opacity does.
public final class GlassLightSpillLayer: SimpleLayer {
    private struct Key: Equatable {
        var color: SIMD4<Double>
        var direction: SIMD2<Double>
        var size: CGSize
        var cornerRadius: CGFloat
        var blur: CGFloat
    }

    private let shadowLayer = SimpleShapeLayer()
    private var key: Key?

    override public init() {
        super.init()
        self.masksToBounds = true
        self.isHidden = true
        self.shadowLayer.fillColor = UIColor.black.cgColor
        self.shadowLayer.fillRule = .evenOdd
        self.shadowLayer.shadowOpacity = 1.0
        self.addSublayer(self.shadowLayer)
    }

    override public init(layer: Any) {
        super.init(layer: layer)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// `blur` is the CSS blur radius (10 for the glass colour's light, 11 for the turn light's rim).
    public func update(spill: GlassLightSpill?, size: CGSize, cornerRadius: CGFloat, blur: CGFloat = 10.0) {
        guard let spill, spill.alpha >= 0.01, size.width > 0.0, size.height > 0.0 else {
            self.isHidden = true
            return
        }
        var r: CGFloat = 1.0, g: CGFloat = 1.0, b: CGFloat = 1.0, a: CGFloat = 1.0
        if !spill.color.getRed(&r, green: &g, blue: &b, alpha: &a) {
            var white: CGFloat = 1.0
            if spill.color.getWhite(&white, alpha: &a) {
                r = white
                g = white
                b = white
            }
        }
        // light.js keys the shadow by the colour (3 decimals) and the direction (2 decimals).
        let key = Key(
            color: (SIMD4<Double>(Double(r), Double(g), Double(b), Double(a)) * 1000.0).rounded(.toNearestOrAwayFromZero),
            direction: (SIMD2<Double>(Double(spill.direction.x), Double(spill.direction.y)) * 100.0).rounded(.toNearestOrAwayFromZero),
            size: size,
            cornerRadius: cornerRadius,
            blur: blur
        )
        if key != self.key {
            self.key = key
            self.cornerRadius = cornerRadius
            let bounds = CGRect(origin: CGPoint(), size: size)
            self.shadowLayer.frame = bounds
            // The outside of the element (grown by the −3 pt spread) casts the shadow inward, onto the rim that faces
            // the light; the element's own bounds clip the rest.
            let path = CGMutablePath()
            path.addRect(bounds.insetBy(dx: -40.0, dy: -40.0))
            path.addPath(UIBezierPath(roundedRect: bounds.insetBy(dx: -3.0, dy: -3.0), cornerRadius: cornerRadius + 3.0).cgPath)
            self.shadowLayer.path = path
            self.shadowLayer.shadowPath = path
            self.shadowLayer.shadowColor = spill.color.cgColor
            // CSS blur b pt ≈ CALayer shadowRadius b / 2.
            self.shadowLayer.shadowRadius = blur / 2.0
            self.shadowLayer.shadowOffset = CGSize(width: -CGFloat(key.direction.x) / 100.0 * 5.0, height: -CGFloat(key.direction.y) / 100.0 * 5.0)
        }
        self.isHidden = false
        self.opacity = Float(spill.alpha)
    }
}
