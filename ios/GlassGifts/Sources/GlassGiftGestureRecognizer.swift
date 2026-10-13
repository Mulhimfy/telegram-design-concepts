import Foundation
import UIKit
import UIKit.UIGestureRecognizerSubclass
import Display

/// The glass's touch on a gift tile (prototype/src/profile/profile-page.js `down` / `move` / `up`), without taking
/// anything away from what a tile already does:
///
/// · **touch down** leans the glass toward the finger and runs a burst of light across it at once, but the recognizer
///   stays `.possible`: the tile's button still gets the touch, and a **tap still opens the gift's info sheet**
///   (the recognizer fails when the finger lifts). The finger moving within the tile keeps the lean on it.
/// · a move past 8 pt before the hold is a scroll or a tab swipe: the recognizer fails and the glass eases home; the
///   pane's own pan has the touch as before (if a pan starts sooner, it fails the recognizer itself).
/// · after the **hold** — the context gesture's own threshold (`beginDelay`, 0.12 s) within 10 pt — a slide belongs to
///   the tiles: the pans of the views around (the pane's scroll, the tab paging, the back swipe) are failed, as the
///   context gesture does when its menu opens (`cancelParentGestures`). Lifting the finger without sliding is still a
///   tap; holding still is still the context menu (its press shrink composes with the glass).
/// · a slide of 10 pt after the hold **inspects**: the recognizer begins (the button's tap is cancelled, the context
///   gesture too), and every tile the finger crosses leans after it with a burst and a selection tick.
/// · the context menu opening fails the recognizer (`cancelParentGestures`); every way out releases the glass, which
///   eases home.
/// A touch that stops a scrolling grid only catches it (no lean, no burst).
final class GlassGiftGestureRecognizer: UIGestureRecognizer {
    private enum Phase {
        case idle
        /// Down, before the hold: the lean follows the finger on its tile.
        case pending
        /// Held still past the context gesture's threshold: a slide now inspects.
        case armed
        /// Sliding across the tiles.
        case inspecting
    }

    /// prototype: a move past 8 pt before the hold scrolls.
    static let scrollSlop: CGFloat = 8.0
    /// prototype: the hold counts within 10 pt; here also the slide that starts inspecting.
    static let holdSlop: CGFloat = 10.0

    weak var tile: GlassGiftTile?

    private var phase: Phase = .idle
    private weak var trackedTouch: UITouch?
    private var startPoint = CGPoint()
    private var holdTimer: Timer?
    /// The tile under the finger while inspecting (nil between tiles).
    private weak var heldTile: GlassGiftTile?
    private let hapticFeedback = HapticFeedback()

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        // Never hold the tile's own touches back; cancel them only once inspecting begins.
        self.cancelsTouchesInView = true
        self.delaysTouchesBegan = false
        self.delaysTouchesEnded = false
    }

    deinit {
        self.holdTimer?.invalidate()
    }

    override var state: UIGestureRecognizer.State {
        didSet {
            switch self.state {
            case .ended, .cancelled, .failed:
                // However the touch ends — lifted, a scroll or the context menu took it — the glass eases home.
                self.finish()
            default:
                break
            }
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard self.phase == .idle else {
            // A second finger: the first one keeps the glass.
            return
        }
        guard let touch = touches.first, let view = self.view, let tile = self.tile else {
            self.state = .failed
            return
        }
        if GlassGiftGestureRecognizer.isInScrollingView(view) {
            // prototype `caught`: this touch stops the scroll.
            self.state = .failed
            return
        }
        self.trackedTouch = touch
        self.startPoint = touch.location(in: view)
        self.phase = .pending
        tile.touchDown(at: self.startPoint)

        let delay = (view as? ContextControllerSourceView)?.beginDelay ?? 0.12
        let timer = Timer(timeInterval: delay, repeats: false, block: { [weak self] _ in
            self?.holdTimerFired()
        })
        self.holdTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let touch = self.trackedTouch, touches.contains(touch), let view = self.view else {
            return
        }
        let point = touch.location(in: view)
        let distance = hypot(point.x - self.startPoint.x, point.y - self.startPoint.y)
        switch self.phase {
        case .idle:
            break
        case .pending:
            if distance > GlassGiftGestureRecognizer.scrollSlop {
                self.state = .failed
            } else {
                self.tile?.aim(at: point)
            }
        case .armed:
            if distance >= GlassGiftGestureRecognizer.holdSlop {
                self.beginInspecting(touch: touch)
            } else {
                self.tile?.aim(at: point)
            }
        case .inspecting:
            self.state = .changed
            if self.inspect(touch: touch) {
                self.hapticFeedback.tap()
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        guard let touch = self.trackedTouch, touches.contains(touch) else {
            return
        }
        if self.phase == .inspecting {
            self.state = .ended
        } else {
            // A tap (or a press released before the menu): the button below opens the info sheet.
            self.state = .failed
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        guard let touch = self.trackedTouch, touches.contains(touch) else {
            return
        }
        self.state = self.phase == .inspecting ? .cancelled : .failed
    }

    override func reset() {
        self.finish()
        super.reset()
    }

    private func holdTimerFired() {
        self.holdTimer = nil
        guard self.phase == .pending, self.state == .possible, let view = self.view else {
            return
        }
        if GlassGiftGestureRecognizer.hasActivePan(above: view) {
            // A scroll or a swipe already has the touch.
            self.state = .failed
            return
        }
        self.phase = .armed
        self.hapticFeedback.prepareTap()
        // From here on a slide is the tiles': nothing around scrolls, pages or swipes back with this touch.
        GlassGiftGestureRecognizer.failPans(above: view)
    }

    private func beginInspecting(touch: UITouch) {
        self.phase = .inspecting
        self.heldTile = self.tile
        self.state = .began
        // No context menu: the finger slides on.
        (self.view as? ContextControllerSourceView)?.cancelGesture()
        // One tick for the start, whichever tile the finger is over by now.
        self.inspect(touch: touch)
        self.hapticFeedback.tap()
    }

    /// The tile under the finger leans after it; crossing onto another one bursts it. True when the tile changed to a
    /// new one.
    @discardableResult
    private func inspect(touch: UITouch) -> Bool {
        guard let view = self.view, let container = view.superview else {
            return false
        }
        let found = GlassGiftGestureRecognizer.tile(at: touch.location(in: container), in: container)
        var enteredTile = false
        if found?.tile !== self.heldTile {
            self.heldTile?.release()
            self.heldTile = found?.tile
            if let found {
                found.tile.burst()
                enteredTile = true
            }
        }
        if let found {
            found.tile.aim(at: touch.location(in: found.view))
        }
        return enteredTile
    }

    private func finish() {
        self.holdTimer?.invalidate()
        self.holdTimer = nil
        let phase = self.phase
        self.phase = .idle
        self.trackedTouch = nil
        switch phase {
        case .idle:
            break
        case .pending, .armed:
            self.tile?.release()
        case .inspecting:
            // Every tile the finger left was released as it left; the one under it now eases home too.
            self.heldTile?.release()
        }
        self.heldTile = nil
    }

    /// The glass tile whose view contains `point` (in `container`, the grid), if any.
    static func tile(at point: CGPoint, in container: UIView) -> (tile: GlassGiftTile, view: UIView)? {
        for view in container.subviews.reversed() where !view.isHidden && view.alpha > 0.01 && view.frame.contains(point) {
            guard let recognizers = view.gestureRecognizers else {
                continue
            }
            for recognizer in recognizers {
                if let recognizer = recognizer as? GlassGiftGestureRecognizer, let tile = recognizer.tile {
                    return (tile, view)
                }
            }
        }
        return nil
    }

    private static func isInScrollingView(_ view: UIView) -> Bool {
        var current = view.superview
        while let view = current {
            if let scrollView = view as? UIScrollView, scrollView.isDecelerating {
                return true
            }
            current = view.superview
        }
        return false
    }

    private static func hasActivePan(above view: UIView) -> Bool {
        var current = view.superview
        while let view = current {
            for recognizer in view.gestureRecognizers ?? [] where recognizer is UIPanGestureRecognizer {
                if recognizer.state == .began || recognizer.state == .changed {
                    return true
                }
            }
            current = view.superview
        }
        return false
    }

    private static func failPans(above view: UIView) {
        var current = view.superview
        while let view = current {
            for recognizer in view.gestureRecognizers ?? [] where recognizer is UIPanGestureRecognizer && recognizer.isEnabled && recognizer.state == .possible {
                recognizer.state = .failed
            }
            current = view.superview
        }
    }
}
