import Foundation
import UIKit
import Display

/// The glass on one gift tile: `GiftItemComponent.View` on a profile's Gifts tab (prototype/src/profile/profile-page.js,
/// the tile part of the grid; the look is prototype/styles/telegram.css `.gift-*`).
///
/// The tile view keeps all its own layers and layout; the glass adds its layers next to them (GlassGiftTileLayers) and
/// leans the whole tile through the view's `sublayerTransform`, which never touches the frame the grid sets. The parts
/// that float above the glass — the sticker (and what sits on it: the hidden-gift badge, the resale price), the corner
/// ribbon, the sender's avatar and the other corner badges — get their depth as `zPosition`, so the tile's perspective
/// gives them parallax; the sticker also slides a little over the glass.
///
/// Telegram's context gesture (ContextControllerSourceView, 0.12 s, then a shrink to (w − 15) / w over 0.2 s and the
/// menu) shrinks the tile through the same `sublayerTransform`, so the glass takes it over: its progress
/// (`customActivationProgress`) becomes one factor of the tile's transform, eased back exactly as the default does
/// (0.2 s ease-out).
///
/// Lifecycle — nothing animates at rest:
/// · a touch, a release, a burst, the press shrink and the depth fading in or out run a display link
///   (`SharedDisplayLinkDriver`, `.max`) that stops when everything has settled;
/// · the phone's tilt (GlassGiftMotion, only while a gifts pane is on screen) is drawn as it arrives;
/// · at rest with no light the tile's transform is exactly identity and nothing floats: the tile keeps its own
///   geometry under the glass's static light. The depth (`zPosition` and the perspective) fades in over ~0.2 s when the
///   glass wakes (the sticker lifts toward you a little more than the ×1.01 of the glass) and out when it rests again.
/// Reduce Motion: no lean, lift, depth or sticker slide; the light still follows the finger (sheen, streak, edge,
/// fragments, sparkles) and not the phone (GlassGiftMotion doesn't run).
public final class GlassGiftTile {
    /// A layer that floats above the glass.
    private final class FloatingPart {
        weak var layer: CALayer?
        let depth: Double
        let slides: Bool
        /// Where the tile view put it (the glass adds the slide on top).
        var basePosition: CGPoint
        /// What the glass last wrote, to tell the tile view's own layout from the glass's slide.
        var writtenPosition: CGPoint?

        init(layer: CALayer, depth: Double, slides: Bool) {
            self.layer = layer
            self.depth = depth
            self.slides = slides
            self.basePosition = layer.position
        }

        func restore() {
            guard let layer = self.layer else {
                return
            }
            layer.zPosition = 0.0
            if self.slides, let writtenPosition = self.writtenPosition, layer.position == writtenPosition {
                layer.position = self.basePosition
            }
            self.writtenPosition = nil
        }
    }

    /// The press shrink of Telegram's context gesture (ContextControllerSourceNode.swift:237-291).
    private struct Press {
        var scale: CGFloat = 1.0
        var easing: (from: CGFloat, start: Double)?
    }

    /// The context gesture's ease back: 0.2 s, ease-out (ContextControllerSourceNode.swift:278).
    private static let pressReleaseDuration: Double = 0.2
    /// The light counts as "on" (the depth stays up) above this tilt, degrees.
    private static let lightThreshold: Double = 0.05

    private weak var hostView: ContextControllerSourceView?
    private var model = GlassTileModel()
    private let layers = GlassGiftTileLayers()
    private let gestureRecognizer: GlassGiftGestureRecognizer
    private var displayLink: SharedDisplayLinkDriver.Link?
    private var lastFrameTime: Double?
    private var motionListener: GlassGiftMotion.Listener?
    private var light: GlassGiftLight?
    private var press = Press()
    /// 0 at rest … 1 awake: scales the perspective and the parts' depth.
    private var depthFactor: Double = 0.0
    private var floatingParts: [FloatingPart] = []
    private var reduceMotionObserver: NSObjectProtocol?
    private var isRemoved = false

    /// `hostView` is the tile (GiftItemComponent.View). The glass installs its gesture recognizer and takes over the
    /// press shrink of its context gesture until `remove()`.
    public init(hostView: ContextControllerSourceView) {
        self.hostView = hostView
        self.gestureRecognizer = GlassGiftGestureRecognizer(target: nil, action: nil)
        self.gestureRecognizer.tile = self
        hostView.addGestureRecognizer(self.gestureRecognizer)

        hostView.customActivationProgress = { [weak self] progress, transition in
            self?.updatePress(progress: progress, transition: transition)
        }

        self.layers.shadow.didEnterHierarchy = { [weak self] in
            self?.updateIsInHierarchy()
        }
        self.layers.shadow.didExitHierarchy = { [weak self] in
            self?.updateIsInHierarchy()
        }
        self.reduceMotionObserver = NotificationCenter.default.addObserver(forName: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.redraw()
        })
    }

    deinit {
        self.displayLink?.invalidate()
        if let reduceMotionObserver = self.reduceMotionObserver {
            NotificationCenter.default.removeObserver(reduceMotionObserver)
        }
    }

    /// Lays the glass out over the tile; the tile view calls it at the end of every update.
    /// - backdrop: the topmost layer of the tile's backdrop (the collectible pattern view's, else its background
    ///   layer): the glass light goes right above it.
    /// - gift: the sticker; giftOverlays: what sits on it (the hidden-gift badge, the resale price). They float
    ///   `GlassGiftLook.giftDepth` above the glass and slide with the lean.
    /// - ribbon: the corner ribbon (`ribbonDepth`); badges: the sender's avatar and the corner badges (`badgeDepth`).
    /// Views that are nil or not (any more) in the tile view are skipped.
    public func update(
        size: CGSize,
        cornerRadius: CGFloat,
        isDark: Bool,
        isCollectible: Bool,
        backdrop: CALayer,
        gift: CALayer?,
        giftOverlays: [UIView?],
        ribbon: [UIView?],
        badges: [UIView?]
    ) {
        guard let hostView = self.hostView, !self.isRemoved else {
            return
        }
        let floatingLayers: ([UIView?]) -> [CALayer] = { views in
            return views.compactMap { view -> CALayer? in
                guard let view, view.superview === hostView else {
                    return nil
                }
                return view.layer
            }
        }
        var giftLayers = floatingLayers(giftOverlays)
        if let gift, gift.superlayer === hostView.layer {
            giftLayers.insert(gift, at: 0)
        }
        self.layers.update(size: size, cornerRadius: cornerRadius, isDark: isDark, isCollectible: isCollectible)

        let hostLayer = hostView.layer
        if self.layers.shadow.superlayer !== hostLayer || hostLayer.sublayers?.first !== self.layers.shadow {
            hostLayer.insertSublayer(self.layers.shadow, at: 0)
        }
        // The glass light right above the backdrop, in order.
        var anchor = backdrop.superlayer === hostLayer ? backdrop : self.layers.shadow
        for layer in self.layers.glassLayers {
            if layer.superlayer !== hostLayer || !GlassGiftTile.isDirectlyAbove(layer, anchor, in: hostLayer) {
                hostLayer.insertSublayer(layer, above: anchor)
            }
            anchor = layer
        }
        for sparkle in self.layers.sparkles where sparkle.superlayer !== hostLayer {
            hostLayer.addSublayer(sparkle)
        }

        self.updateFloatingParts(gift: giftLayers, ribbon: floatingLayers(ribbon), badges: floatingLayers(badges))
        self.updateIsInHierarchy()
        self.redraw()
    }

    /// Takes the glass off the tile: its layers, the depth, the transform, the gesture and the press shrink.
    public func remove() {
        if self.isRemoved {
            return
        }
        self.isRemoved = true
        self.stopDisplayLink()
        self.motionListener = nil
        for part in self.floatingParts {
            part.restore()
        }
        self.floatingParts.removeAll()
        for layer in [self.layers.shadow] + self.layers.glassLayers + self.layers.sparkles {
            layer.removeFromSuperlayer()
        }
        if let hostView = self.hostView {
            hostView.removeGestureRecognizer(self.gestureRecognizer)
            hostView.customActivationProgress = nil
            hostView.layer.sublayerTransform = CATransform3DIdentity
        }
        self.gestureRecognizer.tile = nil
    }

    // MARK: - Interaction (GlassGiftGestureRecognizer)

    /// Touch down at `point` (tile coordinates): the glass leans toward it and a burst of light runs across it.
    func touchDown(at point: CGPoint) {
        // A touched tile is in the window, whatever its layers were told.
        self.updateIsInHierarchy()
        self.aim(at: point)
        self.burst()
    }

    /// The finger at `point` (tile coordinates; outside the tile counts as its edge).
    func aim(at point: CGPoint) {
        let size = self.layers.size
        guard size.width > 0.0, size.height > 0.0 else {
            return
        }
        self.model.aim(u: Double(point.x / size.width) * 2.0 - 1.0, v: Double(point.y / size.height) * 2.0 - 1.0)
        self.startDisplayLink()
    }

    func burst() {
        self.model.burst(at: CACurrentMediaTime())
        self.startDisplayLink()
    }

    /// The finger left: the glass eases home.
    func release() {
        self.model.release()
        self.startDisplayLink()
    }

    // MARK: - Drawing

    private func updateFloatingParts(gift: [CALayer], ribbon: [CALayer], badges: [CALayer]) {
        let groups: [(layers: [CALayer], depth: Double, slides: Bool)] = [
            (gift, GlassGiftLook.giftDepth, true),
            (ribbon, GlassGiftLook.ribbonDepth, false),
            (badges, GlassGiftLook.badgeDepth, false)
        ]
        var parts: [FloatingPart] = []
        for group in groups {
            for layer in group.layers {
                if let part = self.floatingParts.first(where: { $0.layer === layer && $0.depth == group.depth }) {
                    // The tile view laid it out again since the glass last moved it: that is the new base.
                    if part.writtenPosition == nil || layer.position != part.writtenPosition {
                        part.basePosition = layer.position
                        part.writtenPosition = nil
                    }
                    parts.append(part)
                } else {
                    parts.append(FloatingPart(layer: layer, depth: group.depth, slides: group.slides))
                }
            }
        }
        for part in self.floatingParts where !parts.contains(where: { $0 === part }) {
            part.restore()
        }
        self.floatingParts = parts
    }

    /// The tile is in a window: the glass's own layer says so (kCAOnOrderIn, as the sticker layer knows it), or the
    /// view does.
    private var isInHierarchy: Bool {
        return !self.isRemoved && (self.layers.shadow.isInHierarchy || self.hostView?.window != nil)
    }

    private func updateIsInHierarchy() {
        if self.isInHierarchy {
            if self.motionListener == nil {
                self.light = GlassGiftMotion.shared.light
                self.motionListener = GlassGiftMotion.shared.addListener({ [weak self] light in
                    self?.lightUpdated(light)
                })
            }
        } else if self.motionListener != nil || self.displayLink != nil {
            // Off the window: no light, no animation; back at rest when it returns.
            self.motionListener = nil
            self.light = nil
            self.settle()
        }
    }

    private func lightUpdated(_ light: GlassGiftLight?) {
        self.light = light
        if self.displayLink == nil {
            self.redraw()
        }
    }

    private func updatePress(progress: CGFloat, transition: ContextGestureTransition) {
        let width = self.layers.size.width
        guard width > 0.0 else {
            return
        }
        // ContextControllerSourceView's own shrink: max(0.7, (w − 15) / w) at full progress.
        let minScale = max(0.7, (width - 15.0) / width)
        let scale = 1.0 * (1.0 - progress) + minScale * progress
        switch transition {
        case .begin, .update:
            self.press.scale = scale
            self.press.easing = nil
            if self.displayLink == nil {
                self.redraw()
            }
        case .ended:
            self.press.easing = (self.press.scale, CACurrentMediaTime())
            self.startDisplayLink()
        }
    }

    private func startDisplayLink() {
        if !self.isInHierarchy {
            return
        }
        if self.displayLink == nil {
            self.lastFrameTime = CACurrentMediaTime()
            self.displayLink = SharedDisplayLinkDriver.shared.add(framesPerSecond: .max, { [weak self] _ in
                self?.tick()
            })
        }
    }

    private func stopDisplayLink() {
        self.displayLink?.invalidate()
        self.displayLink = nil
        self.lastFrameTime = nil
    }

    private func tick() {
        let now = CACurrentMediaTime()
        // The page's frame step: 0…50 ms (profile-page.js `update`).
        let dt = max(0.0, min(0.05, now - (self.lastFrameTime ?? now)))
        self.lastFrameTime = now

        let state = self.model.update(now: now, dt: dt, light: self.light)
        let pressSettled = self.advancePress(now: now)
        let depthSettled = self.advanceDepth(state: state, dt: dt)
        self.draw(state)
        if !state.isActive && pressSettled && depthSettled {
            self.stopDisplayLink()
        }
    }

    /// A frame without advancing time (the light moved, or the tile view laid out).
    private func redraw() {
        if self.isRemoved {
            return
        }
        let state = self.model.update(now: CACurrentMediaTime(), dt: 0.0, light: self.light)
        if self.depthTarget(state) != self.depthFactor {
            self.startDisplayLink()
        }
        self.draw(state)
    }

    /// Back at rest at once: no lean, no depth, no press.
    private func settle() {
        self.stopDisplayLink()
        self.model = GlassTileModel()
        self.press = Press()
        self.depthFactor = 0.0
        self.draw(self.model.update(now: CACurrentMediaTime(), dt: 0.0, light: self.light))
    }

    private func advancePress(now: Double) -> Bool {
        guard let easing = self.press.easing else {
            return true
        }
        let t = (now - easing.start) / GlassGiftTile.pressReleaseDuration
        if t >= 1.0 {
            self.press.scale = 1.0
            self.press.easing = nil
            return true
        }
        self.press.scale = easing.from + (1.0 - easing.from) * CGFloat(GlassGiftTiming.easeOut(t))
        return false
    }

    private func depthTarget(_ state: GlassTileState) -> Double {
        if UIAccessibility.isReduceMotionEnabled {
            return 0.0
        }
        if state.isActive || self.model.isTouching {
            return 1.0
        }
        if let light = self.light, max(abs(light.x), abs(light.y)) > GlassGiftTile.lightThreshold {
            return 1.0
        }
        return 0.0
    }

    /// The depth follows its target like the wallet card's scale: 1 − e^(−12 dt) (WCC:918).
    private func advanceDepth(state: GlassTileState, dt: Double) -> Bool {
        let target = self.depthTarget(state)
        self.depthFactor += (target - self.depthFactor) * (1.0 - exp(-12.0 * dt))
        if abs(target - self.depthFactor) < 0.001 {
            self.depthFactor = target
            return true
        }
        return false
    }

    private func draw(_ state: GlassTileState) {
        guard let hostView = self.hostView, !self.isRemoved else {
            return
        }
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let k = self.depthFactor

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        self.layers.apply(state)
        self.layers.setResting(k == 0.0 && !state.isActive && !self.model.isTouching && self.press.scale == 1.0 && self.press.easing == nil)

        // The tile leans as one: perspective, translate, scale, rotate X / Y / Z (the wallet card's order), then the
        // press shrink about the centre. At rest (k = 0 and no lean) this is exactly identity.
        let tilt: CATransform3D
        if reduceMotion || (k == 0.0 && !state.isActive) {
            // No lean (Reduce Motion), or resting with at most a hint of light (below `lightThreshold`): flat.
            tilt = CATransform3DIdentity
        } else {
            tilt = GlassGiftTile.tiltTransform(state, perspectiveFactor: k)
        }
        hostView.layer.sublayerTransform = CATransform3DConcat(tilt, CATransform3DMakeScale(self.press.scale, self.press.scale, 1.0))

        // The shadow stays flat under the glass (`.gift-shadow` is outside the tile in the prototype): its own
        // transform is translate · scale about its box, then the tile's lean undone.
        let shadowX = reduceMotion ? 0.0 : state.shadowX
        let shadowY = reduceMotion ? 2.0 : state.shadowY
        let shadowScale = reduceMotion ? 0.96 : state.shadowScale
        let shadowOpacity = reduceMotion ? 0.32 : state.shadowOpacity
        let insets = GlassGiftTileLayers.shadowInsets
        let shadowCentreOffset = (insets.top - insets.bottom) / 2.0
        let shadowTransform = CATransform3DConcat(
            CATransform3DMakeScale(CGFloat(shadowScale), CGFloat(shadowScale), 1.0),
            CATransform3DMakeTranslation(CGFloat(shadowX), CGFloat(shadowY) + shadowCentreOffset, 0.0)
        )
        self.layers.shadow.transform = CATransform3DIsIdentity(tilt) ? shadowTransform : CATransform3DConcat(shadowTransform, CATransform3DInvert(tilt))
        self.layers.shadow.opacity = Float(shadowOpacity)

        // What floats above the glass.
        let slideX = reduceMotion ? 0.0 : CGFloat(state.giftX)
        let slideY = reduceMotion ? 0.0 : CGFloat(state.giftY)
        for part in self.floatingParts {
            guard let layer = part.layer else {
                continue
            }
            layer.zPosition = CGFloat(part.depth * k)
            if part.slides {
                let position = CGPoint(x: part.basePosition.x + slideX, y: part.basePosition.y + slideY)
                if layer.position != position {
                    layer.position = position
                }
                part.writtenPosition = position
            }
        }

        CATransaction.commit()
    }

    /// perspective(650 / k) translate(tx, ty) scale(s) rotateX(pitch) rotateY(yaw) rotateZ(roll), the wallet card's
    /// makePerspectiveTransform (WalletCardComponent.swift:1386-1424) with the prototype's numbers.
    static func tiltTransform(_ state: GlassTileState, perspectiveFactor: Double) -> CATransform3D {
        var transform = CATransform3DIdentity
        transform.m34 = CGFloat(-perspectiveFactor / GlassGiftLook.perspective)
        transform = CATransform3DTranslate(transform, CGFloat(state.translationX), CGFloat(state.translationY), 0.0)
        transform = CATransform3DScale(transform, CGFloat(state.scale), CGFloat(state.scale), 1.0)
        transform = CATransform3DRotate(transform, CGFloat(state.pitch * Double.pi / 180.0), 1.0, 0.0, 0.0)
        transform = CATransform3DRotate(transform, CGFloat(state.yaw * Double.pi / 180.0), 0.0, 1.0, 0.0)
        transform = CATransform3DRotate(transform, CGFloat(state.roll * Double.pi / 180.0), 0.0, 0.0, 1.0)
        return transform
    }

    private static func isDirectlyAbove(_ layer: CALayer, _ anchor: CALayer, in superlayer: CALayer) -> Bool {
        guard let sublayers = superlayer.sublayers, let index = sublayers.firstIndex(where: { $0 === layer }), let anchorIndex = sublayers.firstIndex(where: { $0 === anchor }) else {
            return false
        }
        return index == anchorIndex + 1
    }
}
