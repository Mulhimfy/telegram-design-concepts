// SOURCE: https://github.com/super-ultra/ScrollMechanics (ScrollMechanics/Sources/RubberBand.swift + DecelerationTimingParameters.swift + SpringTimingParameters.swift)
// LICENSE: MIT (c) Ilya Lobanov. Fetched 2026-10-12 for reference.

// ===== RubberBand.swift =====
import Foundation
import CoreGraphics

public func rubberBandClamp(_ x: CGFloat, coeff: CGFloat, dim: CGFloat) -> CGFloat {
    return (1.0 - (1.0 / (x * coeff / dim + 1.0))) * dim
}

public func rubberBandClamp(_ x: CGFloat, coeff: CGFloat, dim: CGFloat, limits: ClosedRange<CGFloat>) -> CGFloat {
    let clampedX = x.clamped(to: limits)
    let diff = abs(x - clampedX)
    let sign: CGFloat = clampedX > x ? -1 : 1
    return clampedX + sign * rubberBandClamp(diff, coeff: coeff, dim: dim)
}

public struct RubberBand {
    public var coeff: CGFloat
    public var dims: CGSize
    public var bounds: CGRect
    
    public init(coeff: CGFloat = 0.55, dims: CGSize, bounds: CGRect) {
        self.coeff = coeff
        self.dims = dims
        self.bounds = bounds
    }
    
    public func clamp(_ point: CGPoint) -> CGPoint {
        let x = rubberBandClamp(point.x, coeff: coeff, dim: dims.width, limits: bounds.minX...bounds.maxX)
        let y = rubberBandClamp(point.y, coeff: coeff, dim: dims.height, limits: bounds.minY...bounds.maxY)
        return CGPoint(x: x, y: y)
    }
}

// ===== DecelerationTimingParameters.swift =====
import Foundation
import CoreGraphics

public struct DecelerationTimingParameters {
    public var initialValue: CGPoint
    public var initialVelocity: CGPoint
    public var decelerationRate: CGFloat
    public var threshold: CGFloat
    
    public init(initialValue: CGPoint, initialVelocity: CGPoint, decelerationRate: CGFloat, threshold: CGFloat) {
        assert(decelerationRate > 0 && decelerationRate < 1)
        
        self.initialValue = initialValue
        self.initialVelocity = initialVelocity
        self.decelerationRate = decelerationRate
        self.threshold = threshold
    }
}

public extension DecelerationTimingParameters {
    
    var destination: CGPoint {
        let dCoeff = 1000 * log(decelerationRate)
        return initialValue - initialVelocity / dCoeff
    }
    
    var duration: TimeInterval {
        guard initialVelocity.length > 0 else { return 0 }
        
        let dCoeff = 1000 * log(decelerationRate)
        return TimeInterval(log(-dCoeff * threshold / initialVelocity.length) / dCoeff)
    }
    
    func value(at time: TimeInterval) -> CGPoint {
        let dCoeff = 1000 * log(decelerationRate)
        return initialValue + (pow(decelerationRate, CGFloat(1000 * time)) - 1) / dCoeff * initialVelocity
    }
    
    func duration(to value: CGPoint) -> TimeInterval? {
        guard value.distance(toSegment: (initialValue, destination)) < threshold else { return nil }
        
        let dCoeff = 1000 * log(decelerationRate)
        return TimeInterval(log(1.0 + dCoeff * (value - initialValue).length / initialVelocity.length) / dCoeff)
    }
    
    func velocity(at time: TimeInterval) -> CGPoint {
        return initialVelocity * pow(decelerationRate, CGFloat(1000 * time))
    }
    
}

// ===== SpringTimingParameters.swift =====
import Foundation
import CoreGraphics

/// https://en.wikipedia.org/wiki/Harmonic_oscillator
///
/// System's equation of motion:
///
/// 0 < dampingRatio < 1:
/// x(t) = exp(-beta * t) * (c1 * sin(w' * t) + c2 * cos(w' * t))
/// c1 = x0
/// c2 = (v0 + beta * x0) / w'
///
/// dampingRatio == 1:
/// x(t) = exp(-beta * t) * (c1 + c2 * t)
/// c1 = x0
/// c2 = (v0 + beta * x0)
///
/// x0 - initial displacement
/// v0 - initial velocity
/// beta = damping / (2 * mass)
/// w0 = sqrt(stiffness / mass) - natural frequency
/// w' = sqrt(w0 * w0 - beta * beta) - damped natural frequency

public struct Spring {
    public var mass: CGFloat
    public var stiffness: CGFloat
    public var dampingRatio: CGFloat
    
    public init(mass: CGFloat, stiffness: CGFloat, dampingRatio: CGFloat) {
        self.mass = mass
        self.stiffness = stiffness
        self.dampingRatio = dampingRatio
    }
}

public extension Spring {
    
    static var `default`: Spring {
        return Spring(mass: 1, stiffness: 200, dampingRatio: 1)
    }
    
}

public extension Spring {
    
    var damping: CGFloat {
        return 2 * dampingRatio * sqrt(mass * stiffness)
    }
    
    var beta: CGFloat {
        return damping / (2 * mass)
    }
    
    var dampedNaturalFrequency: CGFloat {
        return sqrt(stiffness / mass) * sqrt(1 - dampingRatio * dampingRatio)
    }
    
}

public struct SpringTimingParameters {
    public let spring: Spring
    public let displacement: CGPoint
    public let initialVelocity: CGPoint
    public let threshold: CGFloat
    private let impl: TimingParameters
        
    public init(spring: Spring, displacement: CGPoint, initialVelocity: CGPoint, threshold: CGFloat) {
        self.spring = spring
        self.displacement = displacement
        self.initialVelocity = initialVelocity
        self.threshold = threshold
        
        if spring.dampingRatio == 1 {
            impl = CriticallyDampedSpringTimingParameters(spring: spring,
                                                          displacement: displacement,
                                                          initialVelocity: initialVelocity,
                                                          threshold: threshold)
        } else if spring.dampingRatio > 0 && spring.dampingRatio < 1 {
            impl = UnderdampedSpringTimingParameters(spring: spring,
                                                     displacement: displacement,
                                                     initialVelocity: initialVelocity,
                                                     threshold: threshold)
        } else {
            fatalError("dampingRatio should be greater than 0 and less than or equal to 1")
        }
    }
}

extension SpringTimingParameters: TimingParameters {
    
    public var duration: TimeInterval {
        return impl.duration
    }
    
    public func value(at time: TimeInterval) -> CGPoint {
        return impl.value(at: time)
    }
        
}

// MARK: - Private Impl

 
private struct UnderdampedSpringTimingParameters {
    let spring: Spring
    let displacement: CGPoint
    let initialVelocity: CGPoint
    let threshold: CGFloat
}

extension UnderdampedSpringTimingParameters: TimingParameters {
    
    var duration: TimeInterval {
        if displacement.length == 0 && initialVelocity.length == 0 {
            return 0
        }
        
        return TimeInterval(log((c1.length + c2.length) / threshold) / spring.beta)
    }
    
    func value(at time: TimeInterval) -> CGPoint {
        let t = CGFloat(time)
        let wd = spring.dampedNaturalFrequency
        return exp(-spring.beta * t) * (c1 * cos(wd * t) + c2 * sin(wd * t))
    }

    // MARK: - Private
    
    private var c1: CGPoint {
        return displacement
    }
    
    private var c2: CGPoint {
        return (initialVelocity + spring.beta * displacement) / spring.dampedNaturalFrequency
    }
    
}

private struct CriticallyDampedSpringTimingParameters {
    let spring: Spring
    let displacement: CGPoint
    let initialVelocity: CGPoint
    let threshold: CGFloat
}

extension CriticallyDampedSpringTimingParameters: TimingParameters {
    
    var duration: TimeInterval {
        if displacement.length == 0 && initialVelocity.length == 0 {
            return 0
        }
        
        let b = spring.beta
        let e = CGFloat(M_E)
         
        let t1 = 1 / b * log(2 * c1.length / threshold)
        let t2 = 2 / b * log(4 * c2.length / (e * b * threshold))
        
        return TimeInterval(max(t1, t2))
    }
    
    func value(at time: TimeInterval) -> CGPoint {
        let t = CGFloat(time)
        return exp(-spring.beta * t) * (c1 + c2 * t)
    }

    // MARK: - Private
    
    private var c1: CGPoint {
        return displacement
    }
    
    private var c2: CGPoint {
        return initialVelocity + spring.beta * displacement
    }
    
}
