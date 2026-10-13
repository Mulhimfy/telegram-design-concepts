import UIKit
import Display
import GlassGifts

// The GiftItemComponent hook of ios/patches/0005-glass-gifts.patch, typechecked against the module's real API.
// GiftItemComponent itself needs the whole Telegram-iOS build; here its View is reduced to the members the hook
// touches, with their real types' shapes (GiftItemComponent.swift @ f1dd7a2, lines noted). The block inside
// `update` is the patch's, line for line.

/// PresentationTheme (TelegramPresentationData): `overallDarkAppearance`.
final class PresentationThemeShape {
    let overallDarkAppearance: Bool

    init(overallDarkAppearance: Bool) {
        self.overallDarkAppearance = overallDarkAppearance
    }
}

/// GiftItemComponent's fields the hook reads (GiftItemComponent.swift:138-149, 151-177 + `glassEffect`).
struct GiftItemComponentShape {
    enum Mode: Equatable {
        case generic
        case profile
        case select
    }

    let theme: PresentationThemeShape
    let isEditing: Bool
    let mode: Mode
    let glassEffect: Bool
}

/// ComponentView<Empty> (ComponentFlow): `view`.
final class ComponentViewShape {
    var view: UIView?
}

/// AvatarNode (an ASDisplayNode): `view`.
final class AvatarNodeShape {
    let view = UIView()
}

/// BlurredBackgroundView (Display) is a UIView.
final class BlurredBackgroundViewShape: UIView {
}

/// InlineStickerItemLayer (EmojiTextAttachmentView) is a CALayer (MultiAnimationRenderTarget).
final class InlineStickerItemLayerShape: SimpleLayer {
}

/// GiftItemComponent.View (GiftItemComponent.swift:319-367), the members the hook passes.
final class GiftItemComponentViewShape: ContextControllerSourceView {
    let backgroundLayer = SimpleLayer()
    let patternView = ComponentViewShape()
    var avatarNode: AvatarNodeShape?
    let ribbonOutline = UIImageView()
    let ribbon = UIImageView()
    let ribbonText = ComponentViewShape()
    var animationLayer: InlineStickerItemLayerShape?
    var iconBackground: UIVisualEffectView?
    var hiddenIcon: UIImageView?
    var pinnedIcon: UIImageView?
    var dateLockedIcon: UIImageView?
    var resellBackground: BlurredBackgroundViewShape?
    let reselLabel = ComponentViewShape()

    private var glassTile: GlassGiftTile?

    func update(component: GiftItemComponentShape, availableSize: CGSize, backgroundColor: UIColor?) -> CGSize {
        let size = availableSize
        var cornerRadius: CGFloat = 16.0
        if component.mode == .generic {
            cornerRadius = 10.0
        }

        // ---- 0005-glass-gifts.patch, GiftItemComponent.View.update, before `return size` ----
        if component.glassEffect, case .profile = component.mode, !component.isEditing {
            let glassTile: GlassGiftTile
            if let current = self.glassTile {
                glassTile = current
            } else {
                glassTile = GlassGiftTile(hostView: self)
                self.glassTile = glassTile
            }
            glassTile.update(
                size: size,
                cornerRadius: cornerRadius,
                isDark: component.theme.overallDarkAppearance,
                isCollectible: backgroundColor != nil,
                backdrop: self.patternView.view?.layer ?? self.backgroundLayer,
                gift: self.animationLayer,
                giftOverlays: [self.iconBackground, self.hiddenIcon, self.resellBackground, self.reselLabel.view],
                ribbon: [self.ribbonOutline, self.ribbon, self.ribbonText.view],
                badges: [self.avatarNode?.view, self.pinnedIcon, self.dateLockedIcon]
            )
        } else if let glassTile = self.glassTile {
            self.glassTile = nil
            glassTile.remove()
        }
        // ---- end of the hook ----

        return size
    }
}
