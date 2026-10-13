import Foundation

// How the chat row drives the Depth Swipe rig — the Swift twin of the driving code in
// prototype/src/chats/chat-list.js (ChatRow.beginSwipe / setOffset / update / depthStart):
//   · the rig starts when a swipe begins and whenever the row moves on its own by more than half a
//     point (the release spring, a tap closing it, an action closing or filling it);
//   · every frame it gets the presented offset, its velocity — Δx / dt smoothed as
//     vel = vel·0.45 + v·0.55 — and the pull since the finger caught the row;
//   · it ends once nothing moves, the row is still (no finger, no animation, under 1 pt/s) and
//     nothing is round the rim; resting open with pieces round the rim, it stays.
// Pure Swift; CI checks it against the same golden frames as the rig.

public struct DepthSwipeTracker {
    /// The smoothed velocity of the presented offset (pt/s).
    public private(set) var velocity: Double = 0.0
    private var previousOffset: Double = 0.0
    private var lastTime: Double?

    public init() {
    }

    /// Restarts the smoothing: the row was at `offset` one frame before `time`.
    public mutating func reset(offset: Double, at time: Double, frameDuration: Double) {
        self.velocity = 0.0
        self.previousOffset = offset
        self.lastTime = time - frameDuration
    }

    /// ChatRow.update: one frame at `time` with the row presented at `offset`; returns the
    /// smoothed velocity. dt is clamped to 50 ms, as the prototype's frame loop does.
    @discardableResult
    public mutating func frame(at time: Double, offset: Double) -> Double {
        let dt = max(0.0, min(0.05, time - (self.lastTime ?? time)))
        self.lastTime = time
        let v = dt > 0.0 ? (offset - self.previousOffset) / dt : 0.0
        self.velocity = self.velocity * 0.45 + v * 0.55
        self.previousOffset = offset
        return self.velocity
    }

    /// ChatRow.setOffset: a row that moves on its own (animated) by more than half a point goes 3D
    /// the same way as under the finger.
    public static func animatedMoveStarts(target: Double, presented: Double) -> Bool {
        return abs(target - presented) > 0.5
    }

    /// The pull since the finger caught the row (`x − initial` while tracking, 0 once let go).
    public static func pull(offset: Double, gestureInitialOffset: Double?) -> Double {
        guard let gestureInitialOffset else {
            return 0.0
        }
        return offset - gestureInitialOffset
    }

    /// The row is still: no finger, no animation, slower than 1 pt/s.
    public static func isStill(isTracking: Bool, isAnimating: Bool, velocity: Double) -> Bool {
        return !isTracking && !isAnimating && abs(velocity) < 1.0
    }

    /// Settled flat: back to the flat row.
    public static func shouldEnd(isMoving: Bool, isStill: Bool, isRolled: Bool) -> Bool {
        return !isMoving && isStill && !isRolled
    }
}
