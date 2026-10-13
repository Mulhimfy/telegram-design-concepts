import UIKit

// Signature stub of AsyncDisplayKit's ASDisplayNode — only the members DepthSwipe (and the
// ChatListItemNode hooks' stand-in, HookCheck) use, from Telegram-iOS @ f1dd7a2:
//   Source/PublicHeaders/AsyncDisplayKit/ASDisplayNode.h
//     + (void)drawRect:(CGRect)bounds withParameters:(nullable id)parameters
//            isCancelled:(AS_NOESCAPE asdisplaynode_iscancelled_block_t)isCancelledBlock
//          isRasterizing:(BOOL)isRasterizing;
//     @property (readonly) CALayer * layer;
//     hidden (UIViewBridge)
//   Source/PublicHeaders/AsyncDisplayKit/ASDisplayNode+Subclasses.h
//     @property (readonly, getter=isInHierarchy) BOOL inHierarchy;
open class ASDisplayNode: NSObject {
    private let backingView = UIView()

    public var layer: CALayer {
        return self.backingView.layer
    }

    open var isHidden: Bool {
        get {
            return self.backingView.isHidden
        } set {
            self.backingView.isHidden = newValue
        }
    }

    /// Whether the view or layer of this display node is currently in a window.
    public var isInHierarchy: Bool {
        return self.backingView.window != nil
    }

    public override init() {
        super.init()
    }

    @objc open class func draw(_ bounds: CGRect, withParameters parameters: Any?, isCancelled isCancelledBlock: () -> Bool, isRasterizing: Bool) {
    }
}
