import Foundation
import CoreGraphics

// Glass coin interaction model — the Swift twin of prototype/src/coin/coin-physics.js.
// Both are pinned to the same golden trajectories (ios/Standalone/Tests).
//
// The collapsed profile avatar behaves like a two-sided glass coin on a spindle.
// Gesture constants are Telegram's own draggable coin (PremiumCoinComponent.swift):
//   · yaw follows the finger at 1 pt = 1° (handlePan, deg2rad(translation.x))
//   · pitch is rubber-banded: range 60°, coefficient 0.4
//   · a release under 90° and under 200 pt/s springs back, otherwise the coin turns over
//   · flicks over 600 pt/s toss it (it lifts higher while it spins)
// Springs are Telegram's: TouchEffect lift-on / lift-off (GlassBackgroundComponent) and
// the iOS 26 `.spring` (k 555.027, c 47.118). New here: several faces per flick, the
// landing face chosen with UIScrollView's momentum projection, a detent tick per face,
// and `turnBy` — the coin turns over on its own to show a new back photo.

/// A damped harmonic oscillator, the same model as `CASpringAnimation`.
public struct GlassCoinSpring: Equatable {
    public var mass: Double
    public var stiffness: Double
    public var damping: Double

    public init(mass: Double, stiffness: Double, damping: Double) {
        self.mass = mass
        self.stiffness = stiffness
        self.damping = damping
    }

    /// SwiftUI-style parameters: `response` in seconds, `dampingFraction` (ζ).
    public init(response: Double, dampingFraction: Double, mass: Double = 1.0) {
        let omega = 2.0 * Double.pi / response
        self.mass = mass
        self.stiffness = omega * omega * mass
        self.damping = 2.0 * dampingFraction * (self.stiffness * mass).squareRoot()
    }

    var omega0: Double {
        return (self.stiffness / self.mass).squareRoot()
    }

    var zeta: Double {
        return self.damping / (2.0 * (self.stiffness * self.mass).squareRoot())
    }

    /// Displacement and velocity after `t` seconds, starting from displacement `x0` and velocity `v0`.
    public func solve(x0: Double, v0: Double, t: Double) -> (x: Double, v: Double) {
        let w0 = self.omega0
        let z = self.zeta
        if z < 1.0 - 1e-6 {
            let wd = w0 * (1.0 - z * z).squareRoot()
            let e = exp(-z * w0 * t)
            let a = x0
            let b = (v0 + z * w0 * x0) / wd
            let c = cos(wd * t)
            let s = sin(wd * t)
            let x = e * (a * c + b * s)
            let v = e * ((-z * w0) * (a * c + b * s) + (-a * wd * s + b * wd * c))
            return (x, v)
        } else if z > 1.0 + 1e-6 {
            let sq = (z * z - 1.0).squareRoot()
            let r1 = -w0 * (z - sq)
            let r2 = -w0 * (z + sq)
            let a = (v0 - r2 * x0) / (r1 - r2)
            let b = x0 - a
            let e1 = exp(r1 * t)
            let e2 = exp(r2 * t)
            return (a * e1 + b * e2, a * r1 * e1 + b * r2 * e2)
        } else {
            let e = exp(-w0 * t)
            let b = v0 + w0 * x0
            return (e * (x0 + b * t), e * (b - w0 * (x0 + b * t)))
        }
    }
}

/// A scalar driven by a spring with velocity hand-off on retarget (UIKit-style interruptible springs).
public final class GlassCoinSpringValue {
    public private(set) var target: Double
    public private(set) var value: Double
    public private(set) var velocity: Double = 0.0
    public private(set) var isSettled: Bool = true
    public var epsilon: Double = 5e-4

    private var spring: GlassCoinSpring
    private var x0: Double = 0.0
    private var v0: Double = 0.0
    private var t0: Double = 0.0

    public init(_ value: Double, spring: GlassCoinSpring) {
        self.target = value
        self.value = value
        self.spring = spring
    }

    public func set(_ value: Double, at time: Double) {
        self.target = value
        self.value = value
        self.velocity = 0.0
        self.x0 = 0.0
        self.v0 = 0.0
        self.t0 = time
        self.isSettled = true
    }

    public func animate(to target: Double, at time: Double, spring: GlassCoinSpring? = nil, velocity: Double? = nil) {
        self.update(at: time)
        let v = velocity ?? self.velocity
        if let spring {
            self.spring = spring
        }
        self.target = target
        self.x0 = self.value - target
        self.v0 = v
        self.t0 = time
        self.isSettled = false
    }

    @discardableResult
    public func update(at time: Double) -> Double {
        if self.isSettled {
            return self.value
        }
        let t = max(0.0, time - self.t0)
        let (x, v) = self.spring.solve(x0: self.x0, v0: self.v0, t: t)
        self.value = self.target + x
        self.velocity = v
        if abs(x) < self.epsilon && abs(v) < self.epsilon * 10.0 && t > 0.03 {
            self.value = self.target
            self.velocity = 0.0
            self.isSettled = true
        }
        return self.value
    }
}

/// Pan velocity like `UIPanGestureRecognizer.velocity(in:)`: least-squares slope over the last 80 ms.
public final class GlassCoinVelocityTracker {
    private struct Sample {
        var t: Double
        var x: Double
        var y: Double
    }

    private var samples: [Sample] = []
    private let window: Double

    public init(window: Double = 0.08) {
        self.window = window
    }

    public func reset() {
        self.samples.removeAll()
    }

    public func add(time: Double, x: Double, y: Double) {
        self.samples.append(Sample(t: time, x: x, y: y))
        let cutoff = time - 0.25
        while self.samples.count > 2, let first = self.samples.first, first.t < cutoff {
            self.samples.removeFirst()
        }
    }

    public func velocity(at time: Double) -> (x: Double, y: Double) {
        let recent = self.samples.filter { $0.t >= time - self.window }
        if recent.count < 2 {
            return (0.0, 0.0)
        }
        let n = Double(recent.count)
        let t0 = recent[0].t
        var st = 0.0, sx = 0.0, sy = 0.0, stt = 0.0, stx = 0.0, sty = 0.0
        for s in recent {
            let t = s.t - t0
            st += t
            sx += s.x
            sy += s.y
            stt += t * t
            stx += t * s.x
            sty += t * s.y
        }
        let den = n * stt - st * st
        if abs(den) < 1e-9 {
            return (0.0, 0.0)
        }
        return ((n * stx - st * sx) / den, (n * sty - st * sy) / den)
    }
}

/// Rounds half up, like JavaScript's `Math.round`, so the web prototype and the app agree on
/// which face is in front at exact half turns.
@inline(__always)
func glassCoinRound(_ x: Double) -> Int {
    return Int(floor(x + 0.5))
}

/// UIScrollView momentum projection (WWDC18 "Designing Fluid Interfaces").
public func glassCoinProject(velocity: Double, decelerationRate: Double) -> Double {
    return ((velocity / 1000.0) * decelerationRate) / (1.0 - decelerationRate)
}

public struct GlassCoinConfiguration {
    /// PeerInfoHeaderNode.swift:534 — avatarSize / 2.
    public var radius: Double = 50.0
    /// PremiumCoinComponent: 1 pt of drag = 1°.
    public var yawPerPoint: Double = Double.pi / 180.0
    /// PremiumCoinComponent rubberBandingOffset: range 60°, coefficient 0.4.
    public var pitchRange: Double = 60.0
    public var pitchCoefficient: Double = 0.4
    /// PremiumCoinComponent tilts toward a tap (0.6 / 0.3 rad); an avatar lifts flat, so every
    /// edge reads the same while it is held. 20 pt dead zone kept for a host that wants the tilt.
    public var pressYaw: Double = 0.0
    public var pressPitch: Double = 0.0
    public var pressDeadZone: Double = 20.0
    public var dragSlop: Double = 6.0
    /// Release under 90° and under 200 pt/s springs back (PremiumCoinComponent).
    public var smallAngle: Double = Double.pi / 2.0
    public var smallVelocity: Double = 200.0
    /// Over 600 pt/s the coin is tossed (PremiumCoinComponent "explode").
    public var tossVelocity: Double = 600.0
    /// Momentum projection rate, between UIScrollView's .fast (0.99) and .normal (0.998): a swipe
    /// turns the coin over once, only a real flick spins it over several photos.
    public var decelerationRate: Double = 0.995
    public var maxFaces: Int = 9
    public var translateFollow: Double = 0.18
    public var translateLimit: Double = 12.0

    /// TouchEffect.swift lift-on (ζ 0.71).
    public var liftOn = GlassCoinSpring(mass: 1.36, stiffness: 568.0, damping: 39.7)
    /// iOS 26 `.spring` (UIKitRuntimeUtils/UIKitUtils.m make26SpringAnimationImpl), ζ 1.
    public var uiSpring = GlassCoinSpring(mass: 1.0, stiffness: 555.027, damping: 47.118)
    /// One face over: response and damping (lands with ~1.5 % overshoot). `turnBy` more than one face takes 1.3× the
    /// response.
    public var flipResponse: Double = 0.40
    public var flipDamping: Double = 0.80
    /// Released before edge-on: back home.
    public var homeSpring = GlassCoinSpring(response: 0.34, dampingFraction: 0.82)
    /// Lift, tilt and offset after a release, and the glass dissolving into the flat photo.
    public var settleSpring = GlassCoinSpring(response: 0.28, dampingFraction: 0.9)
    public var glassOutSpring = GlassCoinSpring(response: 0.22, dampingFraction: 1.0)
    /// Land while approaching within ~11° slower than 5 rad/s: the glass dissolves over the
    /// end of the motion instead of after it (back to the flat photo ~0.4 s after a release).
    public var landAngle: Double = 0.2
    public var landVelocity: Double = 5.0
    public var spinDampingFraction: Double = 0.8
    public var settleDelay: Double = 0.0
    public var tossLift: Double = 1.18

    public init() {
    }

    public var flipSpring: GlassCoinSpring {
        return GlassCoinSpring(response: self.flipResponse, dampingFraction: self.flipDamping)
    }
}

public enum GlassCoinFaceContent: Hashable {
    /// A profile photo. The reverse of a single photo is `.photo(0)` by default: the same picture on both sides.
    case photo(Int)
    /// The profile colour and its background emoji (coin-physics.js keeps it as a choice for the reverse and as its
    /// default; `GlassCoinAvatarNode` doesn't use it)…
    case emblem
    /// …or the back photo the user added.
    case backPhoto
}

public struct GlassCoinState: Equatable {
    public var yaw: Double
    public var pitch: Double
    public var lift: Double
    public var glass: Double
    public var offset: CGPoint
    public var sideA: GlassCoinFaceContent
    public var sideB: GlassCoinFaceContent
    public var face: Int
    public var yawVelocity: Double
    public var isIdle: Bool
}

public final class GlassCoinModel {
    public enum Mode {
        case idle
        case pressed
        case dragging
        case released
        /// A short lift into glass without turning (a glass-colour change).
        case pulse
    }

    private struct Spin {
        var t0: Double
        var theta0: Double
        var direction: Double
        var omega0: Double
        var deceleration: Double
        var duration: Double
        var target: Double
        var handoff: Double
    }

    public let configuration: GlassCoinConfiguration
    public var photoCount: Int
    /// What the reverse of a single photo shows: `.photo(0)` (the photo itself: one picture, both sides), `.emblem` or
    /// `.backPhoto` (coin-physics.js `setBack`; its default, like this one, is the emblem — the avatar node sets
    /// `.photo(0)`). A side only changes while it faces away: change it while the front is in view.
    public var back: GlassCoinFaceContent = .emblem

    /// A new face swung past edge-on (a detent: `HapticFeedback().tap()`).
    public var onTick: ((_ isCatch: Bool) -> Void)?
    /// The coin came to rest; `changed` when it shows a different face than before the gesture.
    public var onLand: ((_ changed: Bool, _ face: Int) -> Void)?
    /// The face in front changed (every half turn, before `onLand`): with an even face in front the back faces away and
    /// can be swapped unseen.
    public var onFaceChange: ((_ face: Int) -> Void)?

    public private(set) var mode: Mode = .idle

    private let yaw: GlassCoinSpringValue
    private let pitch: GlassCoinSpringValue
    private let lift: GlassCoinSpringValue
    private let glass: GlassCoinSpringValue
    private let offsetX: GlassCoinSpringValue
    private let offsetY: GlassCoinSpringValue
    private let tracker = GlassCoinVelocityTracker()

    private var spin: Spin?
    private var spinVelocity: Double = 0.0
    private var downPoint = CGPoint()
    private var dragOrigin = CGPoint()
    private var dragYaw0: Double = 0.0
    private var dragPitch0: Double = 0.0
    private var startHalfTurn: Int = 0
    private var targetHalfTurn: Int = 0
    private var lastHalfTurn: Int = 0
    private var lastTickTime: Double = -1.0
    private var restTime: Double = 0.0
    private var lastTime: Double?
    private var tossed = false
    private var pulseEnd: Double = 0.0

    public init(photoCount: Int, configuration: GlassCoinConfiguration = GlassCoinConfiguration()) {
        self.configuration = configuration
        self.photoCount = photoCount
        self.yaw = GlassCoinSpringValue(0.0, spring: configuration.uiSpring)
        self.pitch = GlassCoinSpringValue(0.0, spring: configuration.uiSpring)
        self.lift = GlassCoinSpringValue(0.0, spring: configuration.liftOn)
        self.glass = GlassCoinSpringValue(0.0, spring: configuration.liftOn)
        self.offsetX = GlassCoinSpringValue(0.0, spring: configuration.uiSpring)
        self.offsetY = GlassCoinSpringValue(0.0, spring: configuration.uiSpring)
    }

    /// Face index in front: 0 = current photo, +1 = next (swipe left), −1 = previous.
    public func face(atYaw yaw: Double) -> Int {
        return -glassCoinRound(yaw / Double.pi)
    }

    public func content(forFace face: Int) -> GlassCoinFaceContent {
        if self.photoCount <= 1 {
            return ((face % 2) + 2) % 2 == 0 ? .photo(0) : self.back
        }
        return .photo(((face % self.photoCount) + self.photoCount) % self.photoCount)
    }

    /// Content of the card's two physical sides. A side only changes while it faces away.
    public func sides() -> (a: GlassCoinFaceContent, b: GlassCoinFaceContent) {
        let u = -self.yaw.value / Double.pi
        let evenFace = 2 * glassCoinRound(u / 2.0)
        let oddFace = 2 * Int(floor(u / 2.0)) + 1
        return (self.content(forFace: evenFace), self.content(forFace: oddFace))
    }

    public func hitTest(_ point: CGPoint) -> Bool {
        return hypot(Double(point.x), Double(point.y)) <= self.configuration.radius + 10.0
    }

    /// `point` is relative to the coin centre, screen axes (y down).
    public func pointerDown(_ point: CGPoint, at time: Double) {
        self.update(at: time)
        let c = self.configuration
        self.tracker.reset()
        self.tracker.add(time: time, x: Double(point.x), y: Double(point.y))
        self.downPoint = point
        if self.mode == .released && (self.spin != nil || abs(self.yaw.velocity) > 3.0) {
            self.onTick?(true)
        }
        self.spin = nil
        self.mode = .pressed
        self.restTime = 0.0
        // Catch: freeze the current angle under the finger.
        self.yaw.set(self.yaw.value, at: time)
        self.startHalfTurn = glassCoinRound(self.yaw.value / Double.pi)
        let baseYaw = self.yaw.value
        let px = Double(point.x)
        let py = Double(point.y)
        let tiltYaw = abs(px) > c.pressDeadZone ? copysign(1.0, px) * c.pressYaw * min(1.0, abs(px) / c.radius) : 0.0
        let tiltPitch = abs(py) > c.pressDeadZone ? copysign(1.0, py) * c.pressPitch * min(1.0, abs(py) / c.radius) : 0.0
        self.yaw.animate(to: baseYaw + tiltYaw, at: time, spring: c.liftOn)
        self.pitch.animate(to: tiltPitch, at: time, spring: c.liftOn)
        self.lift.animate(to: 1.0, at: time, spring: c.liftOn)
        self.glass.animate(to: 1.0, at: time, spring: c.liftOn)
    }

    public func pointerMove(_ point: CGPoint, at time: Double) {
        guard self.mode == .pressed || self.mode == .dragging else {
            return
        }
        self.update(at: time)
        let c = self.configuration
        self.tracker.add(time: time, x: Double(point.x), y: Double(point.y))
        let dx = Double(point.x - self.downPoint.x)
        let dy = Double(point.y - self.downPoint.y)
        if self.mode == .pressed && hypot(dx, dy) > c.dragSlop {
            self.mode = .dragging
            self.dragOrigin = point
            self.dragYaw0 = self.yaw.value
            self.dragPitch0 = self.pitch.value
        }
        guard self.mode == .dragging else {
            return
        }
        let tx = Double(point.x - self.dragOrigin.x)
        let ty = Double(point.y - self.dragOrigin.y)
        // Direct manipulation; a 60 ms follow spring smooths touch sampling without perceptible lag.
        let follow = GlassCoinSpring(response: 0.06, dampingFraction: 1.0)
        self.yaw.animate(to: self.dragYaw0 + tx * c.yawPerPoint, at: time, spring: follow)
        func band(_ offset: Double) -> Double {
            return (1.0 - 1.0 / ((abs(offset) * c.pitchCoefficient) / c.pitchRange + 1.0)) * c.pitchRange * copysign(1.0, offset)
        }
        self.pitch.animate(to: self.dragPitch0 + band(ty) * Double.pi / 180.0, at: time, spring: follow)
        func rubberBand(_ value: Double) -> Double {
            return (1.0 - 1.0 / ((abs(value) * 0.55) / c.translateLimit + 1.0)) * c.translateLimit * copysign(1.0, value)
        }
        self.offsetX.animate(to: rubberBand(dx * c.translateFollow), at: time, spring: follow)
        self.offsetY.animate(to: rubberBand(dy * c.translateFollow), at: time, spring: follow)
    }

    /// Returns true when the touch was a tap (no drag): the header expands the avatar as before.
    @discardableResult
    public func pointerUp(_ point: CGPoint, at time: Double) -> Bool {
        guard self.mode == .pressed || self.mode == .dragging else {
            return false
        }
        self.update(at: time)
        let wasTap = self.mode == .pressed
        let velocity = wasTap ? (x: 0.0, y: 0.0) : self.tracker.velocity(at: time)
        self.release(velocityX: velocity.x, at: time)
        return wasTap
    }

    public func cancel(at time: Double) {
        if self.mode == .pressed || self.mode == .dragging {
            self.release(velocityX: 0.0, at: time)
        }
    }

    /// A short lift into glass and back, without turning (a glass-colour change).
    public func pulse(at time: Double, hold: Double = 0.3) {
        self.update(at: time)
        if self.mode != .idle {
            return
        }
        self.mode = .pulse
        self.pulseEnd = time + hold
        self.lift.animate(to: 1.0, at: time, spring: self.configuration.liftOn)
        self.glass.animate(to: 1.0, at: time, spring: self.configuration.liftOn)
    }

    /// Programmatic flick (VoiceOver adjustable action, demos): `velocity` in pt/s.
    public func flick(velocity: Double, at time: Double) {
        self.update(at: time)
        self.startHalfTurn = glassCoinRound(self.yaw.value / Double.pi)
        self.lift.animate(to: 1.0, at: time, spring: self.configuration.liftOn)
        self.glass.animate(to: 1.0, at: time, spring: self.configuration.liftOn)
        self.release(velocityX: velocity, at: time)
    }

    /// Shows `face` at rest without animation (Reduce Motion, state restoration).
    public func jump(toFace face: Int, at time: Double) {
        self.update(at: time)
        self.spin = nil
        let angle = -Double(face) * Double.pi
        self.yaw.set(angle, at: time)
        self.pitch.set(0.0, at: time)
        self.lift.set(0.0, at: time)
        self.glass.set(0.0, at: time)
        self.offsetX.set(0.0, at: time)
        self.offsetY.set(0.0, at: time)
        self.lastHalfTurn = glassCoinRound(angle / Double.pi)
        self.startHalfTurn = self.lastHalfTurn
        self.targetHalfTurn = self.lastHalfTurn
        self.mode = .idle
    }

    /// Turns over by `n` faces on its own (showing a new back photo): lifts into glass, turns on the flip spring (1.3×
    /// the response for more than one face) and lands like a released coin.
    public func turnBy(_ n: Int, at time: Double) {
        self.update(at: time)
        let c = self.configuration
        self.spin = nil
        self.startHalfTurn = glassCoinRound(self.yaw.value / Double.pi)
        self.targetHalfTurn = self.startHalfTurn - n
        self.lift.animate(to: 1.0, at: time, spring: c.liftOn)
        self.glass.animate(to: 1.0, at: time, spring: c.liftOn)
        let spring = GlassCoinSpring(response: c.flipResponse * (n > 1 ? 1.3 : 1.0), dampingFraction: c.flipDamping)
        self.yaw.animate(to: Double(self.targetHalfTurn) * Double.pi, at: time, spring: spring)
        self.pitch.animate(to: 0.0, at: time, spring: c.settleSpring)
        self.offsetX.animate(to: 0.0, at: time, spring: c.settleSpring)
        self.offsetY.animate(to: 0.0, at: time, spring: c.settleSpring)
        self.tossed = false
        self.mode = .released
        self.restTime = 0.0
    }

    private func release(velocityX vx: Double, at time: Double) {
        let c = self.configuration
        let yaw = self.yaw.value
        let w0 = vx * c.yawPerPoint
        let startAngle = Double(self.startHalfTurn) * Double.pi
        var target: Int
        if abs(yaw - startAngle) < c.smallAngle && abs(vx) < c.smallVelocity {
            target = self.startHalfTurn
        } else if abs(vx) < c.smallVelocity {
            target = glassCoinRound(yaw / Double.pi)
        } else {
            let projected = yaw + glassCoinProject(velocity: vx, decelerationRate: c.decelerationRate) * c.yawPerPoint
            target = glassCoinRound(projected / Double.pi)
            let direction = w0 < 0.0 ? -1 : 1
            if (target - self.startHalfTurn) * direction <= 0 {
                target = self.startHalfTurn + direction
            }
            let limit = self.startHalfTurn + direction * c.maxFaces
            if (target - limit) * direction > 0 {
                target = limit
            }
        }
        let targetAngle = Double(target) * Double.pi
        let distance = abs(targetAngle - yaw)
        self.spin = nil
        if distance > 1.25 * Double.pi && abs(w0) > 1.0 {
            // Several faces: constant friction, landing exactly on the chosen face; the last
            // half-turn is handed to the flip spring for a physical landing.
            let w = abs(w0)
            let a = (w * w) / (2.0 * distance)
            self.spin = Spin(t0: time, theta0: yaw, direction: targetAngle > yaw ? 1.0 : -1.0, omega0: w, deceleration: a, duration: w / a, target: targetAngle, handoff: 0.55 * Double.pi)
            self.yaw.set(yaw, at: time)
        } else if target == self.startHalfTurn {
            self.yaw.animate(to: targetAngle, at: time, spring: c.homeSpring, velocity: w0)
        } else {
            self.yaw.animate(to: targetAngle, at: time, spring: c.flipSpring, velocity: w0)
        }
        self.pitch.animate(to: 0.0, at: time, spring: c.settleSpring)
        self.offsetX.animate(to: 0.0, at: time, spring: c.settleSpring)
        self.offsetY.animate(to: 0.0, at: time, spring: c.settleSpring)
        self.tossed = abs(vx) > c.tossVelocity && distance > 0.5 * Double.pi
        if self.tossed {
            self.lift.animate(to: c.tossLift, at: time, spring: GlassCoinSpring(response: 0.35, dampingFraction: 0.9))
        }
        self.targetHalfTurn = target
        self.mode = .released
        self.restTime = 0.0
    }

    public func update(at time: Double) {
        let dt = self.lastTime.map { max(0.0, time - $0) } ?? 0.0
        self.lastTime = time
        let c = self.configuration

        if let spin = self.spin {
            let t = min(time - spin.t0, spin.duration)
            let theta = spin.theta0 + spin.direction * (spin.omega0 * t - 0.5 * spin.deceleration * t * t)
            let w = spin.direction * (spin.omega0 - spin.deceleration * t)
            self.spinVelocity = w
            if (spin.target - theta) * spin.direction <= spin.handoff || t >= spin.duration {
                self.spin = nil
                self.yaw.set(theta, at: time)
                self.yaw.animate(to: spin.target, at: time, spring: c.flipSpring, velocity: w)
            } else {
                self.yaw.set(theta, at: time)
            }
        }
        let yaw = self.yaw.update(at: time)
        self.pitch.update(at: time)
        self.lift.update(at: time)
        self.glass.update(at: time)
        self.offsetX.update(at: time)
        self.offsetY.update(at: time)

        let half = glassCoinRound(yaw / Double.pi)
        if half != self.lastHalfTurn {
            self.lastHalfTurn = half
            if time - self.lastTickTime > 0.045 {
                self.lastTickTime = time
                self.onTick?(false)
            }
            self.onFaceChange?(self.face(atYaw: yaw))
        }

        if self.mode == .pulse && time >= self.pulseEnd {
            self.mode = .idle
            self.lift.animate(to: 0.0, at: time, spring: c.settleSpring)
            self.glass.animate(to: 0.0, at: time, spring: c.glassOutSpring)
        }

        if self.mode == .released {
            if self.tossed && abs(Double(self.targetHalfTurn) * Double.pi - yaw) < 0.9 * Double.pi && self.lift.target != 1.0 {
                self.lift.animate(to: 1.0, at: time, spring: c.settleSpring)
            }
            // Land while the coin makes its last few degrees toward the face (or once it is at
            // rest): the glass dissolves over the end of the motion instead of after it.
            let error = Double(self.targetHalfTurn) * Double.pi - yaw
            let velocity = self.yaw.velocity
            let atRest = abs(error) < 0.035 && abs(velocity) < 0.6
            let arriving = abs(error) < c.landAngle && error * velocity >= 0.0 && abs(velocity) < c.landVelocity
            if self.spin == nil && abs(self.pitch.value) < 0.08 && (atRest || arriving) {
                self.restTime += dt
                if self.restTime >= c.settleDelay {
                    self.mode = .idle
                    self.lift.animate(to: 0.0, at: time, spring: c.settleSpring)
                    self.glass.animate(to: 0.0, at: time, spring: c.glassOutSpring)
                    self.onLand?(self.targetHalfTurn != self.startHalfTurn, self.face(atYaw: Double(self.targetHalfTurn) * Double.pi))
                }
            } else {
                self.restTime = 0.0
            }
        }
    }

    public func state(at time: Double) -> GlassCoinState {
        self.update(at: time)
        let sides = self.sides()
        return GlassCoinState(
            yaw: self.yaw.value,
            pitch: self.pitch.value,
            lift: self.lift.value,
            glass: max(0.0, min(1.0, self.glass.value)),
            offset: CGPoint(x: self.offsetX.value, y: self.offsetY.value),
            sideA: sides.a,
            sideB: sides.b,
            face: self.face(atYaw: self.yaw.value),
            yawVelocity: self.spin != nil ? self.spinVelocity : self.yaw.velocity,
            isIdle: !self.isAnimating
        )
    }

    public var isAnimating: Bool {
        return self.spin != nil || self.mode != .idle || !self.lift.isSettled || !self.glass.isSettled || !self.pitch.isSettled || !self.yaw.isSettled || !self.offsetX.isSettled || !self.offsetY.isSettled
    }
}
