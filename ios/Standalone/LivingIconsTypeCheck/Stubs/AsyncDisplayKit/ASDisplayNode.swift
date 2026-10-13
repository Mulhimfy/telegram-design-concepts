import UIKit

// Signature stub of AsyncDisplayKit's ASDisplayNode (the members LivingSettingsIcons uses), from Telegram-iOS
// @ f1dd7a2, submodules/AsyncDisplayKit/Source/PublicHeaders/AsyncDisplayKit/ASDisplayNode.h:
//   @property (readonly) CALayer * layer;                                  (:244)
//   @property (nullable, readonly, weak) ASDisplayNode *supernode;         (:381)
//   @property (getter=isHidden) BOOL hidden;                               (:681, UIViewBridge)
//   - (void)addSubnode:(ASDisplayNode *)subnode;                           (:317)
open class ASDisplayNode: NSObject {
    public let layer: CALayer

    public private(set) weak var supernode: ASDisplayNode?

    public override init() {
        self.layer = CALayer()
        super.init()
    }

    open var isHidden: Bool {
        get {
            return self.layer.isHidden
        } set {
            self.layer.isHidden = newValue
        }
    }

    open func addSubnode(_ subnode: ASDisplayNode) {
        subnode.supernode = self
        self.layer.addSublayer(subnode.layer)
    }
}
