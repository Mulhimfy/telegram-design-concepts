import UIKit

// Signature stubs of Telegram's Display module (submodules/Display/Source @ f1dd7a2) — only what GlassGifts uses, with
// the real declarations' shapes. Bodies are minimal; the real ones are in Telegram-iOS.

// UIKitUtils.swift:59.
public let UIScreenScale = UIScreen.main.scale

// HapticFeedback.swift:6-15, 128-216.
public enum ImpactHapticFeedbackStyle: Hashable {
    case light
    case medium
    case heavy
    case soft
    case rigid
    case veryLight
    case click05
    case click06
}

public final class HapticFeedback {
    public init() {
    }

    public func prepareTap() {
    }

    public func tap() {
    }

    public func prepareImpact(_ style: ImpactHapticFeedbackStyle = .medium) {
    }

    public func impact(_ style: ImpactHapticFeedbackStyle = .medium, intensity: CGFloat? = nil) {
    }

    public func success() {
    }
}

// DisplayLinkAnimator.swift:5-9, 29-51, 249-256.
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
        public var isPaused: Bool = false

        public func invalidate() {
        }
    }

    private init() {
    }

    public func add(framesPerSecond: FramesPerSecond = .fps(60), _ update: @escaping (CGFloat) -> Void) -> Link {
        return LinkImpl()
    }
}

// ContextGesture.swift:5-9, 74-97, 230-253.
public enum ContextGestureTransition {
    case begin
    case update
    case ended(CGFloat)
}

public final class ContextGesture: UIGestureRecognizer, UIGestureRecognizerDelegate {
    public var beginDelay: Double = 0.12
    public var activateOnTap: Bool = false

    public var shouldBegin: ((CGPoint) -> Bool)?
    public var activationProgress: ((CGFloat, ContextGestureTransition) -> Void)?
    public var activated: ((ContextGesture, CGPoint) -> Void)?

    override public init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
    }

    public func cancel() {
        self.state = .failed
    }

    public func endPressedAppearance() {
    }
}

// ContextControllerSourceNode.swift:157-321 (the view; the node half needs AsyncDisplayKit's list types).
open class ContextControllerSourceView: UIView {
    public private(set) var contextGesture: ContextGesture?

    public var isGestureEnabled: Bool = true {
        didSet {
            self.contextGesture?.isEnabled = self.isGestureEnabled
        }
    }
    public var beginDelay: Double = 0.12 {
        didSet {
            self.contextGesture?.beginDelay = self.beginDelay
        }
    }
    public var animateScale: Bool = true

    public var activated: ((ContextGesture, CGPoint) -> Void)?
    public var shouldBegin: ((CGPoint) -> Bool)?
    public var customActivationProgress: ((CGFloat, ContextGestureTransition) -> Void)?
    public weak var additionalActivationProgressLayer: CALayer?
    public var targetViewForActivationProgress: UIView?
    public weak var targetLayerForActivationProgress: CALayer?
    public var targetNodeForActivationProgressContentRect: CGRect?
    public var useSublayerTransformForActivation: Bool = true

    override public init(frame: CGRect) {
        super.init(frame: frame)

        self.isMultipleTouchEnabled = false
        self.isExclusiveTouch = true

        let contextGesture = ContextGesture(target: self, action: nil)
        self.contextGesture = contextGesture
        self.addGestureRecognizer(contextGesture)
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func cancelGesture() {
        self.contextGesture?.cancel()
        self.contextGesture?.isEnabled = false
        self.contextGesture?.isEnabled = self.isGestureEnabled
    }
}
