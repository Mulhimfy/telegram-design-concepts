import Foundation

// The phone's tilt as the gift light reads it — the Swift twin of `MotionSource` in prototype/src/profile/glass-gifts.js
// (pinned to the same golden frames as GlassTileModel). As the TON wallet card reads its device motion
// (WalletCardBackgroundView.swift:84-118): the first reading is the reference, the value is smoothed over 0.1 s
// (WCB:118), and the reference slowly follows the phone (~4 s) so that a held pose turns neutral. Degrees; ±20 → full
// effect. Pure Swift (Foundation only); GlassGiftMotion feeds it from Core Motion.

/// `MotionSource.feed` / `update` / `set`.
public struct GlassGiftMotionFilter {
    /// Degrees of tilt that give the full effect.
    public static let range: Double = 20.0
    /// Seconds: the value follows the tilt with 1 − e^(−dt / 0.1) (WCB:118).
    public static let smoothing: Double = 0.1
    /// Seconds: the reference follows the phone with 1 − e^(−dt / 4).
    public static let recentring: Double = 4.0

    private struct Angles {
        var beta: Double
        var gamma: Double
    }

    public private(set) var value = GlassGiftLight(x: 0.0, y: 0.0)
    private var base: Angles?
    private var current: Angles?

    /// Scripted tilt (demo videos): returned as is instead of the sensors' value; nil goes back to the sensors.
    public var override: GlassGiftLight?

    public init() {
    }

    /// True once a reading arrived (`update` returns a value).
    public var hasReading: Bool {
        return self.current != nil && self.base != nil
    }

    /// A reading, as DeviceOrientationEvent gives it: `beta` front-back (degrees, positive when the top edge comes up
    /// toward the viewer), `gamma` left-right (positive when the right edge goes down / away). The first one is the
    /// reference.
    public mutating func feed(beta: Double, gamma: Double) {
        let reading = Angles(beta: beta, gamma: gamma)
        self.current = reading
        if self.base == nil {
            self.base = reading
        }
    }

    /// One step of `dt` seconds. Nil until the first reading (and without an override).
    public mutating func update(dt: Double) -> GlassGiftLight? {
        if let override = self.override {
            return override
        }
        guard let current = self.current, var base = self.base else {
            return nil
        }
        // Re-centre over ~4 s.
        let d = 1.0 - exp(-dt / GlassGiftMotionFilter.recentring)
        base.beta += (current.beta - base.beta) * d
        base.gamma += (current.gamma - base.gamma) * d
        self.base = base
        let k = 1.0 - exp(-dt / GlassGiftMotionFilter.smoothing)
        let range = GlassGiftMotionFilter.range
        self.value.x += (max(-range, min(range, current.gamma - base.gamma)) - self.value.x) * k
        self.value.y += (max(-range, min(range, current.beta - base.beta)) - self.value.y) * k
        return self.value
    }

    /// Forgets the readings: the next one is the reference again, and the value starts from neutral.
    public mutating func reset() {
        self.value = GlassGiftLight(x: 0.0, y: 0.0)
        self.base = nil
        self.current = nil
    }
}

/// Turns the gyroscope's rotation rate into the readings `GlassGiftMotionFilter` takes.
///
/// The browser's beta / gamma (DeviceOrientationEvent) are Euler angles of the gravity direction: they lock up when the
/// phone is held upright (beta ≈ 90°), the way most people hold it while standing. Here the readings are the phone's
/// rotation about its own x axis (beta) and y axis (gamma) since the first reading, integrated from the gyroscope's
/// bias-corrected rate (CMDeviceMotion.rotationRate, device axes, right-hand rule): the same directions as the
/// browser's angles for small tilts, at any holding angle. The filter only ever uses the difference to its slowly
/// re-centring reference, so a slow drift of the sum never shows.
public struct GlassGiftRotationIntegrator {
    /// Gaps longer than this (a paused sensor, a stalled main thread) count as this long.
    public static let maxStep: Double = 0.1

    public private(set) var beta: Double = 0.0
    public private(set) var gamma: Double = 0.0
    private var lastTimestamp: Double?

    public init() {
    }

    /// One sample: `rate` in radians per second about the device's x and y axes, `timestamp` in seconds. Returns the
    /// time since the previous sample (0 for the first one).
    public mutating func add(rateX: Double, rateY: Double, timestamp: Double) -> Double {
        let dt: Double
        if let lastTimestamp = self.lastTimestamp {
            dt = max(0.0, min(GlassGiftRotationIntegrator.maxStep, timestamp - lastTimestamp))
        } else {
            dt = 0.0
        }
        self.lastTimestamp = timestamp
        self.beta += rateX * dt * 180.0 / Double.pi
        self.gamma += rateY * dt * 180.0 / Double.pi
        return dt
    }

    public mutating func reset() {
        self.beta = 0.0
        self.gamma = 0.0
        self.lastTimestamp = nil
    }
}

/// The device axes in the screen's: the light moves with the interface, not with the hardware (iPad, landscape).
public enum GlassGiftScreenRotation {
    case portrait
    case portraitUpsideDown
    /// Home button / bottom edge on the left: the device's top edge points to the screen's right.
    case landscapeLeft
    /// Home button / bottom edge on the right: the device's top edge points to the screen's left.
    case landscapeRight

    /// `light` in device axes (x along the device's right edge, y toward its bottom edge) → screen axes (x right,
    /// y down).
    public func apply(_ light: GlassGiftLight) -> GlassGiftLight {
        switch self {
        case .portrait:
            return light
        case .portraitUpsideDown:
            return GlassGiftLight(x: -light.x, y: -light.y)
        case .landscapeLeft:
            return GlassGiftLight(x: -light.y, y: light.x)
        case .landscapeRight:
            return GlassGiftLight(x: light.y, y: -light.x)
        }
    }
}
