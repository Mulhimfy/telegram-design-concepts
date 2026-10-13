import Foundation

// The motion helpers of prototype/src/settings/living-icons.js (`clamp` … `bump`), one for one.
// Time is in seconds from the start of an icon's animation; angles in the rigs are degrees.
// Pure Swift: CI replays the web prototype's golden frames through these (Standalone/LivingIconsCore).

public enum LivingIconCurves {
    /// `clamp(x, a = 0, b = 1)`.
    @inline(__always)
    public static func clamp(_ x: Double, _ a: Double = 0.0, _ b: Double = 1.0) -> Double {
        return max(a, min(b, x))
    }

    /// Damped oscillation: amplitude `a`, frequency `f` (Hz), decay `k` (1/s), starting at `t0`.
    public static func ring(_ t: Double, _ a: Double, _ f: Double, _ k: Double, _ t0: Double = 0.0) -> Double {
        if t < t0 {
            return 0.0
        }
        return a * sin(2.0 * Double.pi * f * (t - t0)) * exp(-k * (t - t0))
    }

    /// Spring step 0 → 1 with overshoot (ζ ≈ 0.5), response `r` (s), starting at `t0`.
    public static func pop(_ t: Double, _ r: Double = 0.32, _ t0: Double = 0.0, _ zeta: Double = 0.5) -> Double {
        if t <= t0 {
            return 0.0
        }
        let w = (2.0 * Double.pi) / r
        let wd = w * sqrt(1.0 - zeta * zeta)
        let u = t - t0
        return 1.0 - exp(-zeta * w * u) * (cos(wd * u) + ((zeta * w) / wd) * sin(wd * u))
    }

    /// A ball dropped from `h` (pt) onto the floor with restitution `e`: the y offset (negative = up), from `t0`.
    public static func drop(_ t: Double, _ h: Double, _ t0: Double = 0.0, _ e: Double = 0.38) -> Double {
        let g = 2200.0
        var u = t - t0
        if u < 0.0 {
            return -h
        }
        var v = sqrt(2.0 * g * h)
        let tFall = v / g
        if u < tFall {
            return -h + 0.5 * g * u * u
        }
        u -= tFall
        for _ in 0 ..< 4 {
            v *= e
            let tb = (2.0 * v) / g
            if u < tb {
                return -(v * u - 0.5 * g * u * u)
            }
            u -= tb
        }
        return 0.0
    }

    /// Smoothstep of the clamped input.
    public static func ease(_ u: Double) -> Double {
        let u = clamp(u)
        return u * u * (3.0 - 2.0 * u)
    }

    /// Cubic ease-out of the clamped input.
    public static func easeOut(_ u: Double) -> Double {
        return 1.0 - pow(1.0 - clamp(u), 3.0)
    }

    /// Cubic ease-in of the clamped input.
    public static func easeIn(_ u: Double) -> Double {
        return pow(clamp(u), 3.0)
    }

    /// Lifted for `up` s, then dropped from `h` with bounces (no jump at t = 0).
    public static func hopDrop(_ t: Double, _ h: Double, _ t0: Double = 0.0, _ up: Double = 0.1) -> Double {
        if t < t0 {
            return 0.0
        }
        if t < t0 + up {
            return -h * easeOut((t - t0) / up)
        }
        return drop(t, h, t0 + up)
    }

    /// A half-sine bump 0 → 1 → 0 over `d` from `t0`.
    public static func bump(_ t: Double, _ t0: Double, _ d: Double) -> Double {
        if t <= t0 || t >= t0 + d {
            return 0.0
        }
        return sin((Double.pi * (t - t0)) / d)
    }
}
