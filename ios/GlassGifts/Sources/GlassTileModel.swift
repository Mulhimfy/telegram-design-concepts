import Foundation

// Glass gift tile model — the Swift twin of `GiftLook` and `GlassTile` in prototype/src/profile/glass-gifts.js.
// Both are pinned to the same golden frames (tools/golden-gifts.mjs → ios/Standalone/GlassGiftsCore).
//
// Every gift tile on a profile's Gifts tab is a pane of glass with the gift floating inside it. Touched, it leans
// toward the finger and lifts a hair while a burst of light fragments runs across the glass and sparkles catch at its
// corners; the phone's tilt moves the light across it with only a hint of lean. The motion is Telegram's own TON
// wallet card (WalletCardComponent.swift, the one glassy card in the app that tilts):
//   · the angles follow their targets with 1 − e^(−8 dt), the scale with 1 − e^(−12 dt) (WCC:913-918),
//   · after release the targets decay by e^(−4 dt) per frame (WCC:877-882),
//   · the transform is m34 = −1/650, a small translate with the angles, the scale, X / Y rotation and a touch of Z
//     (yaw · 0.05) (WCC:1386-1424),
//   · device motion moves the light, not the card (WCC:903-917) — here with a hint of lean (≤ 2.5°).
// (WCC = submodules/TelegramUI/Components/Wallet/WalletCardComponent/Sources/WalletCardComponent.swift @ f1dd7a2.)
//
// Units are the prototype's: angles in degrees, offsets in points, the light layers' positions in percent of their
// own boxes (CSS). This file is pure Swift (Foundation only), so the parity tests run it on macOS.

/// `GiftLook` (glass-gifts.js).
public enum GlassGiftLook {
    /// Degrees. The wallet card turns up to 17.2° on a 361 pt card (WCC:110); a 120 pt tile wants less.
    public static let maxYaw: Double = 9.0
    /// Degrees (the wallet card: 11.5°, WCC:107).
    public static let maxPitch: Double = 7.0
    /// Degrees of lean from the phone's tilt at full effect.
    public static let motionLean: Double = 2.5
    /// Scale while touched (the wallet card's pan target, WCC:1601).
    public static let held: Double = 1.01
    /// Points above the glass: the gift, the corner ribbon and the badges.
    public static let giftDepth: Double = 14.0
    public static let ribbonDepth: Double = 18.0
    public static let badgeDepth: Double = 10.0
    /// m34 = −1 / perspective (WCC:1388).
    public static let perspective: Double = 650.0
    /// The page builds three shards and four sparkles per tile (profile-page.js).
    public static let shardCount: Int = 3
    public static let sparkleCount: Int = 4
}

/// The phone's tilt as the light sees it, in degrees: `x` from the left/right tilt, `y` from the forward/back tilt;
/// ±20 is full effect (`MotionSource`, GlassGiftMotionFilter.swift).
public struct GlassGiftLight: Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// One light fragment running across the glass (`.gift-shard`).
public struct GlassTileShard: Equatable {
    public var opacity: Double
    /// translateX, percent of the shard's own width.
    public var translation: Double
    /// Degrees.
    public var rotation: Double
}

/// One sparkle at a corner of the glass (`.gift-sparkle`).
public struct GlassTileSparkle: Equatable {
    public var opacity: Double
    public var scale: Double
    /// Degrees.
    public var rotation: Double
}

/// Everything one `GlassTile.update` writes, frame by frame.
public struct GlassTileState: Equatable {
    /// True while anything still moves (the angles, the scale or a burst): the display link keeps running.
    public var isActive: Bool

    // The tile: perspective(650) translate(translationX, translationY) scale(scale) rotateX(pitch) rotateY(yaw)
    // rotateZ(roll). `yaw` / `pitch` include the motion lean.
    public var yaw: Double
    public var pitch: Double
    public var scale: Double
    public var translationX: Double
    public var translationY: Double
    public var roll: Double

    /// The specular sheen (`.gift-sheen`, a box 170 % of the tile): translate in percent of that box, and opacity.
    public var sheenX: Double
    public var sheenY: Double
    public var sheenOpacity: Double

    /// The prismatic streak (`.gift-holo`, a 300 % gradient): background-position in percent, and opacity.
    public var holoX: Double
    public var holoY: Double
    public var holoOpacity: Double

    /// The lit edge (`.gift-rim`): the angle of its linear gradient, degrees (CSS: 0 = up, clockwise).
    public var rimAngle: Double

    /// The gift's own slide over the glass, points (on top of its depth).
    public var giftX: Double
    public var giftY: Double

    /// The soft shadow under the tile (`.gift-shadow`): translate in points, scale and opacity.
    public var shadowX: Double
    public var shadowY: Double
    public var shadowScale: Double
    public var shadowOpacity: Double

    /// The light fragments, written only while a burst runs (nil otherwise: nothing to show).
    public var shards: [GlassTileShard]?
    public var sparkles: [GlassTileSparkle]?
}

private func clamp(_ x: Double, _ a: Double = 0.0, _ b: Double = 1.0) -> Double {
    return max(a, min(b, x))
}

/// `GlassTile` (glass-gifts.js): one tile's lean, lift and light.
public final class GlassTileModel {
    public struct Target: Equatable {
        public var yaw: Double
        public var pitch: Double
        public var scale: Double
    }

    public private(set) var yaw: Double = 0.0
    public private(set) var pitch: Double = 0.0
    public private(set) var scale: Double = 1.0
    public private(set) var target = Target(yaw: 0.0, pitch: 0.0, scale: 1.0)
    public private(set) var isTouching: Bool = false
    public private(set) var burstStart: Double?

    public init() {
    }

    /// Finger at (u, v) in the tile, −1…1 each way (0, 0 = centre).
    public func aim(u: Double, v: Double) {
        self.isTouching = true
        self.target = Target(
            yaw: clamp(u, -1.0, 1.0) * GlassGiftLook.maxYaw,
            pitch: -clamp(v, -1.0, 1.0) * GlassGiftLook.maxPitch,
            scale: GlassGiftLook.held
        )
    }

    public func release() {
        self.isTouching = false
        self.target.scale = 1.0
    }

    /// A burst of light fragments starting at `time` (seconds, the same clock as `update(now:)`).
    public func burst(at time: Double) {
        self.burstStart = time
    }

    /// One frame. `dt`: the frame time; `light`: the phone's tilt (shared by all tiles), nil without motion.
    public func update(now: Double, dt: Double, light: GlassGiftLight?) -> GlassTileState {
        if !self.isTouching {
            // The pan offset decays after release.
            let k = exp(-4.0 * dt)
            self.target.yaw *= k
            self.target.pitch *= k
        }
        let a = 1.0 - exp(-8.0 * dt)
        let b = 1.0 - exp(-12.0 * dt)
        self.yaw += (self.target.yaw - self.yaw) * a
        self.pitch += (self.target.pitch - self.pitch) * a
        self.scale += (self.target.scale - self.scale) * b

        let lx = light?.x ?? 0.0
        let ly = light?.y ?? 0.0
        let yaw = self.yaw + clamp(lx / 20.0, -1.0, 1.0) * GlassGiftLook.motionLean
        let pitch = self.pitch - clamp(ly / 20.0, -1.0, 1.0) * GlassGiftLook.motionLean
        let isMoving = abs(self.target.yaw - self.yaw) > 0.01 || abs(self.target.pitch - self.pitch) > 0.01
            || abs(self.target.scale - self.scale) > 1e-4
            || abs(self.target.yaw) > 0.01 || abs(self.target.pitch) > 0.01

        // Light: the tile's lean plus the phone's tilt (×0.9 for the surface), in degrees.
        let sx = yaw + lx * 0.9
        let sy = pitch - ly * 0.9
        let tilt = min(1.0, hypot(sx, sy) / 12.0)

        var state = GlassTileState(
            isActive: isMoving,
            // The wallet's transform: a small translate with the angles, scale, X / Y rotation and a touch of Z.
            yaw: yaw,
            pitch: pitch,
            scale: self.scale,
            translationX: -yaw * 0.06,
            translationY: pitch * 0.05,
            roll: yaw * 0.05,
            sheenX: clamp(sx * 2.2, -40.0, 40.0),
            sheenY: clamp(-sy * 2.2, -40.0, 40.0),
            sheenOpacity: 0.3 + 0.7 * tilt,
            holoX: 50.0 + sx * 5.0,
            holoY: 50.0 - sy * 5.0,
            holoOpacity: 0.06 + 0.3 * tilt,
            rimAngle: 135.0 + sx * 6.0 - sy * 6.0,
            giftX: yaw * 0.22,
            giftY: -pitch * 0.22,
            shadowX: -yaw * 0.45,
            shadowY: pitch * 0.45 + 2.0,
            shadowScale: 0.96 + (self.scale - 1.0) * 2.0,
            shadowOpacity: 0.32 + 0.4 * min(1.0, hypot(yaw, pitch) / 9.0),
            shards: nil,
            sparkles: nil
        )

        // Light fragments: shards across the glass, sparkles at its corners.
        if let burstStart = self.burstStart {
            let u = (now - burstStart) / 0.55
            state.shards = (0 ..< GlassGiftLook.shardCount).map { i in
                let v = clamp(u * 1.25 - Double(i) * 0.12)
                return GlassTileShard(
                    opacity: v > 0.0 && v < 1.0 ? sin(Double.pi * v) * 0.8 : 0.0,
                    translation: -130.0 + 260.0 * v,
                    rotation: -28.0 + Double(i) * 7.0
                )
            }
            state.sparkles = (0 ..< GlassGiftLook.sparkleCount).map { i in
                let v = clamp(u * 1.4 - 0.15 - Double(i) * 0.08)
                let k = v > 0.0 && v < 1.0 ? sin(Double.pi * v) : 0.0
                return GlassTileSparkle(opacity: k, scale: 0.3 + k, rotation: v * 120.0)
            }
            if u >= 1.3 {
                self.burstStart = nil
            }
            state.isActive = true
        }
        return state
    }
}

/// Timing curves the tile needs besides the model.
public enum GlassGiftTiming {
    /// CAMediaTimingFunction ease-out — control points (0, 0) and (0.58, 1) — at `t` (0…1): the curve Telegram's
    /// context gesture eases its press shrink back with (ContextControllerSourceNode.swift:278).
    public static func easeOut(_ t: Double) -> Double {
        let t = max(0.0, min(1.0, t))
        // x(s) = 3 (1 − s) s² · 0.58 + s³ rises monotonically on 0…1: bisect for x(s) = t, then y(s) = 3 (1 − s) s² + s³.
        var low = 0.0
        var high = 1.0
        for _ in 0 ..< 40 {
            let s = (low + high) / 2.0
            let x = 3.0 * (1.0 - s) * s * s * 0.58 + s * s * s
            if x < t {
                low = s
            } else {
                high = s
            }
        }
        let s = (low + high) / 2.0
        return 3.0 * (1.0 - s) * s * s + s * s * s
    }
}
