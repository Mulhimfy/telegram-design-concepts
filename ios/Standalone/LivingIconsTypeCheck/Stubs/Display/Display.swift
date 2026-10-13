import UIKit
import AsyncDisplayKit

// Signature stubs of Telegram's Display module (submodules/Display/Source @ f1dd7a2) — only what
// LivingSettingsIcons uses, with the real declarations' shapes.

// SimpleLayer.swift: layers without implicit animations (copied).
public final class NullActionClass: NSObject, CAAction {
    @objc public func run(forKey event: String, object anObject: Any, arguments dict: [AnyHashable : Any]?) {
    }
}

public let nullAction = NullActionClass()

open class SimpleLayer: CALayer {
    public var didEnterHierarchy: (() -> Void)?
    public var didExitHierarchy: (() -> Void)?
    public private(set) var isInHierarchy: Bool = false

    override open func action(forKey event: String) -> CAAction? {
        if event == kCAOnOrderIn {
            self.isInHierarchy = true
            self.didEnterHierarchy?()
        } else if event == kCAOnOrderOut {
            self.isInHierarchy = false
            self.didExitHierarchy?()
        }
        return nullAction
    }

    override public init() {
        super.init()
    }

    override public init(layer: Any) {
        super.init(layer: layer)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

open class SimpleShapeLayer: CAShapeLayer {
    public var didEnterHierarchy: (() -> Void)?
    public var didExitHierarchy: (() -> Void)?

    override open func action(forKey event: String) -> CAAction? {
        if event == kCAOnOrderIn {
            self.didEnterHierarchy?()
        } else if event == kCAOnOrderOut {
            self.didExitHierarchy?()
        }
        return nullAction
    }

    override public init() {
        super.init()
    }

    override public init(layer: Any) {
        super.init(layer: layer)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

open class SimpleGradientLayer: CAGradientLayer {
    public var didEnterHierarchy: (() -> Void)?
    public var didExitHierarchy: (() -> Void)?

    override open func action(forKey event: String) -> CAAction? {
        if event == kCAOnOrderIn {
            self.didEnterHierarchy?()
        } else if event == kCAOnOrderOut {
            self.didExitHierarchy?()
        }
        return nullAction
    }

    override public init() {
        super.init()
    }

    override public init(layer: Any) {
        super.init(layer: layer)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// Nodes/ASImageNode.swift: `open class ASImageNode: ASDisplayNode { public var image: UIImage? … }`.
open class ASImageNode: ASDisplayNode {
    public var image: UIImage? {
        didSet {
            self.layer.contentsScale = self.image?.scale ?? 1.0
            self.layer.contents = self.image?.cgImage
        }
    }

    override public init() {
        super.init()
    }
}

// UIKitUtils.swift:59
public let UIScreenScale = UIScreen.main.scale

// GenerateImage.swift:7-17, 102-113
public let deviceColorSpace: CGColorSpace = {
    if let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) {
        return colorSpace
    } else {
        return CGColorSpaceCreateDeviceRGB()
    }
}()

public func generateImage(_ size: CGSize, contextGenerator: (CGSize, CGContext) -> Void, opaque: Bool = false, scale: CGFloat? = nil) -> UIImage? {
    if size.width.isZero || size.height.isZero {
        return nil
    }
    let format = UIGraphicsImageRendererFormat()
    format.opaque = opaque
    format.scale = scale ?? UIScreenScale
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
        context.cgContext.translateBy(x: 0.0, y: size.height)
        context.cgContext.scaleBy(x: 1.0, y: -1.0)
        contextGenerator(size, context.cgContext)
    }
}

// DisplayLinkAnimator.swift:5-9, 29-75, 249
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
        var isValid: Bool = true
        public var isPaused: Bool = false

        init(framesPerSecond: FramesPerSecond, update: @escaping (CGFloat) -> Void) {
            self.framesPerSecond = framesPerSecond
            self.update = update
        }

        public func invalidate() {
            self.isValid = false
        }
    }

    public func add(framesPerSecond: FramesPerSecond = .fps(60), _ update: @escaping (CGFloat) -> Void) -> Link {
        return LinkImpl(framesPerSecond: framesPerSecond, update: update)
    }
}
