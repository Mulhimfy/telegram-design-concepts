import Foundation
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Recognizes a drag of the glass avatar without taking anything away from the gestures that already live on it:
///
/// · touch down calls `pressed` immediately (the glass lifts) but stays `.possible`,
/// · a move past `slop` in any direction begins the drag: the glass tilts any way. In Telegram the header sits above
///   the list and `PeerInfoHeaderNode.hitTest` gives touches on the avatar to the avatar, so a drag that starts on it
///   never scrolled the list or pulled the header down anyway (prototype/src/ui/input.js),
/// · touch up without a drag fails, so the existing `UITapGestureRecognizer` still expands the avatar,
/// · the context menu's long press cancels it through `cancelPress()`.
///
/// `released` is always called exactly once per `pressed`, whatever happens to the touch.
final class GlassCoinGestureRecognizer: UIGestureRecognizer {
    var pressed: ((CGPoint) -> Void)?
    var moved: ((CGPoint) -> Void)?
    var released: ((CGPoint, _ cancelled: Bool) -> Void)?

    var slop: CGFloat = 6.0

    private var startPoint: CGPoint?
    private var lastPoint = CGPoint()
    private var isPressed = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard self.startPoint == nil, touches.count == 1, let touch = touches.first else {
            if self.isPressed {
                self.finishPress(cancelled: true)
            }
            self.state = (self.state == .began || self.state == .changed) ? .cancelled : .failed
            return
        }
        let point = touch.location(in: self.view)
        self.startPoint = point
        self.lastPoint = point
        self.isPressed = true
        self.pressed?(point)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let startPoint = self.startPoint, let touch = touches.first else {
            return
        }
        let point = touch.location(in: self.view)
        self.lastPoint = point
        if self.state == .possible {
            let dx = point.x - startPoint.x
            let dy = point.y - startPoint.y
            if dx * dx + dy * dy > self.slop * self.slop {
                self.state = .began
            }
            self.moved?(point)
        } else if self.state == .began || self.state == .changed {
            self.state = .changed
            self.moved?(point)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        let point = touches.first?.location(in: self.view) ?? self.lastPoint
        self.lastPoint = point
        if self.state == .began || self.state == .changed {
            self.finishPress(cancelled: false)
            self.state = .ended
        } else {
            // A tap: the glass settles, the tap recognizer expands the avatar.
            self.finishPress(cancelled: false)
            self.state = .failed
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        self.finishPress(cancelled: true)
        self.state = (self.state == .began || self.state == .changed) ? .cancelled : .failed
    }

    /// Another gesture took over (e.g. the context menu fired).
    func cancelPress() {
        if self.isPressed {
            self.finishPress(cancelled: true)
            if self.state == .began || self.state == .changed {
                self.state = .cancelled
            } else {
                self.state = .failed
            }
        }
    }

    override func reset() {
        // Recognizers can be reset without touchesEnded when another one wins; never leave the
        // coin lifted.
        if self.isPressed {
            self.finishPress(cancelled: true)
        }
        self.startPoint = nil
        super.reset()
    }

    private func finishPress(cancelled: Bool) {
        guard self.isPressed else {
            return
        }
        self.isPressed = false
        self.released?(self.lastPoint, cancelled)
    }
}
