import Foundation
import UIKit
import QuartzCore
import AsyncDisplayKit
import Display

// Depth Swipe for one chat list row — the Swift twin of the wiring in
// prototype/src/chats/chat-list.js (ChatRow.depthStart / setOffset / update and the reveal options'
// haptic, prototype/src/chats/reveal-options.js):
//   · ChatListItemNode.updateRevealOffset feeds every change of the reveal offset (the finger, the
//     release spring, a tap closing the row, an action closing or filling it) and whether the
//     full-swipe action is armed; the reveal gesture's start offset (while the finger holds the
//     row) is read every frame; the row's layout feeds contentUpdated();
//   · a swipe, or a move on its own of more than half a point, starts the rig: the flat name,
//     message and photo are measured and drawn once (DepthSwipeContent), replaced by layers
//     (DepthSwipeLayers) and hidden; a display link then runs the rig on the offset as it is
//     displayed, its velocity and the pull;
//   · the outer action arming (the haptic ItemListRevealOptionsNode plays) spins the letters and
//     flips the disc;
//   · when nothing moves any more and nothing is round the rim the layers go and the flat row shows
//     again; resting open with pieces round the rim the layers stay without a display link.
// Reduce Motion: the rig does not run.

/// The flat pieces of a row the rig replaces while it runs.
public struct DepthSwipeParts {
    /// The name (one TextNode, drawn letter by letter from its own lines).
    public var titleNode: TextNode?
    /// The message (its rendered lines become plates).
    public var textNode: TextNode?
    /// Groups: the author's line above the message (one plate).
    public var authorNode: ASDisplayNode?
    /// The photo (the disc replaces it) and, inside it, the picture itself (the disc's face, with
    /// parallax); whatever else the photo draws, like a story ring, is printed on the face.
    public var avatarNode: ASDisplayNode?
    public var avatarPictureNode: ASDisplayNode?
    /// Flat badges that roll over the rim with the row: the name's icons and badges, and what sits
    /// on the photo's edge (online, timer, live…).
    public var badges: [CALayer]
    /// The row's right inset (safe area): the message box ends that much earlier.
    public var rightInset: CGFloat
    /// Day / night extrusion colours.
    public var isDark: Bool

    public init(titleNode: TextNode?, textNode: TextNode?, authorNode: ASDisplayNode?, avatarNode: ASDisplayNode?, avatarPictureNode: ASDisplayNode?, badges: [CALayer], rightInset: CGFloat, isDark: Bool) {
        self.titleNode = titleNode
        self.textNode = textNode
        self.authorNode = authorNode
        self.avatarNode = avatarNode
        self.avatarPictureNode = avatarPictureNode
        self.badges = badges
        self.rightInset = rightInset
        self.isDark = isDark
    }
}

public final class DepthSwipeController {
    /// The flat pieces are hidden by a finished, kept animation of `hidden`: it hides what is on
    /// screen without touching the values the row's own layout sets (nor is it overridden by its
    /// opacity animations), and removing it shows them as they are now.
    private static let hiddenAnimationKey = "DepthSwipe.flat"

    private weak var contentNode: ASDisplayNode?
    private let gestureInitialOffset: () -> CGFloat?
    private let parts: () -> DepthSwipeParts?

    private let rig = DepthSwipeRig(geometry: DepthSwipeGeometry(titleX: 0.0, titleOrigin: 0.0, glyphCenters: [], iconCenters: [], textLeft: nil, lineCount: 0, avatarCenter: nil, avatarHalf: 0.0))
    private var tracker = DepthSwipeTracker()
    private var layers: DepthSwipeLayers?
    private var hiddenLayers: [CALayer] = []
    private var link: SharedDisplayLinkDriver.Link?
    private var frameDuration: Double = 1.0 / 60.0

    private var targetOffset: CGFloat = 0.0
    private var isExtendedActionArmed: Bool = false
    /// Where the row was the frame before the rig started (the velocity starts from it).
    private var startOffset: Double?
    private var lastPresented: (offset: CGFloat, time: Double)?
    private var lastFrame: (time: Double, offset: Double, pull: Double)?
    /// The disc's edge pictures, kept for the row's next swipes.
    private var edgeImages: (size: CGSize, cornerRadius: CGFloat, face: CGImage?, back: CGImage?)?

    /// `contentNode`: the node the reveal offset moves (its bounds origin is −offset), whose
    /// coordinates are the row's at rest. `gestureInitialOffset`: the reveal offset when the finger
    /// caught the row, while it drags it (nil otherwise). `parts`: the row's flat pieces, asked for
    /// when the rig starts and when the row's content changes while it runs.
    public init(contentNode: ASDisplayNode, gestureInitialOffset: @escaping () -> CGFloat?, parts: @escaping () -> DepthSwipeParts?) {
        self.contentNode = contentNode
        self.gestureInitialOffset = gestureInitialOffset
        self.parts = parts
    }

    deinit {
        // The row goes with its layers (possibly off the main thread): only the display link is
        // left to stop.
        self.link?.invalidate()
    }

    public var isActive: Bool {
        return self.rig.isActive
    }

    /// The rig's clock: the time the frame being prepared will be on screen.
    private func displayTime() -> Double {
        return CACurrentMediaTime() + self.frameDuration
    }

    // MARK: - Hooks

    /// Every change of the reveal offset (ItemListRevealOptionsItemNode.updateRevealOffset).
    /// `isExtendedActionArmed`: the full-swipe action is armed (letting go runs it).
    public func updateRevealOffset(_ offset: CGFloat, transition: ContainedViewLayoutTransition, isExtendedActionArmed: Bool) {
        let previousTarget = self.targetOffset
        let presented = self.presentedOffset() ?? previousTarget
        self.targetOffset = offset
        let now = self.displayTime()

        if self.gestureInitialOffset() != nil {
            // ChatRow.beginSwipe: the finger moves the row (a running rig carries on).
            if !self.rig.isActive {
                self.begin(at: now, from: previousTarget)
            }
        } else if transition.isAnimated && DepthSwipeTracker.animatedMoveStarts(target: Double(offset), presented: Double(presented)) {
            // ChatRow.setOffset(animated): the row moves on its own.
            if !self.rig.isActive {
                self.begin(at: now, from: presented)
            }
        }

        // The full-swipe moment: ItemListRevealOptionsNode's haptic when the outer action arms.
        if isExtendedActionArmed && !self.isExtendedActionArmed && !transition.isAnimated {
            self.rig.spin(at: now, direction: offset > 0.0 ? 1 : -1)
        }
        self.isExtendedActionArmed = isExtendedActionArmed

        if self.rig.isActive {
            self.startLink()
        }
    }

    /// The row's content was laid out again (a new message, the mute icon, another theme…): while
    /// the rig runs its pieces are rebuilt from the new content and the motion carries on.
    public func contentUpdated() {
        if !self.rig.isActive {
            return
        }
        self.removeLayers()
        if !self.build() {
            self.rig.end()
            self.stopLink()
            return
        }
        if let lastFrame = self.lastFrame {
            // The new pieces where the old ones were.
            self.rig.update(at: lastFrame.time, offset: lastFrame.offset, velocity: self.tracker.velocity, pull: lastFrame.pull)
            self.layers?.apply(self.rig.frame)
        }
        self.startLink()
    }

    /// Back to the flat row at once.
    public func reset() {
        self.end()
        self.isExtendedActionArmed = false
    }

    // MARK: - Lifecycle

    private func begin(at now: Double, from offset: CGFloat) {
        if UIAccessibility.isReduceMotionEnabled {
            return
        }
        guard let contentNode = self.contentNode, contentNode.isInHierarchy else {
            return
        }
        if !self.build() {
            return
        }
        self.rig.begin(at: now)
        self.startOffset = Double(offset)
        self.lastPresented = nil
        self.lastFrame = nil
        self.startLink()
    }

    private func end() {
        if self.rig.isActive {
            self.rig.end()
        }
        self.removeLayers()
        self.stopLink()
        self.startOffset = nil
        self.lastFrame = nil
    }

    /// Measures the flat pieces, draws them on layers and hides them. False when there is nothing
    /// to show.
    private func build() -> Bool {
        guard let contentNode = self.contentNode, let parts = self.parts() else {
            return false
        }
        let content = contentNode.layer
        let look = DepthSwipeLook.self
        var hidden: [CALayer] = []

        func isShown(_ layer: CALayer) -> Bool {
            return !layer.isHidden && layer.opacity > 0.01 && layer.superlayer != nil && layer.bounds.width > 0.0 && layer.bounds.height > 0.0
        }
        func isInside(_ layer: CALayer, _ ancestor: CALayer) -> Bool {
            var current = layer.superlayer
            while let candidate = current {
                if candidate === ancestor {
                    return true
                }
                current = candidate.superlayer
            }
            return false
        }
        let shownBadges = parts.badges.filter(isShown)

        // The name.
        var title: (art: DepthSwipeTitleArt, frame: CGRect, parent: CALayer, above: CALayer)?
        var titleX = 0.0
        var titleOrigin = 0.0
        var glyphCenters: [Double] = []
        if let titleNode = parts.titleNode, let layout = titleNode.cachedLayout, isShown(titleNode.layer), let parent = titleNode.layer.superlayer {
            let layer = titleNode.layer
            if let art = DepthSwipeTitleArt.make(layout: layout, nodeSize: layer.bounds.size, isDark: parts.isDark) {
                title = (art, layer.frame, parent, layer)
                titleX = Double(layer.convert(layer.bounds, to: content).minX)
                titleOrigin = Double(layer.bounds.width * 0.5)
                glyphCenters = art.units.map { Double($0.x + $0.width * 0.5) }
                hidden.append(layer)
            }
        }

        // The message: the author's line, then the message's lines.
        var lines: (plates: [DepthSwipePlateArt], box: CGRect, parent: CALayer, above: CALayer)?
        var textLeft: Double?
        if let textNode = parts.textNode, isShown(textNode.layer), let parent = textNode.layer.superlayer {
            var plates: [DepthSwipePlateArt] = []
            var above = textNode.layer
            if let authorNode = parts.authorNode, isShown(authorNode.layer), authorNode.layer.superlayer === parent, let plate = DepthSwipeSnapshot.plate(of: authorNode.layer, in: parent) {
                plates.append(plate)
                hidden.append(authorNode.layer)
                if let sublayers = parent.sublayers, let authorIndex = sublayers.firstIndex(of: authorNode.layer), let textIndex = sublayers.firstIndex(of: textNode.layer), authorIndex > textIndex {
                    above = authorNode.layer
                }
            }
            plates.append(contentsOf: DepthSwipeSnapshot.lines(of: textNode, in: parent))
            if !plates.isEmpty {
                hidden.append(textNode.layer)
                let left = plates.map(\.frame.minX).min() ?? 0.0
                let top = plates.map(\.frame.minY).min() ?? 0.0
                let bottom = plates.map(\.frame.maxY).max() ?? 0.0
                // The box ends where the prototype's does (chat-list.js: W − 16 − 26), in the parent.
                // (The content's coordinates are the row's at rest: its bounds origin carries the
                // reveal offset, its width is the row's.)
                let rowRight = content.convert(CGPoint(x: content.bounds.width - parts.rightInset - CGFloat(look.lines.boxRightInset), y: 0.0), to: parent).x
                let right = max(rowRight, plates.map(\.frame.maxX).max() ?? left)
                lines = (plates, CGRect(x: left, y: top, width: right - left, height: bottom - top), parent, above)
                textLeft = Double(parent.convert(CGPoint(x: left, y: 0.0), to: content).x)
            }
        }

        // The photo: its picture is the disc's face; the rest of its drawing (a story ring) is
        // printed on the face; what sits on its edge rolls as badges, so it is left out.
        var avatar: (art: DepthSwipeDiscArt, frame: CGRect, parent: CALayer, above: CALayer)?
        var avatarCenter: Double?
        var avatarHalf = 0.0
        if let avatarNode = parts.avatarNode, isShown(avatarNode.layer), let parent = avatarNode.layer.superlayer {
            let layer = avatarNode.layer
            let onEdge = shownBadges.filter { isInside($0, layer) }
            var picture: (image: CGImage, frame: CGRect)?
            var decorations: CGImage?
            var cornerFraction: CGFloat = 0.5
            if let pictureLayer = parts.avatarPictureNode?.layer, isShown(pictureLayer), isInside(pictureLayer, layer) {
                if let image = DepthSwipeSnapshot.image(of: pictureLayer) {
                    let frame = pictureLayer.convert(pictureLayer.bounds, to: layer).offsetBy(dx: -layer.bounds.minX, dy: -layer.bounds.minY)
                    picture = (image, frame)
                    cornerFraction = DepthSwipeSnapshot.cornerFraction(of: pictureLayer)
                    // Anything else the photo shows (a story ring) is printed on the face.
                    let others = (layer.sublayers ?? []).filter { sublayer in
                        return sublayer !== pictureLayer && !onEdge.contains(where: { $0 === sublayer }) && isShown(sublayer)
                    }
                    if !others.isEmpty {
                        decorations = DepthSwipeSnapshot.image(of: layer, hiding: onEdge + [pictureLayer])
                    }
                }
            } else if let image = DepthSwipeSnapshot.image(of: layer, hiding: onEdge) {
                picture = (image, CGRect(origin: CGPoint(), size: layer.bounds.size))
                cornerFraction = DepthSwipeSnapshot.cornerFraction(of: layer)
            }
            if let picture {
                let size = layer.bounds.size
                let cornerRadius = cornerFraction * size.height
                let edges = self.edges(size: size, cornerRadius: cornerRadius)
                let art = DepthSwipeDiscArt(
                    picture: picture.image,
                    pictureFrame: picture.frame,
                    decorations: decorations,
                    cornerRadius: cornerRadius,
                    faceEdge: edges.face,
                    backEdge: edges.back,
                    color: DepthSwipeSnapshot.meanColor(picture.image) ?? (r: 0.35, g: 0.4, b: 0.45)
                )
                avatar = (art, layer.frame, parent, layer)
                let frame = layer.convert(layer.bounds, to: content)
                avatarCenter = Double(frame.midX)
                avatarHalf = Double(frame.width * 0.5)
                hidden.append(layer)
            }
        }

        if title == nil && lines == nil && avatar == nil {
            return false
        }

        // The badges: copies over them, measured flat.
        let badges = shownBadges.compactMap { layer -> DepthSwipeBadgeArt? in
            guard let image = DepthSwipeSnapshot.image(of: layer) else {
                return nil
            }
            return DepthSwipeBadgeArt(original: layer, image: image)
        }
        let iconCenters = badges.map { Double($0.original.convert($0.original.bounds, to: content).midX) }
        hidden.append(contentsOf: badges.map(\.original))

        self.rig.updateGeometry(DepthSwipeGeometry(
            titleX: titleX,
            titleOrigin: titleOrigin,
            glyphCenters: glyphCenters,
            iconCenters: iconCenters,
            textLeft: textLeft,
            lineCount: lines?.plates.count ?? 0,
            avatarCenter: avatarCenter,
            avatarHalf: avatarHalf
        ))
        self.layers = DepthSwipeLayers(title: title, lines: lines, avatar: avatar, badges: badges, badgeParent: content)
        self.hide(hidden)
        return true
    }

    private func edges(size: CGSize, cornerRadius: CGFloat) -> (face: CGImage?, back: CGImage?) {
        if let current = self.edgeImages, current.size == size, current.cornerRadius == cornerRadius {
            return (current.face, current.back)
        }
        let face = DepthSwipeSnapshot.edgeImage(size: size, cornerRadius: cornerRadius, ringAlpha: 0.35, shadowBlur: 6.0, shadowAlpha: 0.25)
        let back = DepthSwipeSnapshot.edgeImage(size: size, cornerRadius: cornerRadius, ringAlpha: 0.3, shadowBlur: 8.0, shadowAlpha: 0.3)
        self.edgeImages = (size, cornerRadius, face, back)
        return (face, back)
    }

    private func removeLayers() {
        self.layers?.remove()
        self.layers = nil
        self.show()
    }

    private func hide(_ layers: [CALayer]) {
        for layer in layers {
            let animation = CABasicAnimation(keyPath: "hidden")
            animation.fromValue = true as NSNumber
            animation.toValue = true as NSNumber
            animation.duration = 0.001
            animation.fillMode = .both
            animation.isRemovedOnCompletion = false
            layer.add(animation, forKey: DepthSwipeController.hiddenAnimationKey)
        }
        self.hiddenLayers = layers
    }

    private func show() {
        for layer in self.hiddenLayers {
            layer.removeAnimation(forKey: DepthSwipeController.hiddenAnimationKey)
        }
        self.hiddenLayers = []
    }

    // MARK: - Per frame

    private func startLink() {
        if self.link != nil {
            return
        }
        self.link = SharedDisplayLinkDriver.shared.add(framesPerSecond: .max, { [weak self] duration in
            self?.tick(duration: Double(duration))
        })
    }

    private func stopLink() {
        self.link?.invalidate()
        self.link = nil
    }

    /// The offset on screen now, if the row is animating (the reveal spring runs in Core Animation).
    private func presentedOffset() -> CGFloat? {
        guard let layer = self.contentNode?.layer, layer.animation(forKey: "bounds") != nil, let presentation = layer.presentation() else {
            return nil
        }
        return layer.frame.minX - presentation.bounds.minX
    }

    private func tick(duration: Double) {
        guard self.rig.isActive, let contentNode = self.contentNode, contentNode.isInHierarchy, !UIAccessibility.isReduceMotionEnabled else {
            self.end()
            return
        }
        if duration > 0.0 && duration < 0.1 {
            self.frameDuration = duration
        }
        // Everything is computed for the moment this frame will be on screen.
        let lead = self.frameDuration
        let now = self.displayTime()
        var x = self.targetOffset
        var isAnimating = false
        if let presented = self.presentedOffset() {
            // Core Animation moves the row (its render server is a frame ahead of what the app reads):
            // read where it is, then step ahead by one frame, no further than where it is going.
            isAnimating = true
            let clock = CACurrentMediaTime()
            var speed: CGFloat = 0.0
            if let last = self.lastPresented, clock - last.time > 1e-4 {
                speed = (presented - last.offset) / CGFloat(clock - last.time)
            }
            self.lastPresented = (presented, clock)
            let ahead = presented + speed * CGFloat(lead)
            x = min(max(ahead, min(presented, self.targetOffset)), max(presented, self.targetOffset))
        } else {
            self.lastPresented = nil
        }
        let offset = Double(x)
        let gestureInitialOffset = self.gestureInitialOffset()
        if let startOffset = self.startOffset {
            // The first frame: the velocity is measured from where the row was a frame ago.
            self.startOffset = nil
            self.tracker.reset(offset: startOffset, at: now, frameDuration: lead)
        }
        let velocity = self.tracker.frame(at: now, offset: offset)
        let pull = DepthSwipeTracker.pull(offset: offset, gestureInitialOffset: gestureInitialOffset.map { Double($0) })
        let moving = self.rig.update(at: now, offset: offset, velocity: velocity, pull: pull)
        self.lastFrame = (now, offset, pull)
        self.layers?.apply(self.rig.frame)

        let still = DepthSwipeTracker.isStill(isTracking: gestureInitialOffset != nil, isAnimating: isAnimating, velocity: velocity)
        if DepthSwipeTracker.shouldEnd(isMoving: moving, isStill: still, isRolled: self.rig.isRolled) {
            // Settled flat: back to the flat row.
            self.end()
        } else if !moving && still {
            // Settled open with pieces round the rim: the layers stay, nothing to animate.
            self.stopLink()
        }
    }
}
