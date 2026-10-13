import Foundation

// The effects of prototype/src/settings/living-icons.js — the `fx` object built in `play()` and the
// tile's pop, sheen and press in `update()` / `press()` — as pure functions of time. Each returns what
// the prototype writes into the DOM that frame; the layer view (LivingSettingsIconLayer) applies it to
// its layers. Pure Swift (parity-tested against the web).

public enum LivingIconFX {
    private typealias C = LivingIconCurves
    private static let degree = Double.pi / 180.0

    // MARK: - The tile (update(), press())

    /// The tile's spring pop: up 16 % in 0.09 s, back on a spring (`update()`).
    public static func tileScale(_ t: Double) -> Double {
        return t < 0.09 ? 1.0 + 0.16 * C.easeOut(t / 0.09) : 1.0 + 0.16 * (1.0 - C.pop(t, 0.34, 0.09, 0.42))
    }

    /// The sheen crossing the tile: `translateX(-100% … 100%)` of its own width, 0.06 → 0.56 s (`update()`).
    public static func sheenOffset(_ t: Double) -> Double {
        let u = C.clamp((t - 0.06) / 0.5)
        return -100.0 + 200.0 * C.ease(u)
    }

    /// The tap that opens the row's page: the tile gives under the finger (squash, spring back);
    /// nil once it is over (0.6 s), when the tile is itself again (`press()` / `update()`).
    public static func pressScale(_ t: Double) -> Double? {
        if t > 0.6 {
            return nil
        }
        return t < 0.07 ? 1.0 - 0.12 * C.easeOut(t / 0.07) : 0.88 + 0.12 * C.pop(t, 0.3, 0.07, 0.55)
    }

    // MARK: - fx

    /// One sound-wave arc: `side` −1 (left) / 1 (right), drawn `translate(dx, 0)` at `opacity`.
    public struct Arc: Equatable {
        public var side: Double
        public var opacity: Double
        public var dx: Double
    }

    /// `fx.waves(t, t0, n)`: n arcs on each side, expanding and fading, each 0.18 of its run after the one before.
    public static func waves(_ t: Double, _ t0: Double, _ n: Int) -> [Arc] {
        let u = (t - t0) / 0.6
        var arcs: [Arc] = []
        for i in 0 ..< n * 2 {
            let side: Double = i % 2 != 0 ? 1.0 : -1.0
            let k = Double(i / 2)
            let v = C.clamp(u - k * 0.18)
            arcs.append(Arc(side: side, opacity: v > 0.0 && v < 1.0 ? sin(Double.pi * v) : 0.0, dx: side * 3.5 * v))
        }
        return arcs
    }

    /// `fx.glow(t, t0, k)`: a white `drop-shadow(0 0 radius)` of `alpha` around the glyph, nil while off.
    public static func glow(_ t: Double, _ t0: Double, _ k: Double) -> (radius: Double, alpha: Double)? {
        let v = t < t0 ? 0.0 : sin(Double.pi * C.clamp((t - t0) / 0.5))
        return v > 0.01 ? (4.0 * v, k * v) : nil
    }

    /// `fx.glint(t, t0)`: the tile's sheen sent across again at `t0` (replaces `sheenOffset` that frame).
    public static func glint(_ t: Double, _ t0: Double) -> Double {
        let u = C.clamp((t - t0) / 0.45)
        return -100.0 + 200.0 * C.ease(u)
    }

    /// `fx.halo(t, t0)`: a 2 pt ring of the tile's colour around the tile, growing and fading.
    public static func halo(_ t: Double, _ t0: Double) -> (opacity: Double, scale: Double) {
        let u = C.clamp((t - t0) / 0.55)
        return (u > 0.0 && u < 1.0 ? (1.0 - u) * 0.8 : 0.0, 1.0 + 0.45 * C.easeOut(u))
    }

    /// One four-point sparkle: translated (pt, from the tile's centre), turned (degrees), scaled.
    public struct Sparkle: Equatable {
        public var opacity: Double
        public var x: Double
        public var y: Double
        public var rotation: Double
        public var scale: Double
    }

    /// `fx.sparkles(t, t0, n, c)`: n sparkles fly out of the tile and fade.
    public static func sparkles(_ t: Double, _ t0: Double, _ n: Int) -> [Sparkle] {
        let u = (t - t0) / 0.6
        var result: [Sparkle] = []
        for i in 0 ..< n {
            let fi = Double(i)
            let a = (fi / Double(n)) * 360.0 + 20.0 * sin(fi * 7.1)
            let d = 22.0 + 6.0 * sin(fi * 3.3)
            let k = 0.8 + 0.3 * cos(fi * 5.1)
            let v = C.clamp(u * k)
            let r = d * C.easeOut(v)
            result.append(Sparkle(
                opacity: v > 0.0 && v < 1.0 ? sin(Double.pi * v) : 0.0,
                x: cos(a * degree) * r,
                y: sin(a * degree) * r,
                rotation: v * 90.0,
                scale: 0.4 + 0.8 * sin(Double.pi * v)
            ))
        }
        return result
    }

    /// The confetti's colours, piece i taking `confettiColors[i % 6]`.
    public static let confettiColors: [UInt32] = [0xffd84a, 0xff6b8a, 0x6ee7ff, 0x8cff7a, 0xc79bff, 0xffffff]

    /// One piece of confetti (4 × 6 pt, from 42 % of the tile's height); `isLaunched` is false until
    /// `t0`, when it is not drawn yet.
    public struct Confetto: Equatable {
        public var isLaunched: Bool
        public var opacity: Double
        public var x: Double
        public var y: Double
        public var rotation: Double
    }

    /// `fx.confetti(t, t0)`: nine pieces thrown up and out under gravity, spinning and fading.
    public static func confetti(_ t: Double, _ t0: Double) -> [Confetto] {
        let u = t - t0
        var result: [Confetto] = []
        for i in 0 ..< 9 {
            let fi = Double(i)
            if u <= 0.0 {
                result.append(Confetto(isLaunched: false, opacity: 0.0, x: 0.0, y: 0.0, rotation: 0.0))
                continue
            }
            let vx = (fi - 4.0) * 26.0 + 10.0 * sin(fi * 2.7)
            let vy = -150.0 - 40.0 * cos(fi * 1.9)
            let spin = (i % 2 != 0 ? 1.0 : -1.0) * (400.0 + 90.0 * fi)
            result.append(Confetto(
                isLaunched: true,
                opacity: C.clamp(1.4 - u * 1.6),
                x: vx * u,
                y: vy * u + 0.5 * 520.0 * u * u,
                rotation: spin * u
            ))
        }
        return result
    }

    /// `fx.dots(t, t0)`: the bubble's own three dots (cut out of it) bounce in turn — typing — until 1.05 s:
    /// each one's vertical offset (pt, up is negative).
    public static func dots(_ t: Double, _ t0: Double) -> [Double] {
        var result: [Double] = []
        for i in 0 ..< 3 {
            let u = t - t0 - Double(i) * 0.12
            let on = u > 0.0 && t < 1.05
            result.append(on ? -1.4 * max(0.0, sin(2.0 * Double.pi * 2.2 * u)) : 0.0)
        }
        return result
    }

    /// `fx.rays(t, t0)`: the five rays over the lamp, all at this opacity.
    public static func rays(_ t: Double, _ t0: Double) -> Double {
        let u = C.clamp((t - t0) / 0.6)
        return u > 0.0 && u < 1.0 ? sin(Double.pi * u) : 0.0
    }

    /// `fx.stroke(t, t0)`: the brush's paint stroke drawn (`stroke-dashoffset`, path length 1) and faded.
    public static func stroke(_ t: Double, _ t0: Double) -> (dashOffset: Double, opacity: Double) {
        let draw = C.clamp((t - t0) / 0.25)
        let fade = C.clamp((t - 0.75) / 0.25)
        return (1.0 - C.ease(draw), draw <= 0.001 ? 0.0 : 1.0 - fade)
    }

    /// `fx.paper(open)`: the sheet rising out of the folder as its flap opens (its top `y`, opacity).
    public static func paper(_ open: Double) -> (y: Double, opacity: Double) {
        return (14.0 - 6.5 * open, 0.92 * C.clamp(open * 3.0))
    }

    /// `fx.flash(t, t0)`: the camera's flash, a disc growing out of the lens and fading.
    public static func flash(_ t: Double, _ t0: Double) -> (opacity: Double, radius: Double) {
        let u = C.clamp((t - t0) / 0.35)
        return (u > 0.0 && u < 1.0 ? (1.0 - u) * 0.9 : 0.0, 4.0 + 4.0 * C.easeOut(u))
    }

    /// `fx.hue(t, d)`: `hue-rotate(degrees) saturate(1.4)` over the glyph, nil outside the turn.
    public static func hue(_ t: Double, _ d: Double) -> Double? {
        let u = C.clamp(t / d)
        return u > 0.0 && u < 1.0 ? 360.0 * C.ease(u) : nil
    }

    /// The saturation `fx.hue` adds while it turns.
    public static let hueSaturation: Double = 1.4

    /// `fx.spin3d(t, t0, d)`: `perspective(60px) rotateY(degrees)`, a full turn (ease in-out), nil outside it.
    public static func spin3d(_ t: Double, _ t0: Double, _ d: Double) -> Double? {
        let u = C.clamp((t - t0) / d)
        let a = 360.0 * (u < 0.5 ? 4.0 * u * u * u : 1.0 - pow(-2.0 * u + 2.0, 3.0) / 2.0)
        return u > 0.0 && u < 1.0 ? a : nil
    }

    /// `perspective(60px)` of `fx.spin3d`.
    public static let spinPerspective: Double = 60.0

    /// `fx.globe(u)`: from the meridian at rest (rx 3.9 on the rig's 8.6 globe) round to it again; the second
    /// meridian, a quarter turn behind, fades in and out so neither end jumps. Half-widths of the two meridians
    /// on that globe (`LivingIconArtwork.TurningGlobe.meridianScale` takes them to Telegram's) and the second's
    /// opacity.
    public static func globe(_ u: Double) -> (rx0: Double, rx1: Double, opacity1: Double) {
        let th = acos(3.9 / 8.6) + u * 2.0 * Double.pi
        let rx0 = u >= 1.0 ? 3.9 : 8.6 * abs(cos(th))
        return (rx0, 8.6 * abs(sin(th)), C.clamp(u / 0.12) * C.clamp((1.0 - u) / 0.12))
    }

    /// `fx.globe`'s cross-fade at the rig's time `t`: how much of the turning globe shows over Telegram's banded
    /// one (0 at rest) — in from the start, out over the rig's last moments.
    public static func globeCrossFade(_ t: Double, duration: Double) -> Double {
        typealias G = LivingIconArtwork.TurningGlobe
        return C.clamp(t / G.fadeIn) * C.clamp((duration - t) / G.fadeOut)
    }

    /// The CSS `hue-rotate(degrees) saturate(s)` filter applied to one sRGB colour (Filter Effects 1,
    /// §13.1.2 feColorMatrix "hueRotate" and "saturate", in that order; channels 0…1, clamped).
    public static func filterColor(red: Double, green: Double, blue: Double, hueDegrees: Double, saturation: Double) -> (red: Double, green: Double, blue: Double) {
        let a = hueDegrees * degree
        let c = cos(a)
        let s = sin(a)
        let h: [Double] = [
            0.213 + c * 0.787 - s * 0.213, 0.715 - c * 0.715 - s * 0.715, 0.072 - c * 0.072 + s * 0.928,
            0.213 - c * 0.213 + s * 0.143, 0.715 + c * 0.285 + s * 0.140, 0.072 - c * 0.072 - s * 0.283,
            0.213 - c * 0.213 - s * 0.787, 0.715 - c * 0.715 + s * 0.715, 0.072 + c * 0.928 + s * 0.072,
        ]
        let r1 = C.clamp(h[0] * red + h[1] * green + h[2] * blue)
        let g1 = C.clamp(h[3] * red + h[4] * green + h[5] * blue)
        let b1 = C.clamp(h[6] * red + h[7] * green + h[8] * blue)
        let k = saturation
        let r2 = (0.213 + 0.787 * k) * r1 + (0.715 - 0.715 * k) * g1 + (0.072 - 0.072 * k) * b1
        let g2 = (0.213 - 0.213 * k) * r1 + (0.715 + 0.285 * k) * g1 + (0.072 - 0.072 * k) * b1
        let b2 = (0.213 - 0.213 * k) * r1 + (0.715 - 0.715 * k) * g1 + (0.072 + 0.928 * k) * b1
        return (C.clamp(r2), C.clamp(g2), C.clamp(b2))
    }
}
