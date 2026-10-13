import UIKit
import AsyncDisplayKit
import Display
import DepthSwipe

// The ChatListItemNode hooks of ios/patches/0004-depth-swipe.patch compiled against the module, on
// stand-ins for the row's members they touch (same names and shapes as in ChatListItem.swift at
// f1dd7a2). The two functions between BEGIN and END are the patch's, verbatim:
// tools/depth-swipe-patch.sh fails if they differ.

/// ItemListRevealOptionsItemNode with the two accessors the patch adds (ItemListEditableItem.swift).
class ItemListRevealOptionsItemNodeStandIn: ASDisplayNode {
    var revealGestureInitialOffset: CGFloat?
    var isDisplayingExtendedRevealOption: Bool = false
}

/// TextNodeWithEntities (`public let textNode: TextNode`).
final class TextNodeWithEntitiesStandIn {
    let textNode = TextNode()
}

/// AvatarNode (`public let contentNode: ContentNode`, an ASDisplayNode).
final class AvatarNodeStandIn: ASDisplayNode {
    let contentNode = ASDisplayNode()
}

/// ListViewItemLayoutParams (`leftInset`, `rightInset`).
struct ListViewItemLayoutParamsStandIn {
    let leftInset: CGFloat
    let rightInset: CGFloat
}

/// ChatListItem / PresentationData / PresentationTheme: `item.presentationData.theme.overallDarkAppearance`.
struct ChatListItemStandIn {
    struct PresentationData {
        struct Theme {
            let overallDarkAppearance: Bool
        }
        let theme: Theme
    }
    let presentationData: PresentationData
}

final class ChatListItemNodeStandIn: ItemListRevealOptionsItemNodeStandIn {
    var item: ChatListItemStandIn?
    var layoutParams: (ChatListItemStandIn, first: Bool, last: Bool, firstWithHeader: Bool, nextIsPinned: Bool, nextHasActiveRevealControls: Bool, ListViewItemLayoutParamsStandIn, countersSize: CGFloat)?
    let contextContainer = ASDisplayNode()                          // ContextControllerSourceNode
    let titleNode = TextNode()
    let authorNode = ASDisplayNode()                                // AuthorNode
    let textNode = TextNodeWithEntitiesStandIn()                    // TextNodeWithEntities
    let avatarNode = AvatarNodeStandIn()                            // AvatarNode
    let mutedIconNode = ASDisplayNode()                             // ASImageNode
    let onlineNode = ASDisplayNode()                                // PeerOnlineMarkerNode
    var secretIconNode: ASDisplayNode?                              // ASImageNode?
    var credibilityIconView: UIView?                                // ComponentHostView<Empty>?
    var verifiedIconView: UIView?
    var statusIconView: UIView?
    private var titleBadge: (backgroundView: UIImageView, textNode: TextNode)?
    var avatarTimerBadge: UIView?                                   // AvatarBadgeView?
    var avatarLiveBadge: (outline: UIImageView, foreground: UIImageView)?
    private var starView: UIView?                                   // StarView?
    private var communityAvatarBadgeBackgroundView: UIView?        // GlassBackgroundView?
    var avatarBadgeBackground: ASDisplayNode?                       // ASImageNode?
    var avatarBadgeNode: ASDisplayNode?                             // ChatListBadgeNode?
    private var depthSwipe: DepthSwipeController?

    /// ChatListItemNode.updateRevealOffset(offset:transition:), after moving the content and the card.
    func updateRevealOffset(offset: CGFloat, transition: ContainedViewLayoutTransition) {
        self.updateDepthSwipe(offset: offset, transition: transition)
    }

    /// asyncLayout's apply, right after `strongSelf.updateLayout(size:leftInset:rightInset:)`.
    func layoutApplied() {
        let strongSelf = self
        strongSelf.depthSwipe?.contentUpdated()
    }

    // BEGIN ChatListItem.swift hooks
    private func updateDepthSwipe(offset: CGFloat, transition: ContainedViewLayoutTransition) {
        let depthSwipe: DepthSwipeController
        if let current = self.depthSwipe {
            depthSwipe = current
        } else {
            depthSwipe = DepthSwipeController(contentNode: self.contextContainer, gestureInitialOffset: { [weak self] in
                return self?.revealGestureInitialOffset
            }, parts: { [weak self] in
                return self?.depthSwipeParts()
            })
            self.depthSwipe = depthSwipe
        }
        depthSwipe.updateRevealOffset(offset, transition: transition, isExtendedActionArmed: self.isDisplayingExtendedRevealOption)
    }

    private func depthSwipeParts() -> DepthSwipeParts? {
        guard let item = self.item else {
            return nil
        }
        // Flat pieces that roll over the rim with the row: the name's icons and badges, and what
        // sits on the photo's edge.
        let badgeViews: [UIView?] = [self.credibilityIconView, self.verifiedIconView, self.statusIconView, self.titleBadge?.backgroundView, self.avatarTimerBadge, self.avatarLiveBadge?.outline, self.avatarLiveBadge?.foreground, self.starView, self.communityAvatarBadgeBackgroundView]
        let badgeNodes: [ASDisplayNode?] = [self.secretIconNode, self.mutedIconNode, self.titleBadge?.textNode, self.onlineNode, self.avatarBadgeBackground, self.avatarBadgeNode]
        let badges: [CALayer] = badgeViews.compactMap({ $0?.layer }) + badgeNodes.compactMap({ $0?.layer })
        return DepthSwipeParts(
            titleNode: self.titleNode,
            textNode: self.textNode.textNode,
            authorNode: self.authorNode,
            avatarNode: self.avatarNode.isHidden ? nil : self.avatarNode,
            avatarPictureNode: self.avatarNode.contentNode,
            badges: badges,
            rightInset: self.layoutParams?.6.rightInset ?? 0.0,
            isDark: item.presentationData.theme.overallDarkAppearance
        )
    }
    // END ChatListItem.swift hooks
}
