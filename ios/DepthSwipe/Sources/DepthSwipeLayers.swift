import Foundation
import UIKit
import QuartzCore
import Display

// Depth Swipe on Core Animation — the drawing half of prototype/src/chats/depth.js: buildTitle,
// buildLines and buildAvatar as layers, and every style update() writes as a layer property.
//
// CSS → Core Animation:
//   · `perspective: 330px` on a box → its layer's sublayerTransform (m34 = −1/330), about the box's
//     perspective origin (CA applies it about the anchor point, the centre);
//   · `transform-style: preserve-3d` → a CATransformLayer: the extrusion copies and the disc's
//     slices keep their depth;
//   · a CSS transform list applies its last function first; CATransform3DConcat(a, b) applies a
//     first — so every list is built from its last function to its first;
//   · `transform-origin` → anchorPoint, `backface-visibility: hidden` → isDoubleSided = false,
//     `overflow: hidden; border-radius: 50%` → masksToBounds + cornerRadius, `mask-image` → mask;
//   · the letters, their copy in shadow and the extrusion copies are cells of one atlas
//     (DepthSwipeTitleArt), so the whole name is one texture.
// Only what changed since the last frame is written.

private let degree = CGFloat.pi / 180.0

private func perspective(about offset: CGPoint) -> CATransform3D {
    var p = CATransform3DIdentity
    p.m34 = -1.0 / CGFloat(DepthSwipeLook.perspective)
    // Seen from `offset` (relative to the anchor point) instead of from the centre.
    return CATransform3DConcat(CATransform3DConcat(CATransform3DMakeTranslation(-offset.x, -offset.y, 0.0), p), CATransform3DMakeTranslation(offset.x, offset.y, 0.0))
}

/// A flat badge of the row (verified, emoji status, muted, online…) that rolls over the rim: a copy
/// with the badge's place, transform and opacity, on top of the row's content (the badge may sit in
/// the photo, which the disc replaces).
private final class DepthSwipeBadge {
    let layer = SimpleLayer()
    let transform: CATransform3D
    let opacity: Float
    var state: DepthSwipeFrame.Icon??

    init(art: DepthSwipeBadgeArt, parent: CALayer) {
        let original = art.original
        self.transform = original.transform
        self.opacity = original.opacity
        self.layer.contents = art.image
        self.layer.contentsScale = UIScreenScale
        self.layer.bounds = CGRect(origin: CGPoint(), size: original.bounds.size)
        self.layer.anchorPoint = original.anchorPoint
        if let superlayer = original.superlayer {
            self.layer.position = parent.convert(original.position, from: superlayer)
        } else {
            self.layer.position = original.position
        }
        self.layer.transform = self.transform
        self.layer.opacity = self.opacity
        parent.addSublayer(self.layer)
    }

    func apply(_ icon: DepthSwipeFrame.Icon?) {
        if let state = self.state, state == icon {
            return
        }
        self.state = .some(icon)
        if let icon {
            // perspective(P) translate3d(tx, 0, dz) rotateY(−angle), after the badge's own transform.
            var p = CATransform3DIdentity
            p.m34 = -1.0 / CGFloat(DepthSwipeLook.perspective)
            var t = CATransform3DMakeRotation(-CGFloat(icon.angle) * degree, 0.0, 1.0, 0.0)
            t = CATransform3DConcat(t, CATransform3DMakeTranslation(CGFloat(icon.tx), 0.0, CGFloat(icon.dz)))
            t = CATransform3DConcat(t, p)
            self.layer.transform = CATransform3DConcat(self.transform, t)
            self.layer.opacity = self.opacity * Float(icon.opacity)
        } else {
            self.layer.transform = self.transform
            self.layer.opacity = self.opacity
        }
    }
}

/// The name: one CATransformLayer per letter holding its extrusion copies, its face and its copy in
/// shadow, under a layer with the name's perspective (buildTitle).
private final class DepthSwipeTitleLayers {
    private final class Glyph {
        let layer = SimpleTransformLayer()
        let face = SimpleLayer()
        let shade = SimpleLayer()
        var copies: [SimpleLayer] = []
        var state: DepthSwipeFrame.Glyph?
    }

    let container = SimpleLayer()
    private var glyphs: [Glyph] = []

    init(art: DepthSwipeTitleArt, frame: CGRect) {
        self.container.frame = frame
        self.container.sublayerTransform = perspective(about: CGPoint())
        let height = art.nodeSize.height
        let title = DepthSwipeLook.title
        for unit in art.units {
            let glyph = Glyph()
            glyph.layer.bounds = CGRect(x: 0.0, y: 0.0, width: unit.width, height: height)
            glyph.layer.anchorPoint = CGPoint(x: 0.5, y: 0.55)
            glyph.layer.position = CGPoint(x: unit.x + unit.width * 0.5, y: height * 0.55)
            func piece(_ layer: SimpleLayer, row: Int) {
                layer.contents = art.image
                layer.contentsScale = UIScreenScale
                layer.contentsRect = art.contentsRect(unit, row: row)
                layer.frame = art.pieceFrame(unit)
            }
            // Back to front: copy `layers` … copy 1, the face, the face in shadow.
            for j in stride(from: title.layers, through: 1, by: -1) {
                let copy = SimpleLayer()
                piece(copy, row: DepthSwipeTitleArt.copyRow(j))
                copy.zPosition = -CGFloat(j) * CGFloat(title.depth) / CGFloat(title.layers)
                glyph.layer.addSublayer(copy)
                glyph.copies.append(copy)
            }
            piece(glyph.face, row: DepthSwipeTitleArt.faceRow)
            glyph.layer.addSublayer(glyph.face)
            piece(glyph.shade, row: DepthSwipeTitleArt.shadeRow)
            glyph.shade.zPosition = 0.05
            glyph.shade.opacity = 0.0
            glyph.layer.addSublayer(glyph.shade)
            self.container.addSublayer(glyph.layer)
            self.glyphs.append(glyph)
        }
    }

    func apply(_ states: [DepthSwipeFrame.Glyph]) {
        for (glyph, state) in zip(self.glyphs, states) {
            let previous = glyph.state
            if previous == state {
                continue
            }
            glyph.state = state
            if previous?.angle != state.angle || previous?.lift != state.lift || previous?.rim != state.rim {
                // [translate3d(tx, 0, dz) rotateY(−angle) scale3d(1, 1, depthScale)] translateZ(lift) rotateX(angle)
                var t = CATransform3DMakeRotation(CGFloat(state.angle) * degree, 1.0, 0.0, 0.0)
                t = CATransform3DConcat(t, CATransform3DMakeTranslation(0.0, 0.0, CGFloat(state.lift)))
                if let rim = state.rim {
                    t = CATransform3DConcat(t, CATransform3DMakeScale(1.0, 1.0, CGFloat(rim.depthScale)))
                    t = CATransform3DConcat(t, CATransform3DMakeRotation(-CGFloat(rim.angle) * degree, 0.0, 1.0, 0.0))
                    t = CATransform3DConcat(t, CATransform3DMakeTranslation(CGFloat(rim.tx), 0.0, CGFloat(rim.dz)))
                }
                glyph.layer.transform = t
            }
            if previous?.shade != state.shade {
                glyph.shade.opacity = Float(state.shade)
            }
            if previous?.faceOpacity != state.faceOpacity {
                glyph.face.opacity = Float(state.faceOpacity)
            }
            if previous?.layerOpacity != state.layerOpacity {
                for copy in glyph.copies {
                    copy.opacity = Float(state.layerOpacity)
                }
            }
            if previous?.isHidden != state.isHidden {
                glyph.layer.isHidden = state.isHidden
            }
        }
    }
}

/// The message: one plate per line in a box with its own perspective; on a left swipe the box is
/// seen from its left end and the text fades into the rim through a mask (buildLines).
private final class DepthSwipeLinesLayers {
    let container = SimpleLayer()
    private var plates: [(layer: SimpleLayer, frame: CGRect)] = []
    private var states: [DepthSwipeFrame.Line?] = []
    private var direction: Int = 0
    private let mask = SimpleGradientLayer()
    private var maskState: DepthSwipeFrame.TextMask?

    /// `box`: the message box in the parent layer (the plates' frames are in the same space).
    init(plates: [DepthSwipePlateArt], box: CGRect) {
        self.container.frame = box
        for plate in plates {
            let layer = SimpleLayer()
            layer.contents = plate.image
            layer.contentsScale = UIScreenScale
            layer.contentsRect = plate.contentsRect
            let frame = plate.frame.offsetBy(dx: -box.minX, dy: -box.minY)
            layer.frame = frame
            layer.opacity = plate.opacity
            self.container.addSublayer(layer)
            self.plates.append((layer, frame))
            self.states.append(nil)
        }
        self.mask.startPoint = CGPoint(x: 0.0, y: 0.5)
        self.mask.endPoint = CGPoint(x: 1.0, y: 0.5)
        self.mask.frame = CGRect(origin: CGPoint(), size: box.size)
    }

    func apply(direction: Int, lines: [DepthSwipeFrame.Line], mask: DepthSwipeFrame.TextMask?) {
        let size = self.container.bounds.size
        if direction != self.direction {
            self.direction = direction
            // Seen from its left end on a left swipe (perspective-origin 0% 50%), else its centre.
            self.container.sublayerTransform = perspective(about: CGPoint(x: direction < 0 ? -size.width * 0.5 : 0.0, y: 0.0))
            // A plate turns about its right end on a left swipe (the leading left end lifts), about
            // its left end on a right swipe — the ends of the box, as the line elements fill it.
            let pivotX: CGFloat = direction < 0 ? size.width : 0.0
            for plate in self.plates {
                let frame = plate.frame
                plate.layer.anchorPoint = CGPoint(x: frame.width > 0.0 ? (pivotX - frame.minX) / frame.width : 0.0, y: 0.5)
                plate.layer.position = CGPoint(x: pivotX, y: frame.midY)
            }
        }
        for i in 0 ..< min(lines.count, self.plates.count) {
            let line = lines[i]
            if self.states[i] == line {
                continue
            }
            self.states[i] = line
            self.plates[i].layer.transform = line.isFlat ? CATransform3DIdentity : CATransform3DMakeRotation(CGFloat(line.lean) * degree, 0.0, 1.0, 0.0)
        }
        if mask != self.maskState {
            self.maskState = mask
            if let mask {
                // linear-gradient(90deg, transparent start, #000 end) over the box; stops outside the
                // box are clamped with their colour interpolated, so the ramp is unchanged.
                let width = max(1.0, size.width)
                let start = CGFloat(mask.start)
                let end = CGFloat(mask.end)
                func alpha(_ x: CGFloat) -> CGFloat {
                    return end > start ? max(0.0, min(1.0, (x - start) / (end - start))) : (x >= end ? 1.0 : 0.0)
                }
                let p0 = max(0.0, min(width, start))
                let p1 = max(0.0, min(width, end))
                self.mask.colors = [UIColor(white: 0.0, alpha: alpha(p0)).cgColor, UIColor(white: 0.0, alpha: alpha(p1)).cgColor]
                self.mask.locations = [NSNumber(value: Double(p0 / width)), NSNumber(value: Double(p1 / width))]
                if self.container.mask == nil {
                    self.container.mask = self.mask
                }
            } else {
                self.container.mask = nil
            }
        }
    }
}

/// The photo as a thick disc: rim slices behind its face, the same picture on its back, the picture
/// inset in the face (parallax), what else the photo draws (a story ring) printed on the face, a glint
/// and the rim's shadow on top (buildAvatar).
private final class DepthSwipeDiscLayers {
    let container = SimpleLayer()
    private let disc = SimpleTransformLayer()
    private let inner = SimpleLayer()
    private let glint = SimpleGradientLayer()
    private let dim = SimpleLayer()
    private let half: CGFloat
    private let baseOpacity: Float
    private var state: DepthSwipeFrame.Disc?

    init(art: DepthSwipeDiscArt, frame: CGRect, opacity: Float) {
        let avatar = DepthSwipeLook.avatar
        let size = frame.size
        let bounds = CGRect(origin: CGPoint(), size: size)
        let radius = min(art.cornerRadius, min(size.width, size.height) * 0.5)
        let color = art.color
        self.half = size.width * 0.5
        self.baseOpacity = opacity
        self.container.frame = frame
        self.container.opacity = opacity
        self.container.sublayerTransform = perspective(about: CGPoint())
        self.disc.bounds = bounds
        self.disc.position = CGPoint(x: bounds.midX, y: bounds.midY)
        self.container.addSublayer(self.disc)

        func shade(_ k: CGFloat) -> CGColor {
            return UIColor(red: (color.r * 255.0 * k).rounded() / 255.0, green: (color.g * 255.0 * k).rounded() / 255.0, blue: (color.b * 255.0 * k).rounded() / 255.0, alpha: 1.0).cgColor
        }

        // The back: the same picture (one photo, both sides), facing backward behind the slices.
        let back = SimpleLayer()
        back.frame = bounds
        back.contents = art.picture
        back.contentsScale = UIScreenScale
        back.contentsGravity = .resizeAspectFill
        back.cornerRadius = radius
        back.masksToBounds = true
        back.isDoubleSided = false
        // translateZ(−depth − 0.05) rotateY(180deg)
        back.transform = CATransform3DConcat(CATransform3DMakeRotation(CGFloat.pi, 0.0, 1.0, 0.0), CATransform3DMakeTranslation(0.0, 0.0, -CGFloat(avatar.depth) - 0.05))
        if let edge = art.backEdge {
            let backShade = SimpleLayer()
            backShade.frame = bounds
            backShade.contents = edge
            backShade.contentsScale = UIScreenScale
            back.addSublayer(backShade)
        }
        self.disc.addSublayer(back)

        // The rim: slices behind the face, lit next to it.
        for j in stride(from: avatar.layers, through: 1, by: -1) {
            let slice = SimpleLayer()
            slice.frame = bounds
            slice.cornerRadius = radius
            let lit = 0.55 + 0.25 * (1.0 - CGFloat(j) / CGFloat(avatar.layers))
            slice.backgroundColor = shade(lit)
            slice.zPosition = -CGFloat(j) * CGFloat(avatar.depth) / CGFloat(avatar.layers)
            self.disc.addSublayer(slice)
        }

        // The face.
        let face = SimpleLayer()
        face.frame = bounds
        face.cornerRadius = radius
        face.masksToBounds = true
        face.isDoubleSided = false
        self.inner.frame = art.pictureFrame
        self.inner.contents = art.picture
        self.inner.contentsScale = UIScreenScale
        self.inner.contentsGravity = .resizeAspectFill
        face.addSublayer(self.inner)
        if let decorations = art.decorations {
            let printed = SimpleLayer()
            printed.frame = bounds
            printed.contents = decorations
            printed.contentsScale = UIScreenScale
            face.addSublayer(printed)
        }
        if let edge = art.faceEdge {
            let rim = SimpleLayer()
            rim.frame = bounds
            rim.contents = edge
            rim.contentsScale = UIScreenScale
            face.addSublayer(rim)
        }
        // linear-gradient(105deg, transparent 38%, white 55% at 50%, transparent 62%) on a box 30 %
        // larger on every side.
        self.glint.frame = bounds.insetBy(dx: -size.width * 0.3, dy: -size.height * 0.3)
        let angle = 105.0 * degree
        let direction = CGPoint(x: sin(angle), y: -cos(angle))
        let length = abs(direction.x) + abs(direction.y)
        self.glint.startPoint = CGPoint(x: 0.5 - direction.x * length * 0.5, y: 0.5 - direction.y * length * 0.5)
        self.glint.endPoint = CGPoint(x: 0.5 + direction.x * length * 0.5, y: 0.5 + direction.y * length * 0.5)
        self.glint.colors = [UIColor(white: 1.0, alpha: 0.0).cgColor, UIColor(white: 1.0, alpha: 0.55).cgColor, UIColor(white: 1.0, alpha: 0.0).cgColor]
        self.glint.locations = [0.38, 0.5, 0.62]
        self.glint.opacity = 0.0
        face.addSublayer(self.glint)
        self.dim.frame = bounds
        self.dim.cornerRadius = radius
        self.dim.backgroundColor = UIColor.black.cgColor
        self.dim.opacity = 0.0
        face.addSublayer(self.dim)
        self.disc.addSublayer(face)
    }

    func apply(_ state: DepthSwipeFrame.Disc) {
        let previous = self.state
        if previous == state {
            return
        }
        self.state = state
        if previous?.perspectiveOriginX != state.perspectiveOriginX {
            // Seen from straight in front of where it is (on the rim too).
            let originX = state.perspectiveOriginX.map { CGFloat($0) - self.half } ?? 0.0
            self.container.sublayerTransform = perspective(about: CGPoint(x: originX, y: 0.0))
        }
        // translate3d(dx, 0, z) rotateY(angle)
        self.disc.transform = CATransform3DConcat(CATransform3DMakeRotation(CGFloat(state.angle) * degree, 0.0, 1.0, 0.0), CATransform3DMakeTranslation(CGFloat(state.dx), 0.0, CGFloat(state.z)))
        // The picture sits deeper than the rim: it slides against the tilt (translateX scale(1.14)).
        // The prototype zooms it to 1.14 on the first frame; here the zoom comes in with the tilt
        // (all of it from a third of the way), so the flat photo hands over without a jump.
        let tilt = abs(state.parallax) / DepthSwipeLook.avatar.parallax
        let zoom = 1.0 + 0.14 * CGFloat(min(1.0, tilt * 3.0))
        self.inner.transform = CATransform3DConcat(CATransform3DMakeScale(zoom, zoom, 1.0), CATransform3DMakeTranslation(CGFloat(state.parallax), 0.0, 0.0))
        self.glint.transform = CATransform3DMakeTranslation(CGFloat(state.glint) * 0.01 * self.glint.bounds.width, 0.0, 0.0)
        self.glint.opacity = Float(state.glintOpacity)
        self.dim.opacity = Float(state.dim)
        // Faded on the photo's box, not on the disc: opacity there would flatten its rim.
        self.container.opacity = self.baseOpacity * Float(state.opacity)
        self.container.isHidden = state.isHidden
    }
}

/// Everything the rig puts over the row while it runs; removed in one go when it ends.
final class DepthSwipeLayers {
    private let title: DepthSwipeTitleLayers?
    private let lines: DepthSwipeLinesLayers?
    private let disc: DepthSwipeDiscLayers?
    private let badges: [DepthSwipeBadge]

    /// title: the name's atlas and its frame in its parent, placed right above the flat name;
    /// lines: the message's plates and the message box in their parent;
    /// avatar: the photo's pictures, its frame in its parent; badges: copies put on `badgeParent`.
    init(
        title: (art: DepthSwipeTitleArt, frame: CGRect, parent: CALayer, above: CALayer)?,
        lines: (plates: [DepthSwipePlateArt], box: CGRect, parent: CALayer, above: CALayer)?,
        avatar: (art: DepthSwipeDiscArt, frame: CGRect, parent: CALayer, above: CALayer)?,
        badges: [DepthSwipeBadgeArt],
        badgeParent: CALayer
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let title {
            let layers = DepthSwipeTitleLayers(art: title.art, frame: title.frame)
            layers.container.opacity = title.above.opacity
            title.parent.insertSublayer(layers.container, above: title.above)
            self.title = layers
        } else {
            self.title = nil
        }
        if let lines, !lines.plates.isEmpty {
            let layers = DepthSwipeLinesLayers(plates: lines.plates, box: lines.box)
            lines.parent.insertSublayer(layers.container, above: lines.above)
            self.lines = layers
        } else {
            self.lines = nil
        }
        if let avatar {
            let layers = DepthSwipeDiscLayers(art: avatar.art, frame: avatar.frame, opacity: avatar.above.opacity)
            avatar.parent.insertSublayer(layers.container, above: avatar.above)
            self.disc = layers
        } else {
            self.disc = nil
        }
        self.badges = badges.map { DepthSwipeBadge(art: $0, parent: badgeParent) }
        CATransaction.commit()
    }

    func apply(_ frame: DepthSwipeFrame) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.title?.apply(frame.glyphs)
        self.lines?.apply(direction: frame.direction, lines: frame.lines, mask: frame.textMask)
        if let disc = frame.disc {
            self.disc?.apply(disc)
        }
        for (badge, icon) in zip(self.badges, frame.icons) {
            badge.apply(icon)
        }
        CATransaction.commit()
    }

    /// Back to the flat row: the rig's layers go.
    func remove() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.title?.container.removeFromSuperlayer()
        self.lines?.container.removeFromSuperlayer()
        self.disc?.container.removeFromSuperlayer()
        for badge in self.badges {
            badge.layer.removeFromSuperlayer()
        }
        CATransaction.commit()
    }
}
