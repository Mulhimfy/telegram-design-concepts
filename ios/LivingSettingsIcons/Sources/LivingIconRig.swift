import Foundation

// The shape of a rig in prototype/src/settings/living-icons.js: `run(t, P, fx, E)` sets each part's
// transform (`P[name].set({ r, x, y, sx, sy, kx, o, cx, cy })`, `P[name].dash(v)`), changes a
// reference element (`E.mark` / `E.shine` / `E.inner`) and asks for effects (`fx.waves(...)`, …).
// Here `run` fills a `LivingIconFrame`; the layer view (LivingSettingsIconLayer) draws it and the
// parity tests compare it with the web's golden frames. Pure Swift.

/// `P[name].set({ r, x, y, sx, sy, kx, o, cx, cy })` with the prototype's defaults: the part is moved by
/// `translate(x + cx, y + cy) rotate(r) skewX(kx) scale(sx, sy) translate(-cx, -cy)` (degrees, icon pt).
public struct LivingIconPartTransform: Equatable {
    public var r: Double
    public var x: Double
    public var y: Double
    public var sx: Double
    public var sy: Double
    public var kx: Double
    public var o: Double
    public var cx: Double
    public var cy: Double

    public init(r: Double = 0.0, x: Double = 0.0, y: Double = 0.0, sx: Double = 1.0, sy: Double = 1.0, kx: Double = 0.0, o: Double = 1.0, cx: Double = 15.0, cy: Double = 15.0) {
        self.r = r
        self.x = x
        self.y = y
        self.sx = sx
        self.sy = sy
        self.kx = kx
        self.o = o
        self.cx = cx
        self.cy = cy
    }

    public static let identity = LivingIconPartTransform()

    /// The SVG matrix (a, b, c, d, tx, ty) of the transform, mapping the part's coordinates into its parent's.
    public var matrix: (a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        let rad = self.r * Double.pi / 180.0
        let cr = cos(rad)
        let sr = sin(rad)
        let k = tan(self.kx * Double.pi / 180.0)
        // R · K · S, columns (a, b) and (c, d): R = [cr -sr; sr cr], K = [1 k; 0 1], S = diag(sx, sy).
        let a = cr * self.sx
        let b = sr * self.sx
        let c = (cr * k - sr) * self.sy
        let d = (sr * k + cr) * self.sy
        // translate(x + cx, y + cy) · M · translate(-cx, -cy)
        let tx = self.x + self.cx - (a * self.cx + c * self.cy)
        let ty = self.y + self.cy - (b * self.cx + d * self.cy)
        return (a, b, c, d, tx, ty)
    }
}

/// One `fx.<name>(...)` call of a rig, with its arguments (the first, `t`, included as in the prototype).
public enum LivingIconEffectCall: Equatable {
    case waves(t: Double, t0: Double, n: Int)
    case glow(t: Double, t0: Double, k: Double)
    case glint(t: Double, t0: Double)
    case halo(t: Double, t0: Double)
    case sparkles(t: Double, t0: Double, n: Int, color: UInt32)
    case confetti(t: Double, t0: Double)
    case dots(t: Double, t0: Double)
    case rays(t: Double, t0: Double)
    case stroke(t: Double, t0: Double)
    case paper(open: Double)
    case flash(t: Double, t0: Double)
    case hue(t: Double, d: Double)
    case spin3d(t: Double, t0: Double, d: Double)
    case globe(u: Double)

    public var name: String {
        switch self {
        case .waves: return "waves"
        case .glow: return "glow"
        case .glint: return "glint"
        case .halo: return "halo"
        case .sparkles: return "sparkles"
        case .confetti: return "confetti"
        case .dots: return "dots"
        case .rays: return "rays"
        case .stroke: return "stroke"
        case .paper: return "paper"
        case .flash: return "flash"
        case .hue: return "hue"
        case .spin3d: return "spin3d"
        case .globe: return "globe"
        }
    }

    /// The numeric arguments in the prototype's order (the sparkle colour as 0xRRGGBB).
    public var arguments: [Double] {
        switch self {
        case let .waves(t, t0, n): return [t, t0, Double(n)]
        case let .glow(t, t0, k): return [t, t0, k]
        case let .glint(t, t0): return [t, t0]
        case let .halo(t, t0): return [t, t0]
        case let .sparkles(t, t0, n, color): return [t, t0, Double(n), Double(color)]
        case let .confetti(t, t0): return [t, t0]
        case let .dots(t, t0): return [t, t0]
        case let .rays(t, t0): return [t, t0]
        case let .stroke(t, t0): return [t, t0]
        case let .paper(open): return [open]
        case let .flash(t, t0): return [t, t0]
        case let .hue(t, d): return [t, d]
        case let .spin3d(t, t0, d): return [t, t0, d]
        case let .globe(u): return [u]
        }
    }
}

/// Everything a rig asks for at one instant.
public final class LivingIconFrame {
    public let t: Double
    /// `P[name].set(...)`, by part name. A part a rig does not set this frame keeps no entry (it stays at rest).
    public var parts: [String: LivingIconPartTransform] = [:]
    /// `P[name].dash(v)`: the part's strokes drawn back (0: whole … 1: none).
    public var dashes: [String: Double] = [:]
    /// `E.mark` (Saved Messages): the bookmark's ribbon end, `bookmark(n, f, g)`.
    public var bookmark: (n: Double, f: Double, g: Double)?
    /// `E.shine` (Telegram Features): the highlight's `stroke-dashoffset` and opacity.
    public var shine: (dashOffset: Double, opacity: Double)?
    /// `E.inner` (Money): the sparkle's turn (degrees) and scale about (15, 13.4).
    public var inner: (rotation: Double, scale: Double)?
    /// `fx.*` calls, in order.
    public var effects: [LivingIconEffectCall] = []

    public init(t: Double) {
        self.t = t
    }
}

/// `P[name]` of a rig.
public struct LivingIconPartHandle {
    let frame: LivingIconFrame
    let name: String

    public func set(r: Double = 0.0, x: Double = 0.0, y: Double = 0.0, sx: Double = 1.0, sy: Double = 1.0, kx: Double = 0.0, o: Double = 1.0, cx: Double = 15.0, cy: Double = 15.0) {
        self.frame.parts[self.name] = LivingIconPartTransform(r: r, x: x, y: y, sx: sx, sy: sy, kx: kx, o: o, cx: cx, cy: cy)
    }

    /// A stroked part drawn back (0: whole … 1: none).
    public func dash(_ v: Double) {
        self.frame.dashes[self.name] = v
    }
}

/// `P` of a rig: `P.body.set(...)`, or `P["case"]` / `P["arm\(i)"]` where a name is computed or reserved.
@dynamicMemberLookup
public struct LivingIconParts {
    let frame: LivingIconFrame

    public subscript(dynamicMember name: String) -> LivingIconPartHandle {
        return LivingIconPartHandle(frame: self.frame, name: name)
    }

    public subscript(_ name: String) -> LivingIconPartHandle {
        return LivingIconPartHandle(frame: self.frame, name: name)
    }
}

/// `fx` of a rig: each call is recorded on the frame and drawn by the layer view.
public struct LivingIconEffects {
    let frame: LivingIconFrame

    public func waves(_ t: Double, _ t0: Double, _ n: Int) { self.frame.effects.append(.waves(t: t, t0: t0, n: n)) }
    public func glow(_ t: Double, _ t0: Double, _ k: Double) { self.frame.effects.append(.glow(t: t, t0: t0, k: k)) }
    public func glint(_ t: Double, _ t0: Double) { self.frame.effects.append(.glint(t: t, t0: t0)) }
    public func halo(_ t: Double, _ t0: Double) { self.frame.effects.append(.halo(t: t, t0: t0)) }
    public func sparkles(_ t: Double, _ t0: Double, _ n: Int, _ color: UInt32) { self.frame.effects.append(.sparkles(t: t, t0: t0, n: n, color: color)) }
    public func confetti(_ t: Double, _ t0: Double) { self.frame.effects.append(.confetti(t: t, t0: t0)) }
    public func dots(_ t: Double, _ t0: Double) { self.frame.effects.append(.dots(t: t, t0: t0)) }
    public func rays(_ t: Double, _ t0: Double) { self.frame.effects.append(.rays(t: t, t0: t0)) }
    public func stroke(_ t: Double, _ t0: Double) { self.frame.effects.append(.stroke(t: t, t0: t0)) }
    public func paper(_ open: Double) { self.frame.effects.append(.paper(open: open)) }
    public func flash(_ t: Double, _ t0: Double) { self.frame.effects.append(.flash(t: t, t0: t0)) }
    public func hue(_ t: Double, _ d: Double) { self.frame.effects.append(.hue(t: t, d: d)) }
    public func spin3d(_ t: Double, _ t0: Double, _ d: Double) { self.frame.effects.append(.spin3d(t: t, t0: t0, d: d)) }
    public func globe(_ u: Double) { self.frame.effects.append(.globe(u: u)) }
}

/// `E` of a rig: the reference elements a rig changes directly.
public struct LivingIconRefs {
    let frame: LivingIconFrame

    /// `E.mark.setAttribute('d', bookmark(n, f, g))`.
    public func bookmark(_ n: Double, _ f: Double, _ g: Double) {
        self.frame.bookmark = (n, f, g)
    }

    /// `E.shine`'s `stroke-dashoffset` and `opacity`.
    public func shine(dashOffset: Double, opacity: Double) {
        self.frame.shine = (dashOffset, opacity)
    }

    /// `E.inner.setAttribute('transform', rotate(r 15 13.4) translate(15 13.4) scale(s) translate(-15 -13.4))`.
    public func inner(rotation: Double, scale: Double) {
        self.frame.inner = (rotation, scale)
    }
}

/// One icon's animation: `RIGS[name]` without its geometry (that is LivingIconArtwork's).
public struct LivingIconRig {
    public struct Flags: OptionSet {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// `paper: true` — the folder's paper sheet slides between its back and its flap.
        public static let paper = Flags(rawValue: 1 << 0)
        /// `dots: true` — the typing dots.
        public static let dots = Flags(rawValue: 1 << 1)
        /// `globe: true` — the globe is redrawn with two moving meridians.
        public static let globe = Flags(rawValue: 1 << 2)
        /// `spin3d: true` — the glyph turns in 3D.
        public static let spin3d = Flags(rawValue: 1 << 3)
        /// `hue: true` — the glyph's colour turns round the colour wheel.
        public static let hue = Flags(rawValue: 1 << 4)
        /// `element: true` — the whole icon element turns (Money).
        public static let element = Flags(rawValue: 1 << 5)
    }

    public let duration: Double
    public let flags: Flags
    let body: (_ t: Double, _ P: LivingIconParts, _ fx: LivingIconEffects, _ E: LivingIconRefs) -> Void

    public init(duration: Double, flags: Flags = [], run: @escaping (_ t: Double, _ P: LivingIconParts, _ fx: LivingIconEffects, _ E: LivingIconRefs) -> Void) {
        self.duration = duration
        self.flags = flags
        self.body = run
    }

    /// `run(t, P, fx, E)`.
    public func run(_ t: Double) -> LivingIconFrame {
        let frame = LivingIconFrame(t: t)
        self.body(t, LivingIconParts(frame: frame), LivingIconEffects(frame: frame), LivingIconRefs(frame: frame))
        return frame
    }
}
