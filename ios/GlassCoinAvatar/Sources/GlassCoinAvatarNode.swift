import Foundation
import UIKit
import AsyncDisplayKit
import Display
import UIKitRuntimeUtils
import SwiftSignalKit
import MetalEngine

/// What the glass shows this frame, for the lights that follow it: `GlassTurnLightNode` (the light it throws across the
/// header while it turns) and `GlassLightWaveNode.setLift` (the glow brightening while it is held).
public struct GlassCoinLight: Equatable {
    public var yaw: Double
    public var pitch: Double
    public var yawVelocity: Double
    /// The interaction's glass, 0 flat photo … 1 full glass.
    public var glass: Double
    /// The glass colour (rgb 0…1, cross-faded during a change) and how much of it shows (0 clear … 1 tinted).
    public var color: SIMD3<Float>
    public var tint: Double

    public init(yaw: Double, pitch: Double, yawVelocity: Double, glass: Double, color: SIMD3<Float>, tint: Double) {
        self.yaw = yaw
        self.pitch = pitch
        self.yawVelocity = yawVelocity
        self.glass = glass
        self.color = color
        self.tint = tint
    }
}

/// The glass avatar over a collapsed profile avatar (prototype/src/app.js, coin/coin-controller.js).
///
/// Under the finger the avatar turns into a thin sheet of glass and can be turned over to its back: the same photo by
/// default (one picture, both sides), or a back photo the user added (`setBackPhoto`: the photo turns over by itself to
/// show it). `setGlassColor` tints the glass: a short lift into glass (`GlassCoinModel.pulse`, 0.18 s), a 0.22 s colour
/// cross-fade and a 0.55 s flash of the edge light and glow; the light it sends across the screen is
/// `GlassLightWaveNode`'s, the light it throws across the header while it turns `GlassTurnLightNode`'s (both follow it
/// through `lightUpdated`).
///
/// Lifecycle — the glass renders only while something moves:
/// · active: a touch, a pulse, a colour change or a turn. The display link (`SharedDisplayLinkDriver`, `.max`) runs, and
///   the host hides its avatar (`setAvatarHidden`) once the face in front is loaded.
/// · resting: when the avatar at rest is not the plain photo — its back is in front, or the glass is tinted (a tinted
///   glass keeps `GlassCoinLook.restGlass` of glass at rest, coin-renderer.js) — the last frame stays over the real
///   avatar, which shows again underneath: no display link, one surface. It is released when the node leaves the
///   window or is disabled, and drawn again when it comes back.
/// · inactive: nothing is drawn and the surface is released; the real `AvatarNode` shows as before.
///
/// The node is centred on the avatar: its frame is `size × size` around the avatar centre, larger than the avatar so
/// the tilt, lift, translation, shadow and glow fit.
public final class GlassCoinAvatarNode: ASDisplayNode {
    /// VoiceOver action title; the host passes a localized string.
    public var accessibilityTurnOverTitle: String = "Turn Over" {
        didSet {
            self.updateAccessibility()
        }
    }

    /// Loads a face: `.photo(0)` is the profile photo (both sides, until a back photo is set). `.backPhoto` is asked for
    /// only while no `setBackPhoto` image is set (a back photo kept elsewhere).
    public var faceImage: ((GlassCoinFaceContent) -> Signal<UIImage?, NoError>)?
    /// The profile cover behind the avatar and its frame in this node's coordinates.
    public var coverSnapshot: (() -> (image: UIImage, frame: CGRect)?)?
    public var setAvatarHidden: ((Bool) -> Void)?
    /// The glass came to rest on its other side; `content` is the face now in front (`.photo(0)` or `.backPhoto`).
    public var landed: ((_ content: GlassCoinFaceContent) -> Void)?
    /// Every frame the glass draws (nil once it is put down): its pose and colour, for the lights that follow it.
    public var lightUpdated: ((GlassCoinLight?) -> Void)?
    /// Whether the glass may react at all (not while the avatar is expanded, edited, etc.).
    public var isEnabled: Bool = true {
        didSet {
            if self.isEnabled != oldValue {
                self.updateGestureEnabled()
                if self.isEnabled {
                    self.settle()
                } else {
                    self.cancelInteraction()
                }
                self.updateAccessibility()
            }
        }
    }

    /// The back photo the user chose (square, as the glass samples it), or nil: the back is the photo itself.
    public private(set) var backPhoto: UIImage?
    /// The glass colour, or nil for clear glass.
    public private(set) var glassColor: UIColor?

    /// The face in front: `.photo(0)`, or the back.
    public var frontContent: GlassCoinFaceContent {
        let time = CACurrentMediaTime()
        return self.model.content(forFace: self.model.face(atYaw: self.model.state(at: time).yaw))
    }

    private enum Phase {
        case inactive
        case active
        case resting
    }

    /// A glass colour change: the colour and tint cross-fade over 0.22 s (ease in-out), the flash runs 0.55 s.
    private struct ColorTransition {
        var start: Double
        var fromColor: SIMD3<Float>
        var toColor: SIMD3<Float>
        var fromTint: Double
        var toTint: Double
    }

    /// app.js `setGlassColor`: the tint tween, the flash tween (rising over its first 12 %) and the lift into glass.
    private static let colorFadeDuration: Double = 0.22
    private static let flashDuration: Double = 0.55
    private static let flashRise: Double = 0.12
    private static let colorPulseHold: Double = 0.18
    /// app.js `chooseBack`: the back photo sheet starts to leave 0.28 s after the pick and the avatar turns 0.75 s after
    /// it; "None" with the front in view is a short lift (pulse 0.18 s).
    private static let backPhotoTurnDelay: Double = 0.75
    private static let backPulseHold: Double = 0.18
    /// A programmatic flick of one face (the VoiceOver action), pt/s.
    private static let turnVelocity: Double = -430.0

    private let model: GlassCoinModel
    private let coinLayer: GlassCoinLayer
    private let hapticFeedback = HapticFeedback()
    private var gestureRecognizer: GlassCoinGestureRecognizer?
    private weak var hostView: UIView?
    private var displayLink: SharedDisplayLinkDriver.Link?
    private var lastFrameTime: Double?
    private var phase: Phase = .inactive
    /// The real avatar is hidden only while the glass moves, and only once it can draw the face in front.
    private var isAvatarHidden = false
    private var colorTransition: ColorTransition?
    /// What the card's back shows now: the back photo, or nil — the photo itself.
    private var shownBackPhoto: UIImage?
    /// A back chosen with `setBackPhoto(_:animated: true)` (the inner nil: none), waiting for its turn.
    private var scheduledBack: UIImage??
    /// A new back waiting for the front to come into view: a side only changes while it faces away.
    private var pendingBack: UIImage??
    private var pendingTurnGeneration = 0
    /// A back photo turn came due while the node was out of the window: it runs when the node is back.
    private var turnsWhenVisible = false
    private let faceDisposables = DisposableDict<String>()
    private var requestedFaces = Set<String>()
    private static var didPrewarm = false
    private var isReduceMotionEnabled: Bool {
        return UIAccessibility.isReduceMotionEnabled
    }

    public init(configuration: GlassCoinConfiguration = GlassCoinConfiguration()) {
        // One photo and its back — the photo itself until a back photo is set: no flipping through the gallery.
        let model = GlassCoinModel(photoCount: 1, configuration: configuration)
        model.back = .photo(0)
        self.model = model
        self.coinLayer = GlassCoinLayer()
        super.init()

        self.isUserInteractionEnabled = false
        self.coinLayer.isHidden = true
        self.layer.addSublayer(self.coinLayer)

        if !GlassCoinAvatarNode.didPrewarm {
            GlassCoinAvatarNode.didPrewarm = true
            prewarmGlassCoin()
        }

        self.model.onTick = { [weak self] isCatch in
            guard let self else {
                return
            }
            if isCatch {
                self.hapticFeedback.impact(.rigid)
            } else {
                // A detent each time the other side swings past edge-on.
                self.hapticFeedback.tap()
            }
        }
        self.model.onLand = { [weak self] changed, face in
            guard let self, changed else {
                return
            }
            self.hapticFeedback.impact(.medium)
            self.landed?(self.model.content(forFace: face))
        }
        self.model.onFaceChange = { [weak self] face in
            // The front came into view: the back faces away and takes the new back unseen (app.js chooseBack).
            guard let self, let back = self.pendingBack, abs(face) % 2 == 0 else {
                return
            }
            self.pendingBack = nil
            self.applyBack(back)
        }
    }

    deinit {
        self.displayLink?.invalidate()
        self.faceDisposables.dispose()
    }

    override public func didEnterHierarchy() {
        super.didEnterHierarchy()
        if self.turnsWhenVisible {
            self.turnsWhenVisible = false
            // Let the transition that brought the screen back finish first.
            self.scheduleChooseBack(after: 0.45)
        }
        self.settle()
    }

    override public func didExitHierarchy() {
        super.didExitHierarchy()
        // A move between windows passes through no window for a moment: decide at the end of this run loop turn.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isInHierarchy else {
                return
            }
            self.gestureRecognizer?.cancelPress()
            if self.phase != .inactive {
                let time = CACurrentMediaTime()
                self.model.jump(toFace: self.model.face(atYaw: self.model.state(at: time).yaw), at: time)
                self.finishColorTransition()
                self.deactivate()
            }
            // Nothing shows now: a back waiting for the front takes its place.
            self.applyPendingBack()
            // The faces load again when the node is back (the back photo is kept in `backPhoto`).
            self.resetFaces()
        }
    }

    /// Attaches the glass gesture to the view that shows the avatar (where its tap recognizer lives).
    public func attach(to view: UIView) {
        if let gestureRecognizer = self.gestureRecognizer {
            gestureRecognizer.view?.removeGestureRecognizer(gestureRecognizer)
        }
        let gestureRecognizer = GlassCoinGestureRecognizer(target: nil, action: nil)
        gestureRecognizer.cancelsTouchesInView = false
        gestureRecognizer.delaysTouchesEnded = false
        gestureRecognizer.pressed = { [weak self] point in
            self?.pointerDown(point)
        }
        gestureRecognizer.moved = { [weak self] point in
            self?.pointerMove(point)
        }
        gestureRecognizer.released = { [weak self] point, cancelled in
            self?.pointerUp(point, cancelled: cancelled)
        }
        view.addGestureRecognizer(gestureRecognizer)
        // Drags on the avatar belong to the glass, not to the swipe-back gesture.
        view.interactiveTransitionGestureRecognizerTest = { [weak self] _ in
            guard let self else {
                return false
            }
            return self.isEnabled && !self.isReduceMotionEnabled
        }
        self.gestureRecognizer = gestureRecognizer
        self.hostView = view
        self.updateGestureEnabled()
        self.updateAccessibility()
    }

    private func updateGestureEnabled() {
        // A disabled glass must not win drags from the context menu or swipe-back.
        self.gestureRecognizer?.isEnabled = self.isEnabled && !self.isReduceMotionEnabled
    }

    public func update(size: CGSize, avatarRadius: CGFloat, isDark: Bool, environment: GlassCoinEnvironment) {
        var look = self.coinLayer.look
        look.radius = avatarRadius
        // Thickness, edge band, lift and eye distance scale with the avatar (the 200 pt form-sheet avatar too); the
        // defaults are CoinLook's for the 100 pt avatar.
        let base = GlassCoinLook()
        let k = avatarRadius / base.radius
        look.halfThickness = base.halfThickness * k
        look.rimWidth = base.rimWidth * k
        look.liftZ = base.liftZ * k
        look.eyeDistance = base.eyeDistance * k
        self.coinLayer.look = look
        self.coinLayer.isDarkAppearance = isDark
        self.coinLayer.environment = environment
        let frame = CGRect(origin: CGPoint(), size: size)
        if self.coinLayer.frame != frame {
            self.coinLayer.frame = frame
            self.coinLayer.updateLayout()
        }
    }

    // MARK: - Back photo and glass colour

    /// Sets the back photo (nil: none — the back is the photo itself again). Animated — app.js `chooseBack`, 0.75 s later,
    /// as the picker leaves: with the front in view the new back is set at once (it faces away) and the avatar turns
    /// over to show it (`turnBy(1)`; "None": a short lift); with the back in view it turns (two faces for a new back,
    /// one for none) and the new back is set as the front passes. A side only changes while it faces away, so nothing
    /// pops in view. Not animated: set at once (restoring a saved choice).
    public func setBackPhoto(_ image: UIImage?, animated: Bool) {
        self.cancelScheduledTurn()
        let square = image.flatMap { glassCoinSquareImage($0) }
        self.backPhoto = square
        if animated {
            self.scheduledBack = .some(square)
            self.scheduleChooseBack(after: GlassCoinAvatarNode.backPhotoTurnDelay)
        } else {
            self.scheduledBack = nil
            self.pendingBack = nil
            self.applyBack(square)
            self.settle()
        }
    }

    /// Sets the glass colour (nil: clear glass). Animated — app.js `setGlassColor`: a light haptic, a 0.18 s lift into
    /// glass, the colour and tint cross-fading over 0.22 s, and a flash of the edge light and glow over 0.55 s.
    /// Not animated: just the new colour (restoring a saved choice).
    public func setGlassColor(_ color: UIColor?, animated: Bool) {
        let previous = self.glassColor
        self.glassColor = color
        // To clear glass the colour stays and the tint fades out.
        let toColor = color.map { GlassCoinLayer.rgb($0) } ?? (self.colorTransition?.toColor ?? self.coinLayer.glassColor)
        let toTint: Double = color != nil ? 1.0 : 0.0
        if !animated || !self.isEnabled || !self.isInHierarchy || self.isReduceMotionEnabled {
            self.colorTransition = nil
            self.coinLayer.glassColor = toColor
            self.coinLayer.glassTint = CGFloat(toTint)
            self.coinLayer.flash = 0.0
            if self.phase == .active {
                self.coinLayer.state = self.model.state(at: CACurrentMediaTime())
            } else {
                self.settle()
            }
            return
        }
        if previous == color {
            return
        }
        self.hapticFeedback.impact(.light)
        let time = CACurrentMediaTime()
        self.colorTransition = ColorTransition(
            start: time,
            fromColor: self.coinLayer.glassColor,
            toColor: toColor,
            fromTint: Double(self.coinLayer.glassTint),
            toTint: toTint
        )
        self.activate()
        self.model.pulse(at: time, hold: GlassCoinAvatarNode.colorPulseHold)
        self.tick()
    }

    private func updateColorTransition(at time: Double) {
        guard let transition = self.colorTransition else {
            return
        }
        let t = time - transition.start
        let fade = GlassCoinAvatarNode.easeInOut(max(0.0, min(1.0, t / GlassCoinAvatarNode.colorFadeDuration)))
        self.coinLayer.glassColor = transition.fromColor + (transition.toColor - transition.fromColor) * Float(fade)
        self.coinLayer.glassTint = CGFloat(transition.fromTint + (transition.toTint - transition.fromTint) * fade)
        let u = max(0.0, min(1.0, t / GlassCoinAvatarNode.flashDuration))
        let rise = GlassCoinAvatarNode.flashRise
        let fall = 1.0 - (u - rise) / (1.0 - rise)
        let flash = u < rise ? u / rise : fall * fall
        self.coinLayer.flash = CGFloat(0.9 * flash)
        if t >= GlassCoinAvatarNode.flashDuration {
            self.finishColorTransition()
        }
    }

    private func finishColorTransition() {
        guard let transition = self.colorTransition else {
            return
        }
        self.colorTransition = nil
        self.coinLayer.glassColor = transition.toColor
        self.coinLayer.glassTint = CGFloat(transition.toTint)
        self.coinLayer.flash = 0.0
    }

    /// animator.js `ease.inOut` (cubic).
    private static func easeInOut(_ u: Double) -> Double {
        if u < 0.5 {
            return 4.0 * u * u * u
        }
        let v = -2.0 * u + 2.0
        return 1.0 - v * v * v / 2.0
    }

    private func scheduleChooseBack(after delay: Double) {
        self.pendingTurnGeneration += 1
        let generation = self.pendingTurnGeneration
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + delay, execute: { [weak self] in
            guard let self, self.pendingTurnGeneration == generation else {
                return
            }
            if self.isInHierarchy {
                self.chooseBack()
            } else {
                self.turnsWhenVisible = true
            }
        })
    }

    /// Stops a scheduled turn to the chosen back (a new choice replaces it).
    private func cancelScheduledTurn() {
        self.pendingTurnGeneration += 1
        self.turnsWhenVisible = false
    }

    /// Something else moves the glass before the chosen back's own turn (a touch, VoiceOver, the context menu): the back
    /// still changes only while it faces away — now if the front is in view, as the front passes otherwise.
    private func takeScheduledBack() {
        self.cancelScheduledTurn()
        guard let back = self.scheduledBack else {
            return
        }
        self.scheduledBack = nil
        let face = self.model.face(atYaw: self.model.state(at: CACurrentMediaTime()).yaw)
        if abs(face) % 2 == 0 {
            self.pendingBack = nil
            self.applyBack(back)
        } else {
            self.pendingBack = .some(back)
        }
    }

    /// app.js `chooseBack`: the chosen back comes into view without popping.
    private func chooseBack() {
        guard let back = self.scheduledBack else {
            return
        }
        self.scheduledBack = nil
        let time = CACurrentMediaTime()
        let face = self.model.face(atYaw: self.model.state(at: time).yaw)
        let frontInView = abs(face) % 2 == 0
        if self.pendingBack == nil && back == nil && self.shownBackPhoto == nil {
            // None, and the back already is the photo itself.
            return
        }
        if !self.isEnabled || self.isReduceMotionEnabled {
            // Nothing turns: the back changes at once; a new back photo shows (as the turn would end), none shows the
            // front.
            self.pendingBack = nil
            self.applyBack(back)
            if frontInView == (back != nil) {
                self.model.jump(toFace: face + 1, at: time)
                if self.isEnabled {
                    self.landed?(self.model.content(forFace: face + 1))
                }
            }
            self.settle()
            return
        }
        if self.model.mode == .pressed || self.model.mode == .dragging {
            // The finger has it: no turn of its own; the back still changes only while it faces away.
            if frontInView {
                self.pendingBack = nil
                self.applyBack(back)
            } else {
                self.pendingBack = .some(back)
            }
            return
        }
        self.activate()
        if frontInView {
            // The back faces away: it changes now, then the avatar turns over to show it.
            self.pendingBack = nil
            self.applyBack(back)
            if back == nil {
                self.model.pulse(at: time, hold: GlassCoinAvatarNode.backPulseHold)
            } else {
                self.model.turnBy(1, at: time)
            }
        } else {
            // The back is in view: it turns, and the new back is set as the front passes (`onFaceChange`).
            self.pendingBack = .some(back)
            self.model.turnBy(back == nil ? 1 : 2, at: time)
        }
        self.tick()
    }

    /// What the card's back shows from now on (nil: the photo itself).
    private func applyBack(_ back: UIImage?) {
        self.shownBackPhoto = back
        let key = self.key(.backPhoto)
        self.faceDisposables.set(nil, forKey: key)
        self.requestedFaces.remove(key)
        self.coinLayer.setFaceImage(back, for: .backPhoto)
        self.model.back = back != nil ? .backPhoto : .photo(0)
        if self.phase != .inactive {
            self.ensureFaces()
        }
    }

    private func applyPendingBack() {
        if let back = self.pendingBack {
            self.pendingBack = nil
            self.applyBack(back)
        }
    }

    // MARK: - Accessibility

    /// Turns the avatar over, as a swipe would (VoiceOver action, keyboard). With Reduce Motion the other side shows
    /// without the animation.
    public func turnOver() {
        guard self.isEnabled else {
            return
        }
        self.takeScheduledBack()
        let time = CACurrentMediaTime()
        if self.isReduceMotionEnabled {
            let face = self.model.face(atYaw: self.model.state(at: time).yaw) + 1
            self.model.jump(toFace: face, at: time)
            self.landed?(self.model.content(forFace: face))
            self.settle()
            return
        }
        self.activate()
        self.model.flick(velocity: GlassCoinAvatarNode.turnVelocity, at: time)
        self.tick()
    }

    private func updateAccessibility() {
        guard let hostView = self.hostView else {
            return
        }
        if self.isEnabled {
            hostView.accessibilityCustomActions = [
                UIAccessibilityCustomAction(name: self.accessibilityTurnOverTitle, actionHandler: { [weak self] _ in
                    self?.turnOver()
                    return true
                })
            ]
        } else {
            hostView.accessibilityCustomActions = nil
        }
    }

    // MARK: - Host events

    /// The context menu (long press) or an expansion took over: put the glass down at once, on its front, so the real
    /// avatar is what they animate from and what shows when they are done.
    public func cancelInteraction() {
        self.gestureRecognizer?.cancelPress()
        self.takeScheduledBack()
        let time = CACurrentMediaTime()
        guard self.phase != .inactive || self.model.face(atYaw: self.model.state(at: time).yaw) != 0 else {
            return
        }
        self.model.jump(toFace: 0, at: time)
        // The front is in view: a back waiting for it takes its place.
        self.applyPendingBack()
        self.finishColorTransition()
        self.deactivate()
    }

    /// The profile photo changed: show the front, at rest.
    public func resetToFront() {
        self.gestureRecognizer?.cancelPress()
        self.takeScheduledBack()
        self.model.jump(toFace: 0, at: CACurrentMediaTime())
        self.applyPendingBack()
        self.finishColorTransition()
        self.deactivate()
        self.settle()
    }

    /// Drop the cached faces (the profile photo changed); they load again when needed.
    public func resetFaces() {
        // DisposableDict stays usable only if it is never disposed as a whole: clear key by key.
        for key in self.requestedFaces {
            self.faceDisposables.set(nil, forKey: key)
        }
        self.requestedFaces.removeAll()
        self.coinLayer.removeAllFaceImages()
        if self.phase != .inactive {
            self.ensureFaces()
        }
    }

    // MARK: - Input

    private func coinPoint(_ hostPoint: CGPoint) -> CGPoint {
        // Points relative to the avatar centre, screen axes.
        guard let hostView = self.hostView else {
            return hostPoint
        }
        return CGPoint(x: hostPoint.x - hostView.bounds.midX, y: hostPoint.y - hostView.bounds.midY)
    }

    private func pointerDown(_ hostPoint: CGPoint) {
        guard self.isEnabled, !self.isReduceMotionEnabled else {
            return
        }
        self.takeScheduledBack()
        self.activate()
        self.hapticFeedback.prepareTap()
        // The avatar lifts into glass (coin-controller.js `press`: a soft impact).
        self.hapticFeedback.impact(.soft)
        self.model.pointerDown(self.coinPoint(hostPoint), at: CACurrentMediaTime())
        self.tick()
    }

    private func pointerMove(_ hostPoint: CGPoint) {
        guard self.phase == .active else {
            return
        }
        self.model.pointerMove(self.coinPoint(hostPoint), at: CACurrentMediaTime())
    }

    private func pointerUp(_ hostPoint: CGPoint, cancelled: Bool) {
        guard self.phase == .active else {
            return
        }
        if cancelled {
            self.model.cancel(at: CACurrentMediaTime())
        } else {
            self.model.pointerUp(self.coinPoint(hostPoint), at: CACurrentMediaTime())
        }
    }

    // MARK: - Lifecycle

    /// Whether the avatar at rest needs the glass's frame: its back is in front, or the glass is tinted.
    private var wantsRestingFrame: Bool {
        guard self.isEnabled, self.isInHierarchy else {
            return false
        }
        if self.coinLayer.glassTint > 0.0 && self.coinLayer.look.restGlass > 0.0 {
            return true
        }
        return self.frontContent != .photo(0)
    }

    private func activate() {
        if self.phase == .active {
            return
        }
        self.phase = .active
        if let (image, frame) = self.coverSnapshot?() {
            self.coinLayer.setCoverImage(image, frame: frame)
        }
        self.ensureFaces()
        self.coinLayer.state = self.model.state(at: CACurrentMediaTime())
        self.showCoinIfReady()
        self.lastFrameTime = nil
        if self.displayLink == nil {
            self.displayLink = SharedDisplayLinkDriver.shared.add(framesPerSecond: .max, { [weak self] _ in
                self?.tick()
            })
        }
    }

    /// Shows the glass once the face in front has a texture; while it moves, it also takes the real avatar's place.
    private func showCoinIfReady() {
        guard self.phase != .inactive, let state = self.coinLayer.state else {
            return
        }
        let front: GlassCoinFaceContent = cos(state.yaw) >= 0.0 ? state.sideA : state.sideB
        guard self.coinLayer.hasFaceImage(for: front) else {
            return
        }
        self.coinLayer.isHidden = false
        if self.phase == .active && !self.isAvatarHidden {
            self.isAvatarHidden = true
            self.setAvatarHidden?(true)
        }
    }

    /// Puts the glass to rest from outside a gesture (enabled again, back in the window, a new colour or back): keeps
    /// a frame when the avatar at rest needs one, releases everything otherwise. Nothing happens while it moves.
    private func settle() {
        if self.phase == .active {
            return
        }
        if self.wantsRestingFrame {
            self.rest()
        } else {
            self.deactivate()
        }
    }

    private func rest() {
        self.stopDisplayLink()
        self.phase = .resting
        self.lightUpdated?(nil)
        if self.isAvatarHidden {
            self.isAvatarHidden = false
            self.setAvatarHidden?(false)
        }
        self.ensureFaces()
        self.coinLayer.state = self.model.state(at: CACurrentMediaTime())
        self.showCoinIfReady()
    }

    private func deactivate() {
        self.stopDisplayLink()
        guard self.phase != .inactive else {
            return
        }
        self.phase = .inactive
        self.lightUpdated?(nil)
        if self.isAvatarHidden {
            self.isAvatarHidden = false
            self.setAvatarHidden?(false)
        }
        self.coinLayer.isHidden = true
        self.coinLayer.state = nil
        self.coinLayer.setCoverImage(nil, frame: .zero)
        self.coinLayer.releaseSurfaces()
    }

    private func stopDisplayLink() {
        self.displayLink?.invalidate()
        self.displayLink = nil
        self.lastFrameTime = nil
    }

    private func tick() {
        let time = CACurrentMediaTime()
        if let lastFrameTime = self.lastFrameTime {
            self.coinLayer.frameDuration = max(1.0 / 240.0, min(1.0 / 20.0, time - lastFrameTime))
        }
        self.lastFrameTime = time
        self.updateColorTransition(at: time)
        let state = self.model.state(at: time)
        self.coinLayer.state = state
        self.ensureFaces()
        self.showCoinIfReady()
        self.lightUpdated?(GlassCoinLight(
            yaw: state.yaw,
            pitch: state.pitch,
            yawVelocity: state.yawVelocity,
            glass: state.glass,
            color: self.coinLayer.glassColor,
            tint: Double(self.coinLayer.glassTint)
        ))
        if !self.model.isAnimating && state.glass <= 0.0 && self.colorTransition == nil {
            if self.wantsRestingFrame {
                self.rest()
            } else {
                self.deactivate()
            }
        }
    }

    // MARK: - Faces

    private func key(_ content: GlassCoinFaceContent) -> String {
        switch content {
        case let .photo(index):
            return "photo\(index)"
        case .emblem:
            return "emblem"
        case .backPhoto:
            return "backPhoto"
        }
    }

    /// Loads both sides of the card: the photo and the back (the photo itself, or the back photo), so either is ready
    /// before it swings into view.
    private func ensureFaces() {
        let wanted: [GlassCoinFaceContent] = self.model.back == .photo(0) ? [.photo(0)] : [.photo(0), self.model.back]
        let wantedKeys = Set(wanted.map { self.key($0) })
        // A face that is no longer wanted (the back changed) can be asked for again later.
        for key in self.requestedFaces where !wantedKeys.contains(key) {
            self.faceDisposables.set(nil, forKey: key)
        }
        self.requestedFaces = self.requestedFaces.intersection(wantedKeys)
        self.coinLayer.retainFaceImages(Set(wanted))
        for content in wanted where !self.coinLayer.hasFaceImage(for: content) {
            if content == .backPhoto, let backPhoto = self.shownBackPhoto {
                self.coinLayer.setFaceImage(backPhoto, for: .backPhoto)
                continue
            }
            let key = self.key(content)
            if self.requestedFaces.contains(key) {
                continue
            }
            guard let signal = self.faceImage?(content) else {
                continue
            }
            self.requestedFaces.insert(key)
            self.faceDisposables.set((signal |> deliverOnMainQueue).start(next: { [weak self] image in
                guard let self else {
                    return
                }
                guard let image else {
                    // Not available (yet): allow a later request.
                    self.requestedFaces.remove(key)
                    return
                }
                self.coinLayer.setFaceImage(image, for: content)
                self.showCoinIfReady()
            }), forKey: key)
        }
    }
}
