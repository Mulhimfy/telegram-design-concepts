import UIKit
import AsyncDisplayKit
import GlassGifts

// The PeerInfoGiftsPaneNode hook of ios/patches/0005-glass-gifts.patch, typechecked against the module's real API and
// the ASDisplayNode stub (didEnterHierarchy / didExitHierarchy, ASDisplayNode+Subclasses.h). The pane is reduced to an
// ASDisplayNode; the two overrides and the property are the patch's.
public final class PeerInfoGiftsPaneNodeShape: ASDisplayNode {
    private var glassGiftMotion: GlassGiftMotion.Client?

    public override func didEnterHierarchy() {
        super.didEnterHierarchy()

        self.glassGiftMotion = GlassGiftMotion.shared.addClient(view: self.view)
    }

    public override func didExitHierarchy() {
        super.didExitHierarchy()

        self.glassGiftMotion = nil
    }
}
