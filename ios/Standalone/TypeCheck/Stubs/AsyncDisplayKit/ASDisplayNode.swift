import UIKit

// Signature stub of AsyncDisplayKit's ASDisplayNode (the members GlassCoinAvatar uses), from Telegram-iOS @ f1dd7a2:
// ASDisplayNode.h (UIViewBridge: frame, bounds, alpha, userInteractionEnabled) and ASDisplayNode+Subclasses.h
// (didEnterHierarchy / didExitHierarchy, ASDISPLAYNODE_REQUIRES_SUPER; inHierarchy, getter isInHierarchy).
open class ASDisplayNode: NSObject {
    public let view: UIView

    public var layer: CALayer {
        return self.view.layer
    }

    public override init() {
        self.view = UIView()
        super.init()
    }

    open var frame: CGRect {
        get {
            return self.view.frame
        } set {
            self.view.frame = newValue
        }
    }

    open var bounds: CGRect {
        get {
            return self.view.bounds
        } set {
            self.view.bounds = newValue
        }
    }

    open var isUserInteractionEnabled: Bool {
        get {
            return self.view.isUserInteractionEnabled
        } set {
            self.view.isUserInteractionEnabled = newValue
        }
    }

    open var alpha: CGFloat {
        get {
            return self.view.alpha
        } set {
            self.view.alpha = newValue
        }
    }

    /// Whether the view or layer of this display node is currently in a window.
    public var isInHierarchy: Bool {
        return self.view.window != nil
    }

    /// Called just after the view is added to a window.
    open func didEnterHierarchy() {
    }

    /// Called after the view is removed from the window.
    open func didExitHierarchy() {
    }

    open func addSubnode(_ node: ASDisplayNode) {
        self.view.addSubview(node.view)
    }
}
