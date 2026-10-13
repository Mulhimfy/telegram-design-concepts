import Foundation

// Depth Swipe springs — the Swift twin of prototype/src/core/spring.js.
//
// A closed-form damped harmonic oscillator, the same model as CASpringAnimation
// (m·x'' + c·x' + k·x = 0). It is evaluated analytically from the moment a value was (re)targeted,
// so it does not depend on the frame rate: a 60 Hz device, a 120 Hz ProMotion device and the golden
// recordings (tools/golden-depth.mjs) give the same curve.
//
// Velocity hand-off: retargeting keeps the current value and velocity, as UIKit's interruptible
// springs do.

/// Spring parameters (`SpringParams`).
public struct DepthSwipeSpring: Equatable {
    public var mass: Double
    public var stiffness: Double
    public var damping: Double

    public init(mass: Double, stiffness: Double, damping: Double) {
        self.mass = mass
        self.stiffness = stiffness
        self.damping = damping
    }

    /// `SpringParams.fromResponse`: response in seconds and a damping fraction, as SwiftUI and
    /// `UISpringTimingParameters` describe springs.
    public init(response: Double, dampingFraction: Double, mass: Double = 1.0) {
        let omega = (2.0 * Double.pi) / response
        let stiffness = omega * omega * mass
        self.mass = mass
        self.stiffness = stiffness
        self.damping = 2.0 * dampingFraction * (stiffness * mass).squareRoot()
    }

    var omega0: Double {
        return (self.stiffness / self.mass).squareRoot()
    }

    var zeta: Double {
        return self.damping / (2.0 * (self.stiffness * self.mass).squareRoot())
    }

    /// `solveSpring`: displacement (current − target) and velocity `t` seconds after starting at
    /// displacement `x0` with velocity `v0`.
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

/// A scalar driven by a spring (`SpringValue`): `animate` retargets it with velocity hand-off,
/// `update` advances it to a time.
public final class DepthSwipeSpringValue {
    public private(set) var target: Double
    public private(set) var value: Double
    public private(set) var velocity: Double = 0.0
    public private(set) var isSettled: Bool = true
    /// At rest when |x| < epsilon and |v| < 10·epsilon (after 30 ms).
    public var epsilon: Double = 5e-4

    private var spring: DepthSwipeSpring
    private var x0: Double = 0.0
    private var v0: Double = 0.0
    private var t0: Double = 0.0

    public init(_ value: Double, spring: DepthSwipeSpring) {
        self.target = value
        self.value = value
        self.spring = spring
    }

    public func set(_ value: Double, at time: Double) {
        self.target = value
        self.x0 = 0.0
        self.v0 = 0.0
        self.t0 = time
        self.value = value
        self.velocity = 0.0
        self.isSettled = true
    }

    public func animate(to target: Double, at time: Double, spring: DepthSwipeSpring? = nil, velocity: Double? = nil) {
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
        // Perceptual rest: well below a pixel / a tenth of a degree for the values animated here.
        if abs(x) < self.epsilon && abs(v) < self.epsilon * 10.0 && t > 0.03 {
            self.value = self.target
            self.velocity = 0.0
            self.isSettled = true
        }
        return self.value
    }
}
