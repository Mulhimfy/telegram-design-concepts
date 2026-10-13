import UIKit
import AsyncDisplayKit

// Signature stubs of Telegram's Display module (submodules/Display/Source @ f1dd7a2) — only what
// DepthSwipe uses, with the real declarations' shapes.

// UIKitUtils.swift:59
public let UIScreenScale = UIScreen.main.scale

// DisplayLinkAnimator.swift:5-75, 249
public protocol SharedDisplayLinkDriverLink: AnyObject {
    var isPaused: Bool { get set }

    func invalidate()
}

public final class SharedDisplayLinkDriver {
    public enum FramesPerSecond: Comparable {
        case fps(Int)
        case max

        public static func <(lhs: FramesPerSecond, rhs: FramesPerSecond) -> Bool {
            switch lhs {
            case let .fps(lhsFps):
                switch rhs {
                case let .fps(rhsFps):
                    return lhsFps < rhsFps
                case .max:
                    return true
                }
            case .max:
                return false
            }
        }
    }

    public typealias Link = SharedDisplayLinkDriverLink

    public static let shared = SharedDisplayLinkDriver()

    public final class LinkImpl: Link {
        public let framesPerSecond: FramesPerSecond
        let update: (CGFloat) -> Void
        public var isPaused: Bool = false

        init(framesPerSecond: FramesPerSecond, update: @escaping (CGFloat) -> Void) {
            self.framesPerSecond = framesPerSecond
            self.update = update
        }

        public func invalidate() {
        }
    }

    private init() {
    }

    public func add(framesPerSecond: FramesPerSecond = .fps(60), _ update: @escaping (CGFloat) -> Void) -> Link {
        return LinkImpl(framesPerSecond: framesPerSecond, update: update)
    }
}

// ContainedViewLayoutTransition.swift:44-55, 129-140
public enum ContainedViewLayoutTransitionCurve: Equatable, Hashable {
    case linear
    case easeInOut
    case easeIn
    case spring
    case customSpring(mass: CGFloat = 5.0, stiffness: CGFloat = 900.0, damping: CGFloat, initialVelocity: CGFloat)
    case custom(Float, Float, Float, Float)

    public static var slide: ContainedViewLayoutTransitionCurve {
        return .custom(0.33, 0.52, 0.25, 0.99)
    }
}

public enum ContainedViewLayoutTransition {
    case immediate
    case animated(duration: Double, curve: ContainedViewLayoutTransitionCurve)

    public var isAnimated: Bool {
        if case .immediate = self {
            return false
        } else {
            return true
        }
    }
}
