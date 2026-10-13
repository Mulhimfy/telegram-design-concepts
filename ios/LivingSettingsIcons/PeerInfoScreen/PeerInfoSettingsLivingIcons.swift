import Foundation
import UIKit
import AsyncDisplayKit
import Display
import LivingSettingsIcons

/// A Settings row's node whose static icon a living icon can play over (the disclosure and action rows).
protocol PeerInfoScreenLivingIconItemNode: AnyObject {
    /// The node showing the row's static icon, while it shows one.
    var livingIconImageNode: ASImageNode? { get }
}

/// Living Icons in the Settings tab (tgdesign prototype/src/settings/living-icons.js, nav.js): tapping a row squashes
/// its icon; coming back from the row's page — about 0.2 s into a back-button pop, or when a swipe back completes —
/// the icon comes alive in place. One icon at a time; nothing runs at rest; nothing plays with Reduce Motion.
final class PeerInfoSettingsLivingIcons {
    let player = LivingSettingsIconPlayer()
    /// The row whose page is open (or opening).
    fileprivate var openedSection: PeerInfoSettingsSection?
    fileprivate var openedTimestamp: Double = 0.0
    /// Settings went away since (the row's page was pushed).
    fileprivate var isAway = false
    /// Cancels a pending start when Settings goes away again first.
    fileprivate var generation = 0
}

extension PeerInfoScreenNode {
    /// The row that opens `section` (PeerInfoSettingsItems.swift: its section and item id) and its living icon. The
    /// emoji status row is left out: it opens a picker over Settings, not a page (and its icon depends on the status).
    private static func livingIconRow(_ section: PeerInfoSettingsSection) -> (section: SettingsSection, id: Int, icon: LivingSettingsIcon)? {
        switch section {
        case .profileColor:
            return (.edit, 1, .profileColor)
        case .avatar:
            return (.edit, 2, .profilePhoto)
        case .profile:
            return (.myProfile, 0, .myProfile)
        case .wallet:
            return (.wallet, 0, .money)
        case .proxy:
            return (.proxy, 0, .proxy)
        case .savedMessages:
            return (.shortcuts, 1, .savedMessages)
        case .recentCalls:
            return (.shortcuts, 2, .recentCalls)
        case .devices:
            return (.shortcuts, 3, .devices)
        case .chatFolders:
            return (.shortcuts, 4, .chatFolders)
        case .notificationsAndSounds:
            return (.advanced, 0, .notifications)
        case .privacyAndSecurity:
            return (.advanced, 1, .privacy)
        case .dataAndStorage:
            return (.advanced, 2, .dataAndStorage)
        case .appearance:
            return (.advanced, 3, .appearance)
        case .language:
            return (.advanced, 4, .language)
        case .powerSaving:
            return (.advanced, 6, .powerSaving)
        case .premium:
            return (.payment, 100, .premium)
        case .stars:
            return (.payment, 102, .stars)
        case .businessSetup:
            return (.payment, 104, .business)
        case .premiumGift:
            return (.payment, 105, .gift)
        case .support:
            return (.support, 0, .support)
        case .faq:
            return (.support, 1, .faq)
        case .tips:
            return (.support, 2, .tips)
        default:
            return nil
        }
    }

    /// The row's static icon node and the list card it lies in.
    private func livingIconTarget(_ section: PeerInfoSettingsSection) -> (icon: LivingSettingsIcon, imageNode: ASImageNode, container: ASDisplayNode)? {
        guard self.isSettings, let row = PeerInfoScreenNode.livingIconRow(section), let sectionNode = self.regularSections[AnyHashable(row.section)], let itemNode = sectionNode.itemNodes[AnyHashable(row.id)], let host = itemNode as? PeerInfoScreenLivingIconItemNode, let imageNode = host.livingIconImageNode, let container = itemNode.supernode else {
            return nil
        }
        return (row.icon, imageNode, container)
    }

    /// Whether a finger is revealing Settings (a swipe back in progress: NavigationContainer's pan).
    private var isLivingIconsSwipeInProgress: Bool {
        var view: UIView? = self.view
        while let current = view {
            for recognizer in current.gestureRecognizers ?? [] where recognizer is UIPanGestureRecognizer {
                if recognizer.state == .began || recognizer.state == .changed {
                    return true
                }
            }
            view = current.superview
        }
        return false
    }

    /// A Settings row was tapped (`openSettings(section:)`): its icon gives under the finger, and it is remembered.
    func livingIconsWillOpen(section: PeerInfoSettingsSection) {
        let livingIcons = self.livingIcons
        livingIcons.generation += 1
        guard let target = self.livingIconTarget(section) else {
            livingIcons.openedSection = nil
            return
        }
        livingIcons.openedSection = section
        livingIcons.openedTimestamp = CACurrentMediaTime()
        livingIcons.isAway = false
        livingIcons.player.press(imageNode: target.imageNode, container: target.container)
    }

    /// Settings goes away: when that is the tapped row's page coming in (soon after the tap), wait for Settings to
    /// come back; otherwise forget the row.
    func livingIconsWillDisappear() {
        let livingIcons = self.livingIcons
        livingIcons.generation += 1
        if livingIcons.openedSection != nil && !livingIcons.isAway {
            if CACurrentMediaTime() - livingIcons.openedTimestamp < 2.0 {
                livingIcons.isAway = true
            } else {
                livingIcons.openedSection = nil
            }
        }
    }

    /// Settings starts coming back. A back-button pop: the icon plays 0.2 s in, when the page has nearly landed (the
    /// 0.5 s spring is at 95 %). A swipe back calls this as the finger starts; the icon plays when it completes.
    func livingIconsWillAppear(animated: Bool) {
        let livingIcons = self.livingIcons
        guard livingIcons.isAway, livingIcons.openedSection != nil, animated, !self.isLivingIconsSwipeInProgress else {
            return
        }
        livingIcons.generation += 1
        let generation = livingIcons.generation
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.2, execute: { [weak self] in
            guard let self, self.livingIcons.generation == generation else {
                return
            }
            self.livingIconsPlay()
        })
    }

    /// Settings is shown again: the end of a pop, or of a swipe back.
    func livingIconsDidAppear() {
        self.livingIconsPlay()
    }

    private func livingIconsPlay() {
        let livingIcons = self.livingIcons
        guard livingIcons.isAway, let section = livingIcons.openedSection else {
            return
        }
        livingIcons.openedSection = nil
        livingIcons.isAway = false
        guard let target = self.livingIconTarget(section) else {
            return
        }
        // Only a row on screen.
        let frame = target.imageNode.layer.convert(target.imageNode.layer.bounds, to: self.layer)
        guard frame.intersects(self.bounds) else {
            return
        }
        // The list cards' corners (PresentationResourcesItemList.cornersImage, glass: 26).
        livingIcons.player.play(target.icon, imageNode: target.imageNode, container: target.container, glyphColor: self.presentationData.theme.list.itemAccentColor, cornerRadius: 26.0)
    }
}
