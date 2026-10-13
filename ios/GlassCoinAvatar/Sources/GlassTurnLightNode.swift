import Foundation
import UIKit
import AsyncDisplayKit
import Display

/// The light of the glass colour while the photo turns — the native twin of prototype/src/ui/turn-light.js (the same
/// constants and curves, function for function). Only with a colour chosen: clear glass stays plain, and so does
/// Reduce Motion. The glass face throws its colour as it tilts:
/// · the name and the line under it are swept by it: a band of the colour crosses the letters in the direction the
///   photo turns (turn it right and the light runs over the name from left to right; turn it back and it runs back),
///   once every quarter turn — a sawtooth along the direction the face looks, so a spin sweeps them again and again; the
///   letters light up in the colour and glow around the band (`shineLines`);
/// · a fast spin washes the whole line in the colour instead;
/// · a sheen crosses the glass buttons with the light, and their rim facing the avatar lights up (`lightButtons`);
/// · a soft aura of the colour grows around the photo (`auraLayer`; in the emoji pattern too once `setPatternMask` has
///   the pattern).
/// Nothing moves across the background itself; it all fades with the glass when the photo lands.
///
/// It shows only while the header is at rest (turn-light.js: the light's origin at the avatar's rest position) and is
/// driven by the glass frame by frame through `update(light:)` (`GlassCoinAvatarNode.lightUpdated`): no display link of
/// its own, nothing at all while it rests, and per frame only opacities and transforms (the glow of each line is
/// blurred once, off the main thread, when its text changes).
///
/// Placement (`PeerInfoHeaderNode`): this node over the title and subtitle, its frame at the origin of the header (the
/// coordinates of `update(size:avatarCenter:visibility:isAtRest:)`); `auraLayer` above the cover and under the avatar,
/// in a layer with the same coordinates; the buttons' light inside each `Button.layer`, over its glass and under its
/// content.
public final class GlassTurnLightNode: ASDisplayNode {
    /// A line of the header the light sweeps: its glyphs (only their alpha is used) and where they are.
    public struct Line {
        public var image: CGImage
        /// The glyph image's frame in this node's coordinates.
        public var frame: CGRect
        /// The band's strength on this line and its glow's (turn-light.js: the name 1 and 1, the line under it 0.85 and
        /// 0.7).
        public var strength: CGFloat
        public var glow: CGFloat

        public init(image: CGImage, frame: CGRect, strength: CGFloat, glow: CGFloat) {
            self.image = image
            self.frame = frame
            self.strength = strength
            self.glow = glow
        }

        /// The glyphs a text layer shows (an `ImmediateTextNode`'s layer: its `contents`, stretched over its bounds),
        /// measured in `container` (this node's layer). Nil for an empty layer or one that doesn't show (hidden, or
        /// transparent itself or through a superlayer).
        public init?(textLayer: CALayer, in container: CALayer, strength: CGFloat, glow: CGFloat) {
            guard let contents = textLayer.contents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID else {
                return nil
            }
            var opacity: Float = 1.0
            var layer: CALayer? = textLayer
            while let current = layer {
                if current.isHidden {
                    return nil
                }
                opacity *= current.opacity
                layer = current.superlayer
            }
            guard opacity > 0.01 else {
                return nil
            }
            let image = contents as! CGImage
            let frame = textLayer.convert(textLayer.bounds, to: container)
            guard frame.width > 0.0, frame.height > 0.0 else {
                return nil
            }
            self.init(image: image, frame: frame, strength: strength, glow: glow)
        }
    }

    /// A glass button whose rim and sheen catch the light (turn-light.js `makeButton`).
    public struct Button {
        /// Where its light goes, the size of the button: over its glass, under its content.
        public var layer: CALayer
        public var cornerRadius: CGFloat

        public init(layer: CALayer, cornerRadius: CGFloat) {
            self.layer = layer
            self.cornerRadius = cornerRadius
        }
    }

    /// The lines to sweep, measured in this node's coordinates when the light wakes (the header is at rest then).
    public var lines: (() -> [Line])?
    /// The glass buttons, read when the light wakes.
    public var buttons: (() -> [Button])?

    /// The aura (turn-light.js `paint`): a soft glow of the colour around the photo, screen-blended, clipped to the
    /// header. The host puts it above the cover and under the avatar, in a layer with this node's coordinates.
    public let auraLayer: SimpleLayer

    /// Whether the light shows (it woke and hasn't rested since).
    public private(set) var isActive = false

    /// turn-light.js `REACH`: the tilt at which the light has left the header.
    private static let reach: Double = 62.0 * Double.pi / 180.0
    /// `WIDTH`: half-width of the light passing over the letters and buttons (pt).
    private static let lightWidth: Double = 46.0
    /// `LENGTH`: half-length (covers the header from the bar to the subtitle, pt).
    private static let lightLength: Double = 260.0
    /// `SWEEP`: tilt (rad) for the band to cross the letters (one quarter turn ≈ one sweep).
    private static let sweep: Double = 1.2
    /// `paint`: the aura's radii (pt) and its strength in the pattern.
    private static let auraInnerRadius: CGFloat = 44.0
    private static let auraOuterRadius: CGFloat = 230.0
    private static let patternGlint: Double = 2.6

    /// Where the light is this frame, and its colours (turn-light.js `b`).
    private struct Beam {
        var x: Double
        var y: Double
        var dir: CGPoint
        var angle: CGFloat
        var w: Double
        var I: Double
        var T: Double
        var sweep: Double
        var wash: Double
        var aura: Double
        var hot: GlassLightRGB
        var body: GlassLightRGB
    }

    private var headerSize = CGSize()
    private var origin = CGPoint()
    private var visibility: CGFloat = 1.0
    private var isAtRest = true
    /// The light's position and face last frame: a jump across the header within a face is smeared, not strobed.
    private var previous: (x: Double, y: Double, face: Int)?
    private var colorKey: SIMD4<Double>?
    private var lineLights: [LineLight] = []
    private var buttonLights: [ButtonLight] = []
    private let auraGradientLayer = SimpleGradientLayer()
    private let patternGlintLayer = SimpleGradientLayer()
    private let patternMaskLayer = SimpleLayer()
    private var patternFrame: CGRect = .zero

    override public init() {
        self.auraLayer = SimpleLayer()
        super.init()

        self.isUserInteractionEnabled = false
        self.auraLayer.masksToBounds = true
        self.auraLayer.isHidden = true
        for layer in [self.auraGradientLayer, self.patternGlintLayer] {
            layer.type = .radial
            layer.compositingFilter = "screenBlendMode"
            layer.opacity = 0.0
            self.auraLayer.addSublayer(layer)
        }
        self.patternGlintLayer.mask = self.patternMaskLayer
        self.patternGlintLayer.isHidden = true
    }

    override public func didExitHierarchy() {
        super.didExitHierarchy()
        self.rest()
    }

    /// The header at rest: its size (the banner: the light leaves it there), the avatar centre, how much of the light
    /// shows (as `GlassLightWaveNode`'s) and whether the header is at rest — not scrolled, pulled, expanded or in a
    /// transition (turn-light.js: no light unless the avatar is at its rest position).
    public func update(size: CGSize, avatarCenter: CGPoint, visibility: CGFloat, isAtRest: Bool) {
        let visibility = max(0.0, min(1.0, visibility))
        if size == self.headerSize && avatarCenter == self.origin && visibility == self.visibility && isAtRest == self.isAtRest {
            return
        }
        let geometryChanged = size != self.headerSize || avatarCenter != self.origin
        self.headerSize = size
        self.origin = avatarCenter
        self.visibility = visibility
        self.isAtRest = isAtRest
        if geometryChanged {
            self.auraLayer.frame = CGRect(origin: CGPoint(), size: size)
            self.colorKey = nil
        }
        if self.isActive && (!isAtRest || visibility <= 0.0) {
            self.rest()
        }
    }

    /// The cover's emoji pattern as a mask (its alpha) and its frame in this node: the aura lights it 2.6× (turn-light.js
    /// `draw`). Optional; nil removes it.
    public func setPatternMask(_ image: UIImage?, frame: CGRect) {
        self.patternMaskLayer.contents = image?.cgImage
        self.patternFrame = image != nil ? frame : .zero
        self.colorKey = nil
    }

    /// The glass this frame (nil: it was put down). turn-light.js `update`.
    public func update(light: GlassCoinLight?) {
        guard let light, self.isInHierarchy, !UIAccessibility.isReduceMotionEnabled else {
            self.rest()
            return
        }
        let t = glassTurnClamp(light.tint)
        let vis = self.isAtRest ? Double(self.visibility) : 0.0
        let glass = glassTurnClamp(light.glass)
        // The face toward the viewer and where it looks (screen axes, y down).
        let th = light.yaw - Double.pi * Double(glassCoinRound(light.yaw / Double.pi))
        let ph = light.pitch
        let nx = sin(th)
        let ny = sin(ph) * cos(th)
        let nl = (nx * nx + ny * ny).squareRoot()
        let psi = acos(glassTurnClamp(cos(ph) * cos(th), -1.0, 1.0))
        let spin = glassTurnSmooth(7.0, 20.0, abs(light.yawVelocity))
        // Clear glass has no colour to throw: nothing lights up.
        let strength = t < 0.02 ? 0.0 : (0.6 + 0.3 * t) * glass * vis * min(1.0, t * 1.5)
        var I = strength * glassTurnSmooth(0.04, 0.22, psi) * (1.0 - 0.7 * spin)
        // The band over the letters: on as soon as the glass leaves flat, where the sweep has got to.
        let T = strength * glassTurnSmooth(0.025, 0.12, psi) * (1.0 - 0.7 * spin)
        let sweep = glassTurnClamp(psi / GlassTurnLightNode.sweep)
        let wash = strength * spin
        let aura = strength * max(0.6 * glassTurnSmooth(0.04, 0.35, psi), spin)
        if (I < 0.004 && T < 0.004 && wash < 0.004 && aura < 0.004) || (nl < 1e-4 && wash < 0.004) {
            self.rest()
            return
        }
        if !self.isActive {
            self.wake()
        }
        let dir = nl > 1e-4 ? CGPoint(x: nx / nl, y: ny / nl) : CGPoint(x: 1.0, y: 0.0)
        let dx = Double(dir.x)
        let dy = Double(dir.y)

        // Where the light is: it leaves the avatar slowly, then runs out of the header (offscreen by REACH, so the change
        // of face at edge-on is never seen).
        let W = Double(self.headerSize.width)
        let H = Double(self.headerSize.height)
        let ox = Double(self.origin.x)
        let oy = Double(self.origin.y)
        let exitX = dx > 1e-6 ? (W - ox) / dx : (dx < -1e-6 ? -ox / dx : Double.infinity)
        let exitY = dy > 1e-6 ? (H - oy) / dy : (dy < -1e-6 ? -oy / dy : Double.infinity)
        let far = min(exitX, exitY) + GlassTurnLightNode.lightWidth * 1.6
        let D = far * pow(psi / GlassTurnLightNode.reach, 1.35)
        let bx = ox + dx * D
        let by = oy + dy * D
        // Fast enough to jump across in a frame: smear it (wider, dimmer) instead of strobing.
        var w = GlassTurnLightNode.lightWidth
        let face = glassCoinRound(light.yaw / Double.pi)
        if let previous = self.previous, previous.face == face {
            let jump = ((bx - previous.x) * (bx - previous.x) + (by - previous.y) * (by - previous.y)).squareRoot()
            w = GlassTurnLightNode.lightWidth + 0.5 * jump
            I *= GlassTurnLightNode.lightWidth / w
        }
        self.previous = (bx, by, face)

        let color = GlassLightRGB(light.color)
        let beam = Beam(
            x: bx,
            y: by,
            dir: dir,
            angle: CGFloat(atan2(dy, dx)),
            w: w,
            I: I,
            T: T,
            sweep: sweep,
            wash: wash,
            aura: aura,
            hot: GlassLightRGB.white.mixed(with: color.lightened(0.6), t),
            body: GlassLightRGB(r: 0.9, g: 0.95, b: 1.0).mixed(with: color.lightened(0.22), t)
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.updateColors(beam)
        self.auraGradientLayer.opacity = Float(beam.aura)
        self.patternGlintLayer.opacity = Float(beam.aura)
        self.shineLines(beam)
        self.lightButtons(beam)
        CATransaction.commit()
    }

    /// Measures the lines and buttons (the header is at rest) and shows the layers.
    private func wake() {
        self.isActive = true
        self.previous = nil
        self.colorKey = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer {
            CATransaction.commit()
        }

        let lines = self.lines?() ?? []
        for (index, line) in lines.enumerated() {
            let lineLight: LineLight
            if index < self.lineLights.count {
                lineLight = self.lineLights[index]
            } else {
                lineLight = LineLight()
                self.lineLights.append(lineLight)
                // The glow under the shine, line after line (turn-light.js appends the glow, then the shine).
                self.layer.addSublayer(lineLight.halo)
                self.layer.addSublayer(lineLight.shine)
            }
            lineLight.set(line)
        }
        for index in lines.count ..< self.lineLights.count {
            self.lineLights[index].set(nil)
        }

        let buttons = self.buttons?() ?? []
        for (index, button) in buttons.enumerated() {
            let buttonLight: ButtonLight
            if index < self.buttonLights.count {
                buttonLight = self.buttonLights[index]
            } else {
                buttonLight = ButtonLight()
                self.buttonLights.append(buttonLight)
            }
            let frame = button.layer.convert(button.layer.bounds, to: self.layer)
            let d = hypot(self.origin.x - frame.midX, self.origin.y - frame.midY)
            let toAvatar = d > 1e-3 ? CGPoint(x: (self.origin.x - frame.midX) / d, y: (self.origin.y - frame.midY) / d) : CGPoint(x: 0.0, y: -1.0)
            buttonLight.attach(to: button, frame: frame, toAvatar: toAvatar)
        }
        for index in buttons.count ..< self.buttonLights.count {
            self.buttonLights[index].detach()
        }

        self.auraLayer.isHidden = false
    }

    /// Everything off (turn-light.js `rest`).
    private func rest() {
        guard self.isActive else {
            return
        }
        self.isActive = false
        self.previous = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.auraLayer.isHidden = true
        self.auraGradientLayer.opacity = 0.0
        self.patternGlintLayer.opacity = 0.0
        for lineLight in self.lineLights {
            lineLight.hide()
        }
        for buttonLight in self.buttonLights {
            buttonLight.hide()
        }
        CATransaction.commit()
    }

    /// The colours, set when they change (turn-light.js keys them by `toFixed(2)`).
    private func updateColors(_ beam: Beam) {
        let hot = beam.hot.key(100.0)
        let body = beam.body.key(100.0)
        let key = SIMD4<Double>(hot.x * 1000.0 + hot.y, hot.z, body.x * 1000.0 + body.y, body.z)
        if key == self.colorKey {
            return
        }
        self.colorKey = key

        // turn-light.js `paint`: radial from 44 to 230 pt, the colour at 0.36 · aura, 0.14 · aura at 45 %; the opacity is
        // the aura (it never reaches the clamp at 1).
        let radius = GlassTurnLightNode.auraOuterRadius
        let frame = CGRect(x: self.origin.x - radius, y: self.origin.y - radius, width: radius * 2.0, height: radius * 2.0)
        self.auraGradientLayer.frame = frame
        glassLightSetRadialGradient(self.auraGradientLayer, center: CGPoint(x: radius, y: radius), innerRadius: GlassTurnLightNode.auraInnerRadius, outerRadius: radius, stops: [
            GlassLightGradientStop(offset: 0.0, color: beam.body, alpha: 0.36),
            GlassLightGradientStop(offset: 0.45, color: beam.body, alpha: 0.14),
            GlassLightGradientStop(offset: 1.0, color: beam.body, alpha: 0.0)
        ])
        self.auraGradientLayer.isHidden = false
        // In the pattern: the colour lightened by 0.3, 2.6× as strong, masked by the emoji.
        if !self.patternFrame.isEmpty {
            let k = GlassTurnLightNode.patternGlint
            let pattern = self.patternFrame
            self.patternGlintLayer.frame = pattern
            self.patternMaskLayer.frame = CGRect(origin: CGPoint(), size: pattern.size)
            let body = beam.body.lightened(0.3)
            glassLightSetRadialGradient(self.patternGlintLayer, center: CGPoint(x: self.origin.x - pattern.minX, y: self.origin.y - pattern.minY), innerRadius: GlassTurnLightNode.auraInnerRadius, outerRadius: radius, stops: [
                GlassLightGradientStop(offset: 0.0, color: body, alpha: min(1.0, 0.36 * k)),
                GlassLightGradientStop(offset: 0.45, color: body, alpha: min(1.0, 0.14 * k)),
                GlassLightGradientStop(offset: 1.0, color: body, alpha: 0.0)
            ])
            self.patternGlintLayer.isHidden = false
        } else {
            self.patternGlintLayer.isHidden = true
        }

        for lineLight in self.lineLights {
            lineLight.setColors(hot: beam.hot, body: beam.body)
        }
        for buttonLight in self.buttonLights {
            buttonLight.setColors(hot: beam.hot, body: beam.body)
        }
    }

    /// turn-light.js `shineTexts`: the band of the colour runs across the letters the way the glass turns (a gradient
    /// clipped to the glyphs), and they glow around it (the glyphs' blurred light, masked to the band). A fast spin
    /// washes the whole line instead.
    private func shineLines(_ beam: Beam) {
        let dir = beam.dir
        let sA = abs(dir.x)
        let cA = abs(dir.y)
        for lineLight in self.lineLights {
            guard let frame = lineLight.frame else {
                continue
            }
            // The band's half-width and where the sweep has taken it, along the way the glass turns: from just before
            // the first letter to just past the last one (c is measured from the line's centre).
            let half = Double(frame.width * sA + frame.height * cA) / 2.0
            let w = 16.0 + 0.42 * half
            let c = (2.0 * beam.sweep - 1.0) * (half + w)
            let a = glassTurnClamp(beam.T * Double(lineLight.strength) * 1.25)
            let wa = glassTurnClamp(beam.wash * Double(lineLight.strength) * 0.55)
            let center = CGPoint(x: frame.width / 2.0 + dir.x * CGFloat(c), y: frame.height / 2.0 + dir.y * CGFloat(c))
            let rotation = CATransform3DMakeRotation(beam.angle, 0.0, 0.0, 1.0)

            let showsBand = a > 0.01 && abs(c) < half + w
            if showsBand {
                lineLight.band.bounds = CGRect(x: 0.0, y: 0.0, width: CGFloat(2.0 * w), height: hypot(frame.width, frame.height) + 2.0)
                lineLight.band.position = center
                lineLight.band.transform = rotation
            }
            lineLight.band.opacity = showsBand ? Float(a) : 0.0
            lineLight.wash.opacity = wa > 0.01 ? Float(wa) : 0.0
            lineLight.shine.isHidden = !showsBand && wa <= 0.01

            // The glow: the colour around the letters where the band is (all of them in a wash).
            let peak = max(a, wa) * Double(lineLight.glow)
            lineLight.halo.opacity = peak < 0.01 ? 0.0 : Float(peak)
            lineLight.halo.isHidden = peak < 0.01
            if peak >= 0.01 {
                // Outside the band the glow keeps the wash's share of it.
                let glowFloor = a > 0.0 ? glassTurnClamp(wa / max(a, wa)) : 1.0
                if glowFloor >= 0.999 {
                    lineLight.haloMaskBase.opacity = 1.0
                    lineLight.haloMaskBand.isHidden = true
                } else {
                    let pad = GlassTurnLightLayout.glowPad
                    let gw = 1.5 * w
                    lineLight.haloMaskBase.opacity = Float(glowFloor)
                    lineLight.haloMaskBand.isHidden = false
                    lineLight.haloMaskBand.bounds = CGRect(x: 0.0, y: 0.0, width: CGFloat(2.0 * gw), height: hypot(frame.width + pad * 2.0, frame.height + pad * 2.0) + 2.0)
                    lineLight.haloMaskBand.position = CGPoint(x: center.x + pad, y: center.y + pad)
                    lineLight.haloMaskBand.transform = rotation
                }
            }
        }
    }

    /// turn-light.js `lightButtons`: a sheen crosses the glass buttons with the light; the rim facing the avatar lights up.
    private func lightButtons(_ beam: Beam) {
        let dx = Double(beam.dir.x)
        let dy = Double(beam.dir.y)
        for buttonLight in self.buttonLights {
            guard let frame = buttonLight.frame else {
                continue
            }
            let cx = Double(frame.midX)
            let cy = Double(frame.midY)
            let dist = (beam.x - cx) * dx + (beam.y - cy) * dy
            let along = abs((beam.x - cx) * -dy + (beam.y - cy) * dx) / GlassTurnLightNode.lightLength
            let lf = 1.0 - glassTurnSmooth(0.35, 1.0, along)
            let reach = beam.w + Double(max(frame.width, frame.height)) * 0.5
            let sheen = glassTurnClamp(beam.I * lf * 1.2) * (abs(dist) < reach + 20.0 ? 1.0 : 0.0)
            let x = (dist / (beam.w + 40.0))
            let rim = glassTurnClamp(beam.I * lf * exp(-x * x) * 0.95 + beam.wash * 0.6)
            buttonLight.update(dir: beam.dir, angle: beam.angle, dist: CGFloat(dist), sheen: sheen, rim: rim, hot: beam.hot)
        }
    }
}

/// The light on one line: the shine (a band and a wash clipped to the glyphs) and the glow (the glyphs' blurred light
/// in three colours, masked to the band).
private final class LineLight {
    let shine = SimpleLayer()
    let shineMask = SimpleLayer()
    let wash = SimpleLayer()
    let band = SimpleGradientLayer()
    let halo = SimpleLayer()
    let haloMask = SimpleLayer()
    let haloMaskBase = SimpleLayer()
    let haloMaskBand = SimpleGradientLayer()
    /// turn-light.js `textShadow`, bottom to top: 42 pt at 0.4 and 24 pt at 0.7 of the colour, 11 pt at 0.95 of the
    /// colour lightened by 0.1, 4 pt at 0.9 of the hot centre.
    let glowLayers: [SimpleLayer] = [SimpleLayer(), SimpleLayer(), SimpleLayer()]
    let glowMasks: [SimpleLayer] = [SimpleLayer(), SimpleLayer(), SimpleLayer()]
    static let glowShadows: [[(blur: CGFloat, alpha: CGFloat)]] = [[(42.0, 0.4), (24.0, 0.7)], [(11.0, 0.95)], [(4.0, 0.9)]]
    /// px per pt for each glow mask: the wide blurs need little resolution.
    static let glowScales: [CGFloat] = [1.0, 1.0, 2.0]

    private(set) var frame: CGRect?
    private(set) var strength: CGFloat = 1.0
    private(set) var glow: CGFloat = 1.0
    private var maskSource: CGImage?
    private var maskSourceSize = CGSize()

    init() {
        self.shine.mask = self.shineMask
        self.shine.addSublayer(self.wash)
        self.shine.addSublayer(self.band)
        self.band.startPoint = CGPoint(x: 0.0, y: 0.5)
        self.band.endPoint = CGPoint(x: 1.0, y: 0.5)
        // turn-light.js: −w, −w/2, 0, +w/2, +w across the band.
        self.band.locations = [0.0, 0.25, 0.5, 0.75, 1.0]
        self.halo.mask = self.haloMask
        self.haloMaskBase.backgroundColor = UIColor.black.cgColor
        self.haloMask.addSublayer(self.haloMaskBase)
        self.haloMaskBand.startPoint = CGPoint(x: 0.0, y: 0.5)
        self.haloMaskBand.endPoint = CGPoint(x: 1.0, y: 0.5)
        self.haloMaskBand.colors = [UIColor(white: 0.0, alpha: 0.0).cgColor, UIColor.black.cgColor, UIColor(white: 0.0, alpha: 0.0).cgColor]
        self.haloMaskBand.locations = [0.0, 0.5, 1.0]
        self.haloMask.addSublayer(self.haloMaskBand)
        for (layer, mask) in zip(self.glowLayers, self.glowMasks) {
            layer.mask = mask
            self.halo.addSublayer(layer)
        }
        self.hide()
    }

    func set(_ line: GlassTurnLightNode.Line?) {
        guard let line else {
            self.frame = nil
            self.hide()
            return
        }
        self.frame = line.frame
        self.strength = line.strength
        self.glow = line.glow
        let bounds = CGRect(origin: CGPoint(), size: line.frame.size)
        self.shine.frame = line.frame
        self.shineMask.frame = bounds
        self.shineMask.contents = line.image
        self.wash.frame = bounds
        let pad = GlassTurnLightLayout.glowPad
        let haloFrame = line.frame.insetBy(dx: -pad, dy: -pad)
        let haloBounds = CGRect(origin: CGPoint(), size: haloFrame.size)
        self.halo.frame = haloFrame
        self.haloMask.frame = haloBounds
        self.haloMaskBase.frame = haloBounds
        for (layer, mask) in zip(self.glowLayers, self.glowMasks) {
            layer.frame = haloBounds
            mask.frame = haloBounds
        }
        if line.image !== self.maskSource || line.frame.size != self.maskSourceSize {
            self.maskSource = line.image
            self.maskSourceSize = line.frame.size
            self.makeGlowMasks(image: line.image, size: line.frame.size)
        }
    }

    func setColors(hot: GlassLightRGB, body: GlassLightRGB) {
        self.wash.backgroundColor = body.color(alpha: 1.0).cgColor
        self.band.colors = [
            body.color(alpha: 0.0).cgColor,
            body.color(alpha: 0.75).cgColor,
            hot.color(alpha: 1.0).cgColor,
            body.color(alpha: 0.75).cgColor,
            body.color(alpha: 0.0).cgColor
        ]
        self.glowLayers[0].backgroundColor = body.color(alpha: 1.0).cgColor
        self.glowLayers[1].backgroundColor = body.lightened(0.1).color(alpha: 1.0).cgColor
        self.glowLayers[2].backgroundColor = hot.color(alpha: 1.0).cgColor
    }

    func hide() {
        self.shine.isHidden = true
        self.band.opacity = 0.0
        self.wash.opacity = 0.0
        self.halo.isHidden = true
        self.halo.opacity = 0.0
    }

    /// The glow is the glyphs' text-shadow: blurred once per text, off the main thread, as WebKit draws it (a CoreGraphics
    /// shadow whose blur is the CSS blur radius). Until the masks arrive the line has no glow.
    private func makeGlowMasks(image: CGImage, size: CGSize) {
        for mask in self.glowMasks {
            mask.contents = nil
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let masks = zip(LineLight.glowShadows, LineLight.glowScales).map { shadows, scale in
                return glassTurnGlowMask(glyphs: image, size: size, pad: GlassTurnLightLayout.glowPad, scale: scale, shadows: shadows)
            }
            DispatchQueue.main.async {
                guard let strongSelf = self, strongSelf.maskSource === image else {
                    return
                }
                for (mask, contents) in zip(strongSelf.glowMasks, masks) {
                    mask.contents = contents
                }
            }
        }
    }
}

/// The light on one glass button: its rim (the inset light on the side facing the avatar) and the sheen's stripe, both
/// over the button's glass.
private final class ButtonLight {
    let rim = GlassLightSpillLayer()
    let clip = SimpleLayer()
    let stripe = SimpleGradientLayer()
    private(set) var frame: CGRect?
    private var size = CGSize()
    private var cornerRadius: CGFloat = 0.0
    private var toAvatar = CGPoint()

    init() {
        self.clip.masksToBounds = true
        self.clip.opacity = 0.0
        self.clip.addSublayer(self.stripe)
        self.stripe.startPoint = CGPoint(x: 0.0, y: 0.5)
        self.stripe.endPoint = CGPoint(x: 1.0, y: 0.5)
        self.stripe.locations = [0.0, 0.28, 0.5, 0.72, 1.0]
    }

    func attach(to button: GlassTurnLightNode.Button, frame: CGRect, toAvatar: CGPoint) {
        self.frame = frame
        self.toAvatar = toAvatar
        self.cornerRadius = button.cornerRadius
        if self.clip.superlayer !== button.layer {
            self.clip.removeFromSuperlayer()
            self.rim.removeFromSuperlayer()
            // Over the glass, under the button's content.
            button.layer.insertSublayer(self.clip, at: 0)
            button.layer.insertSublayer(self.rim, at: 0)
        }
        let bounds = button.layer.bounds
        self.size = bounds.size
        self.rim.frame = bounds
        self.clip.frame = bounds
        self.clip.cornerRadius = button.cornerRadius
        let length = hypot(bounds.width, bounds.height) + 24.0
        self.stripe.bounds = CGRect(x: 0.0, y: 0.0, width: GlassTurnLightLayout.stripeWidth, height: length)
        self.stripe.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    func detach() {
        self.frame = nil
        self.hide()
    }

    func setColors(hot: GlassLightRGB, body: GlassLightRGB) {
        self.stripe.colors = [
            body.color(alpha: 0.0).cgColor,
            body.color(alpha: 0.32).cgColor,
            hot.color(alpha: 0.8).cgColor,
            body.color(alpha: 0.32).cgColor,
            body.color(alpha: 0.0).cgColor
        ]
    }

    /// The stripe sits where the light is (`dist` along its direction from the button's centre), across it.
    func update(dir: CGPoint, angle: CGFloat, dist: CGFloat, sheen: Double, rim: Double, hot: GlassLightRGB) {
        self.stripe.position = CGPoint(x: self.size.width / 2.0 + dir.x * dist, y: self.size.height / 2.0 + dir.y * dist)
        self.stripe.transform = CATransform3DMakeRotation(angle, 0.0, 0.0, 1.0)
        self.clip.opacity = sheen < 0.01 ? 0.0 : Float(sheen)
        let spill = rim < 0.01 ? nil : GlassLightSpill(color: hot.lightened(0.2).color(alpha: 1.0), alpha: CGFloat(rim), direction: self.toAvatar)
        self.rim.update(spill: spill, size: self.size, cornerRadius: self.cornerRadius, blur: 11.0)
    }

    func hide() {
        self.clip.opacity = 0.0
        self.rim.update(spill: nil, size: self.size, cornerRadius: self.cornerRadius)
    }
}

/// Lengths of the line and button lights.
private enum GlassTurnLightLayout {
    /// turn-light.js `GLOW_PAD`: room around a line for its glow (pt).
    static let glowPad: CGFloat = 44.0
    /// `makeButton`: the sheen's stripe is 34 pt wide (and the button's diagonal + 24 pt long).
    static let stripeWidth: CGFloat = 34.0
}

/// The glyphs' alpha blurred like a CSS text-shadow on a canvas `pad` pt larger on every side, at `scale` px per pt:
/// each shadow is a CoreGraphics shadow whose blur is the CSS blur radius (as WebKit draws text-shadow) and whose alpha
/// is the shadow's, composited bottom to top. The glyphs themselves are drawn outside the canvas: only their shadows
/// fall on it. A bitmap context of our own has no base transform, so the shadow offset and blur are in pixels.
private func glassTurnGlowMask(glyphs: CGImage, size: CGSize, pad: CGFloat, scale: CGFloat, shadows: [(blur: CGFloat, alpha: CGFloat)]) -> CGImage? {
    let width = Int(ceil((size.width + pad * 2.0) * scale))
    let height = Int(ceil((size.height + pad * 2.0) * scale))
    guard width > 0, height > 0, let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return nil
    }
    let away = CGFloat(width) + 32.0
    // y up: the padding is the same at the top and the bottom.
    let glyphRect = CGRect(x: pad * scale - away, y: CGFloat(height) - (pad + size.height) * scale, width: size.width * scale, height: size.height * scale)
    for shadow in shadows {
        context.setShadow(offset: CGSize(width: away, height: 0.0), blur: shadow.blur * scale, color: UIColor(white: 0.0, alpha: shadow.alpha).cgColor)
        context.draw(glyphs, in: glyphRect)
    }
    return context.makeImage()
}

private func glassTurnClamp(_ x: Double, _ a: Double = 0.0, _ b: Double = 1.0) -> Double {
    return max(a, min(b, x))
}

/// turn-light.js `smooth`: smoothstep.
private func glassTurnSmooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = glassTurnClamp((x - a) / (b - a))
    return t * t * (3.0 - 2.0 * t)
}
