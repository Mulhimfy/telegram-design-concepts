import UIKit
import AsyncDisplayKit
import SwiftSignalKit

// Signature stubs of Telegram's Display module (submodules/Display/Source) — only what
// GlassCoinAvatar uses, with the real declarations' shapes.

public final class NullActionClass: NSObject, CAAction {
    @objc public func run(forKey event: String, object anObject: Any, arguments dict: [AnyHashable : Any]?) {
    }
}

public let nullAction = NullActionClass()

// Display/Source/SimpleLayer.swift: layers without implicit animations.
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

public let UIScreenScale: CGFloat = UIScreen.main.scale

public func generateImage(_ size: CGSize, contextGenerator: (CGSize, CGContext) -> Void, opaque: Bool = false, scale: CGFloat? = nil) -> UIImage? {
    let format = UIGraphicsImageRendererFormat()
    format.opaque = opaque
    format.scale = scale ?? UIScreenScale
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
        context.cgContext.translateBy(x: 0.0, y: size.height)
        context.cgContext.scaleBy(x: 1.0, y: -1.0)
        contextGenerator(size, context.cgContext)
    }
}

public func generateImage(_ size: CGSize, opaque: Bool = false, scale: CGFloat? = nil, rotatedContext: (CGSize, CGContext) -> Void) -> UIImage? {
    let format = UIGraphicsImageRendererFormat()
    format.opaque = opaque
    format.scale = scale ?? UIScreenScale
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
        rotatedContext(size, context.cgContext)
    }
}

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

// Real: `public typealias Link = SharedDisplayLinkDriverLink`, a protocol (DisplayLinkAnimator.swift:5,49).
public protocol SharedDisplayLinkDriverLink: AnyObject {
    func invalidate()
}

public final class SharedDisplayLinkDriver {
    public enum FramesPerSecond: Comparable {
        case fps(Int)
        case max
    }

    public typealias Link = SharedDisplayLinkDriverLink

    private final class LinkImpl: SharedDisplayLinkDriverLink {
        func invalidate() {
        }
    }

    public static let shared = SharedDisplayLinkDriver()

    public func add(framesPerSecond: FramesPerSecond = .fps(60), _ update: @escaping (CGFloat) -> Void) -> Link {
        return LinkImpl()
    }
}

public extension UIColor {
    func withMultiplied(hue: CGFloat, saturation: CGFloat, brightness: CGFloat) -> UIColor {
        var h: CGFloat = 0.0, s: CGFloat = 0.0, b: CGFloat = 0.0, a: CGFloat = 0.0
        self.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: max(0.0, min(1.0, h * hue)), saturation: max(0.0, min(1.0, s * saturation)), brightness: max(0.0, min(1.0, b * brightness)), alpha: a)
    }

    func mixedWith(_ other: UIColor, alpha: CGFloat) -> UIColor {
        let alpha = min(1.0, max(0.0, alpha))
        var r1: CGFloat = 0.0, g1: CGFloat = 0.0, b1: CGFloat = 0.0, a1: CGFloat = 0.0
        var r2: CGFloat = 0.0, g2: CGFloat = 0.0, b2: CGFloat = 0.0, a2: CGFloat = 0.0
        self.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 * (1.0 - alpha) + r2 * alpha, green: g1 * (1.0 - alpha) + g2 * alpha, blue: b1 * (1.0 - alpha) + b2 * alpha, alpha: a1 * (1.0 - alpha) + a2 * alpha)
    }
}
