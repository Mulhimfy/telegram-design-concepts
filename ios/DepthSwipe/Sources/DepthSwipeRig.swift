import Foundation

// Depth Swipe — the Swift twin of prototype/src/chats/depth.js (DepthLook, DepthRig.update).
//
// Pull a chat and it comes off the surface in 3D:
//   · the name becomes extruded 3D type whose letters roll back on their own axis, like the reels
//     of Telegram's rolling counters, in a wave that starts on the side the row moves toward; their
//     widths never change, so the name stays in one piece;
//   · each line of the message leans as one rigid plate, its leading end lifting, a beat later;
//   · the photo becomes a thick disc that tilts with the pull, the picture sitting deeper than its
//     rim (parallax) and a glint crossing it;
//   · swiped to the left, nothing is cut off by the screen edge: the edge is the rounded rim of the
//     surface, and the disc, then the name letter by letter, roll over it into the depth and back
//     out when the row closes. The message text fades into the rim;
//   · the full-swipe moment (the haptic) spins the letters once, reel by reel, and flips the disc
//     like a coin.
// When the row settles everything rolls back flat and the flat text takes over again.
//
// This file is the maths only: plain values per frame (DepthSwipeFrame), no UIKit. CI replays the
// web rig's golden frames through it (ios/Standalone/DepthSwipeCore). DepthSwipeLayers draws them.

/// `DepthLook`: every constant of the look, as in depth.js.
public enum DepthSwipeLook {
    public struct Title {
        /// Degrees the letters roll back at full speed, and while the finger holds the row.
        public let roll: Double
        public let hold: Double
        /// pt toward the viewer while a letter is rolled (it lifts off the surface).
        public let lift: Double
        /// The extrusion: `layers` copies spread over `depth` pt behind the face.
        public let depth: Double
        public let layers: Int
        /// Seconds between neighbouring letters in the wave.
        public let stagger: Double
        /// Darkening of a face rolled edge-on (opacity of its copy in shadow).
        public let shade: Double
        public let spring: DepthSwipeSpring
    }

    public struct Lines {
        /// Degrees a line leans at full speed, and while the finger holds the row.
        public let lean: Double
        public let hold: Double
        public let lift: Double
        /// Seconds the first line follows the motion late, and between lines.
        public let delay: Double
        public let stagger: Double
        public let spring: DepthSwipeSpring
        /// The message box ends here, from the row's right edge (chat-list.js: rightInset 16 + 26):
        /// a plate turns about this end on a left swipe.
        public let boxRightInset: Double
    }

    public struct Avatar {
        public let lean: Double
        public let hold: Double
        public let lift: Double
        /// The disc's thickness: `layers` rim slices over `depth` pt.
        public let depth: Double
        public let layers: Int
        public let delay: Double
        public let spring: DepthSwipeSpring
        /// pt the picture slides against the tilt (it sits deeper than the rim).
        public let parallax: Double
    }

    /// Left swipes: the rim at the screen's left edge. A piece whose flat centre has gone d pt past
    /// the hinge line is d / radius rad round it (on screen at hinge − radius·sin, radius·(1 − cos)
    /// deep); it fades out between fade.start and fade.end degrees and is gone behind the rim after.
    public struct Edge {
        public let hinge: Double
        public let radius: Double
        public let shade: Double
        public let fadeStart: Double
        public let fadeEnd: Double
    }

    /// The full-swipe moment.
    public struct Spin {
        public let duration: Double
        public let stagger: Double
    }

    /// pt/s: the motion lean is max · tanh(|v| / v0).
    public static let v0: Double = 620.0
    /// pt of pull for most of the "tension" lean while the finger holds the row.
    public static let holdDistance: Double = 60.0
    /// The perspective of the name, the message box and the disc (CSS `perspective: 330px`).
    public static let perspective: Double = 330.0
    public static let title = Title(roll: 40.0, hold: 18.0, lift: 4.0, depth: 6.0, layers: 7, stagger: 0.022, shade: 0.4, spring: DepthSwipeSpring(response: 0.17, dampingFraction: 0.5))
    public static let lines = Lines(lean: 18.0, hold: 8.0, lift: 0.0, delay: 0.03, stagger: 0.035, spring: DepthSwipeSpring(response: 0.22, dampingFraction: 0.58), boxRightInset: 42.0)
    public static let avatar = Avatar(lean: 48.0, hold: 22.0, lift: 7.0, depth: 6.0, layers: 6, delay: 0.008, spring: DepthSwipeSpring(response: 0.22, dampingFraction: 0.58), parallax: 7.0)
    public static let edge = Edge(hinge: 36.0, radius: 34.0, shade: 0.5, fadeStart: 62.0, fadeEnd: 90.0)
    public static let spin = Spin(duration: 0.56, stagger: 0.03)

    /// Angles are springs in degrees: at rest within 0.02° (SpringValue's default is for points).
    static let angleEpsilon: Double = 0.02
}

/// Where the row's pieces sit, flat, with the row at rest — in row points (x = 0 is the row's left
/// edge, which is the screen's left edge in the chat list). buildTitle / buildLines / buildAvatar
/// measure the same things in depth.js.
public struct DepthSwipeGeometry: Equatable {
    /// The name's left edge in the row (`titleX`).
    public var titleX: Double
    /// Half the name's width: the perspective origin of its letters (`titleOrigin`).
    public var titleOrigin: Double
    /// Each letter's centre within the name (`glyphs[].cx`).
    public var glyphCenters: [Double]
    /// The badges after the name (verified, emoji status, muted…), centres in the row (`icons[].cx`).
    public var iconCenters: [Double]
    /// The message box's left edge in the row (`box.offsetLeft`); nil without a message.
    public var textLeft: Double?
    /// Lines of the message, the author's line first in groups.
    public var lineCount: Int
    /// The photo's centre in the row and half its width (`avatar.cx`, `avatar.half`); nil without one.
    public var avatarCenter: Double?
    public var avatarHalf: Double

    public init(titleX: Double, titleOrigin: Double, glyphCenters: [Double], iconCenters: [Double], textLeft: Double?, lineCount: Int, avatarCenter: Double?, avatarHalf: Double) {
        self.titleX = titleX
        self.titleOrigin = titleOrigin
        self.glyphCenters = glyphCenters
        self.iconCenters = iconCenters
        self.textLeft = textLeft
        self.lineCount = lineCount
        self.avatarCenter = avatarCenter
        self.avatarHalf = avatarHalf
    }
}

/// One frame of the rig: every transform and opacity depth.js writes, as numbers.
public struct DepthSwipeFrame {
    /// Round the rim (left swipes): `translate3d(tx, 0, dz) rotateY(−angle) scale3d(1, 1, depthScale)`.
    public struct Rim: Equatable {
        public var tx: Double
        public var dz: Double
        /// Degrees round the rim (0 flat … 90 edge-on … behind it).
        public var angle: Double
        /// The letter's depth flattens as it turns, so its side never outgrows it.
        public var depthScale: Double
    }

    /// A letter: `[rim] translateZ(lift) rotateX(angle)` about (50 %, 55 %) of its box.
    public struct Glyph: Equatable {
        /// The roll spring (degrees, before the spin and the rim).
        public var roll: Double
        public var angle: Double
        public var lift: Double
        public var rim: Rim?
        /// Opacity of the face's copy in shadow.
        public var shade: Double
        public var faceOpacity: Double
        /// Opacity of the extrusion copies.
        public var layerOpacity: Double
        public var isHidden: Bool
    }

    /// A badge after the name round the rim: `perspective(P) translate3d(tx, 0, dz) rotateY(−angle)`.
    public struct Icon: Equatable {
        public var tx: Double
        public var dz: Double
        public var angle: Double
        public var opacity: Double
    }

    /// A message line: `rotateY(lean)` about its leading end's opposite end; flat below 0.05°.
    public struct Line: Equatable {
        public var lean: Double
        public var isFlat: Bool
    }

    /// The message fades into the rim: transparent at `start`, opaque from `end` (box points).
    public struct TextMask: Equatable {
        public var start: Double
        public var end: Double
    }

    /// The disc: `translate3d(dx, 0, z) rotateY(angle)`, seen from straight in front of where it is.
    public struct Disc: Equatable {
        /// The lean spring (degrees).
        public var lean: Double
        public var angle: Double
        public var dx: Double
        public var z: Double
        /// The perspective origin's x in the photo's box while it is round the rim (else its centre).
        public var perspectiveOriginX: Double?
        /// pt the picture slides (`translateX(parallax) scale(1.14)`).
        public var parallax: Double
        /// The glint's shift in % of its own width, and its opacity.
        public var glint: Double
        public var glintOpacity: Double
        /// Black over the face as it turns away from the light on the rim.
        public var dim: Double
        /// The photo's box fades on the rim (not the disc: opacity there would flatten its rim).
        public var opacity: Double
        public var isHidden: Bool
    }

    /// −1: the row moves left (the wave starts at the name's left end), 1: right.
    public var direction: Int = -1
    public var glyphs: [Glyph] = []
    public var icons: [Icon?] = []
    public var textMask: TextMask?
    public var lines: [Line] = []
    public var disc: Disc?
    /// Anything round the rim: the rig stays while the row rests like that.
    public var isRolled: Bool = false
    /// Anything still moving (springs or the spin).
    public var isMoving: Bool = false
}

private let degree = Double.pi / 180.0
private let halfTurn = Double.pi / 2.0

private func clamp(_ x: Double, _ a: Double = 0.0, _ b: Double = 1.0) -> Double {
    return max(a, min(b, x))
}

private func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = clamp((x - a) / (b - a))
    return t * t * (3.0 - 2.0 * t)
}

private func ease(_ u: Double) -> Double {
    return u < 0.5 ? 4.0 * u * u * u : 1.0 - pow(-2.0 * u + 2.0, 3.0) / 2.0
}

/// `DepthRig` without the DOM: begin / end / spin / update(now, x, v, pull).
public final class DepthSwipeRig {
    public private(set) var isActive: Bool = false
    public private(set) var geometry: DepthSwipeGeometry
    /// The last frame update(at:…) computed.
    public private(set) var frame = DepthSwipeFrame()

    private struct Sample {
        let t: Double
        let v: Double
        let x: Double
    }

    private var samples: [Sample] = []
    private var spinStart: Double?
    private var rolls: [DepthSwipeSpringValue] = []
    private var leans: [DepthSwipeSpringValue] = []
    private var discLean: DepthSwipeSpringValue?

    public init(geometry: DepthSwipeGeometry) {
        self.geometry = geometry
    }

    public var isRolled: Bool {
        return self.frame.isRolled
    }

    private static func angleSpring(_ spring: DepthSwipeSpring) -> DepthSwipeSpringValue {
        let value = DepthSwipeSpringValue(0.0, spring: spring)
        value.epsilon = DepthSwipeLook.angleEpsilon
        return value
    }

    /// Starts flat; while it runs a new move carries on from where it is.
    public func begin(at now: Double) {
        if self.isActive {
            return
        }
        self.isActive = true
        self.samples = []
        self.spinStart = nil
        self.rolls = self.geometry.glyphCenters.map { _ in DepthSwipeRig.angleSpring(DepthSwipeLook.title.spring) }
        self.leans = (0 ..< self.geometry.lineCount).map { _ in DepthSwipeRig.angleSpring(DepthSwipeLook.lines.spring) }
        self.discLean = self.geometry.avatarCenter != nil ? DepthSwipeRig.angleSpring(DepthSwipeLook.avatar.spring) : nil
        self.frame = DepthSwipeFrame()
    }

    /// Back to flat (call once update(at:…) has settled).
    public func end() {
        if !self.isActive {
            return
        }
        self.isActive = false
        self.samples = []
        self.spinStart = nil
        self.rolls = []
        self.leans = []
        self.discLean = nil
        self.frame = DepthSwipeFrame()
    }

    /// The row's content was laid out again while the rig runs: new pieces, same motion. Springs
    /// carry over by index (a letter added at the end takes its neighbour's state).
    public func updateGeometry(_ geometry: DepthSwipeGeometry) {
        if self.isActive {
            func carried(_ old: [DepthSwipeSpringValue], count: Int, spring: DepthSwipeSpring) -> [DepthSwipeSpringValue] {
                return (0 ..< count).map { i in
                    if i < old.count {
                        return old[i]
                    }
                    let value = DepthSwipeRig.angleSpring(spring)
                    if let last = old.last {
                        value.set(last.value, at: 0.0)
                    }
                    return value
                }
            }
            self.rolls = carried(self.rolls, count: geometry.glyphCenters.count, spring: DepthSwipeLook.title.spring)
            self.leans = carried(self.leans, count: geometry.lineCount, spring: DepthSwipeLook.lines.spring)
            if geometry.avatarCenter == nil {
                self.discLean = nil
            } else if self.discLean == nil {
                self.discLean = DepthSwipeRig.angleSpring(DepthSwipeLook.avatar.spring)
            }
        }
        self.geometry = geometry
    }

    // MARK: - The full-swipe moment

    /// `direction`: +1 / −1, the way the row is going.
    public func spin(at now: Double, direction: Int) {
        if !self.isActive {
            return
        }
        self.spinStart = now
    }

    func spinAngle(at now: Double, order: Double) -> Double {
        guard let spinStart = self.spinStart else {
            return 0.0
        }
        let spin = DepthSwipeLook.spin
        return 360.0 * ease(clamp((now - spinStart - order * spin.stagger) / spin.duration))
    }

    public func isSpinning(at now: Double) -> Bool {
        guard let spinStart = self.spinStart else {
            return false
        }
        return now - spinStart < DepthSwipeLook.spin.duration + DepthSwipeLook.spin.stagger * Double(self.rolls.count + 4)
    }

    // MARK: - Per frame

    /// The row's velocity at time t (linear between samples).
    private func sampledVelocity(at t: Double) -> Double {
        let s = self.samples
        guard let last = s.last else {
            return 0.0
        }
        if t >= last.t {
            return last.v
        }
        var i = s.count - 1
        while i > 0 {
            if s[i - 1].t <= t {
                let a = s[i - 1]
                let b = s[i]
                let u = (t - a.t) / max(1e-6, b.t - a.t)
                return a.v + (b.v - a.v) * u
            }
            i -= 1
        }
        return s[0].v
    }

    private struct RimPlace {
        let th: Double
        let deg: Double
        let r: Double
        let dx: Double
        let dz: Double
        let lit: Double
        let fade: Double
    }

    /// The rim (left swipes): how far round it a piece whose flat centre is at X (screen pt) is,
    /// where it shows, how lit it is and how much of it is left.
    private static func rim(_ x: Double) -> RimPlace? {
        let edge = DepthSwipeLook.edge
        let th = max(0.0, (edge.hinge - x) / edge.radius)
        if th <= 0.0 {
            return nil
        }
        let c = min(th, halfTurn)
        let deg = th / degree
        return RimPlace(
            th: th,
            deg: deg,
            r: min(1.0, th / halfTurn),
            dx: edge.hinge - edge.radius * sin(c) - x,
            dz: -edge.radius * (1.0 - cos(c)),
            lit: 1.0 - cos(c),
            fade: 1.0 - smooth(edge.fadeStart, edge.fadeEnd, deg)
        )
    }

    /// x: the row's offset (pt, + = right), v: its velocity (pt/s), pull: how far the finger has
    /// pulled it since it touched (pt, 0 once let go). Returns true while anything moves.
    @discardableResult
    public func update(at now: Double, offset x: Double, velocity v: Double, pull: Double = 0.0) -> Bool {
        if !self.isActive {
            return false
        }
        self.samples.append(Sample(t: now, v: v, x: x))
        while self.samples.count > 2 && self.samples[0].t < now - 0.6 {
            self.samples.removeFirst()
        }
        let look = DepthSwipeLook.self
        let edge = look.edge
        // The side the row moves toward.
        let dir: Int
        if x < -0.5 {
            dir = -1
        } else if x > 0.5 {
            dir = 1
        } else if v > 0.0 {
            dir = 1
        } else {
            dir = -1
        }
        let tension = abs(tanh(pull / look.holdDistance))
        let motion: (Double) -> Double = { t in
            return tanh(abs(self.sampledVelocity(at: t)) / look.v0)
        }
        var moving = false
        // Advance to now, then retarget (velocity carried over); a target that stays put lets the
        // spring come to rest.
        func step(_ value: DepthSwipeSpringValue, _ target: Double) -> Double {
            value.update(at: now)
            if abs(target - value.target) > 0.01 {
                value.animate(to: target, at: now)
            }
            if !value.isSettled {
                moving = true
            }
            return value.value
        }
        var rolled = false
        func rimAt(_ position: Double) -> RimPlace? {
            let place = DepthSwipeRig.rim(position)
            if place != nil {
                rolled = true
            }
            return place
        }

        var frame = DepthSwipeFrame()
        frame.direction = dir

        // The name: letters roll back (top away, into the surface), the wave from the leading side;
        // at the rim each one turns round it.
        let title = look.title
        let n = self.rolls.count
        let perspective = look.perspective
        let origin = self.geometry.titleOrigin
        frame.glyphs.reserveCapacity(n)
        for i in 0 ..< n {
            let cx = self.geometry.glyphCenters[i]
            let order = dir < 0 ? i : n - 1 - i
            let t0 = now - Double(order) * title.stagger
            let roll = step(self.rolls[i], title.roll * motion(t0) + title.hold * tension)
            let place = rimAt(self.geometry.titleX + cx + x)
            let k = place.map { 1.0 - $0.r } ?? 1.0
            let a = (roll + self.spinAngle(at: now, order: Double(order))) * k
            let lift = title.lift * min(1.0, abs(sin(a * degree)) * 1.4) * k
            var rim: DepthSwipeFrame.Rim?
            if let place {
                // Placed so that, seen through the name's perspective, it lands on the rim. Its
                // depth flattens as it turns, so the side never outgrows the letter.
                let tx = origin + (cx + place.dx - origin) * (perspective - place.dz) / perspective - cx
                let kz = 1.0 - 0.85 * place.r
                rim = DepthSwipeFrame.Rim(tx: tx, dz: place.dz, angle: place.deg, depthScale: kz)
            }
            let shade = max(title.shade * (1.0 - abs(cos(a * degree))), place.map { edge.shade * $0.lit } ?? 0.0)
            let fade = place?.fade ?? 1.0
            // Near edge-on it fades (layer by layer, so the letter keeps its depth) and then it's
            // behind; its sides fade a little as it turns, so the face stays the letter.
            frame.glyphs.append(DepthSwipeFrame.Glyph(
                roll: roll,
                angle: a,
                lift: lift,
                rim: rim,
                shade: shade * fade,
                faceOpacity: fade >= 0.999 ? 1.0 : fade,
                layerOpacity: place.map { fade * (1.0 - 0.6 * $0.r) } ?? 1.0,
                isHidden: fade <= 0.001
            ))
        }

        // The badges after the name (verified, muted): flat pieces on the same rim.
        frame.icons = self.geometry.iconCenters.map { cx -> DepthSwipeFrame.Icon? in
            guard let place = rimAt(cx + x) else {
                return nil
            }
            let tx = place.dx * (perspective - place.dz) / perspective
            return DepthSwipeFrame.Icon(tx: tx, dz: place.dz, angle: place.deg, opacity: place.fade >= 0.999 ? 1.0 : place.fade)
        }

        // The message: its text fades into the rim (a mask over the box, in its own coordinates).
        if let textLeft = self.geometry.textLeft {
            let left = textLeft + x
            if left < edge.hinge {
                frame.textMask = DepthSwipeFrame.TextMask(start: edge.hinge - edge.radius * 0.92 - left, end: edge.hinge - left)
                rolled = true
            }
        }

        // The message lines: rigid plates, the leading end lifting, line 2 after line 1. Seen from
        // their left end on a left swipe (they lift there without spreading over the photo).
        let lines = look.lines
        frame.lines = self.leans.enumerated().map { i, value in
            let lean = step(value, (lines.lean * motion(now - lines.delay - Double(i) * lines.stagger) + lines.hold * tension) * Double(-dir))
            return DepthSwipeFrame.Line(lean: lean, isFlat: abs(lean) < 0.05)
        }

        // The disc: heavier (lags a little more). On a left swipe it rolls over the rim: its lean
        // hands over to the turn round the rim, following the position directly.
        if let discLean = self.discLean, let center = self.geometry.avatarCenter {
            let avatar = look.avatar
            let lean = step(discLean, (avatar.lean * motion(now - avatar.delay) + avatar.hold * tension) * Double(dir))
            let place = rimAt(center + x)
            let k = place.map { 1.0 - $0.r } ?? 1.0
            let a = lean * k - (place?.deg ?? 0.0) + self.spinAngle(at: now, order: -3.0) * Double(-dir)
            let s = sin(a * degree)
            let lift = avatar.lift * min(1.0, abs(s) * 1.3) * k
            let dx = place?.dx ?? 0.0
            frame.disc = DepthSwipeFrame.Disc(
                lean: lean,
                angle: a,
                dx: dx,
                z: (place?.dz ?? 0.0) + lift,
                perspectiveOriginX: place != nil ? self.geometry.avatarHalf + dx : nil,
                parallax: -avatar.parallax * s,
                glint: s * 34.0,
                glintOpacity: min(1.0, abs(s) * 1.6) * (place?.fade ?? 1.0),
                dim: place.map { edge.shade * $0.lit } ?? 0.0,
                opacity: place.map { $0.fade < 0.999 ? $0.fade : 1.0 } ?? 1.0,
                isHidden: place.map { $0.fade <= 0.001 } ?? false
            )
        }

        // While anything is round the rim the rig stays (the row may rest open like that).
        frame.isRolled = rolled
        frame.isMoving = moving || self.isSpinning(at: now)
        self.frame = frame
        return frame.isMoving
    }
}
