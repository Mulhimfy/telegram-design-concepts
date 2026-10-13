import Foundation
import UIKit
import AsyncDisplayKit
import Display

/// Plays Settings icons (prototype/src/settings/living-icons.js `LivingIcons`: `play(row, now)`,
/// `press(row, now)`, `update(now)`, `stop()`).
///
/// · `play` swaps the row's static icon (its `ASImageNode`, hidden — its image is never touched) for a
///   `LivingSettingsIconLayer` at the same place and runs the rig on the display link; on the frame at or past
///   the rig's duration the layer is removed and the static icon shown again, exactly as it was.
/// · `press` is the tap that opens the row's page: the tile gives under the finger (a copy of the static image,
///   0.6 s).
/// · One icon at a time: playing another stops the current one. Nothing runs at rest — the display link exists
///   only while something moves. With Reduce Motion nothing plays.
public final class LivingSettingsIconPlayer {
    private struct Playback {
        let icon: LivingSettingsIcon
        let layer: LivingSettingsIconLayer
        /// Holds the icon's layer (and clips the particles to the list's card).
        let host: SimpleLayer
        weak var imageNode: ASImageNode?
        weak var container: ASDisplayNode?
        let wasHidden: Bool
        let start: Double
    }

    private struct Press {
        let layer: SimpleLayer
        weak var imageNode: ASImageNode?
        weak var container: ASDisplayNode?
        let wasHidden: Bool
        let start: Double
    }

    private var current: Playback?
    private var pressed: Press?
    private var displayLink: SharedDisplayLinkDriver.Link?

    public var isPlaying: Bool {
        return self.current != nil
    }

    public init() {
    }

    deinit {
        self.displayLink?.invalidate()
    }

    private var isReduceMotionEnabled: Bool {
        return UIAccessibility.isReduceMotionEnabled
    }

    /// Where the static icon is, in `container`'s coordinates.
    private func iconFrame(_ imageNode: ASImageNode, in container: ASDisplayNode) -> CGRect {
        return imageNode.layer.convert(imageNode.layer.bounds, to: container.layer)
    }

    /// Plays `icon` in place of the row's static icon.
    ///
    /// - Parameters:
    ///   - imageNode: the row's icon node (its image is the static icon; it is hidden while the icon plays).
    ///   - container: where the icon plays — the row's list card (the particles may leave the row, not the card).
    ///   - glyphColor: the glyph's colour where it has no tile (the accent colour of the profile's own rows).
    ///   - cornerRadius: the card's corner radius; the particles are clipped to its rounded rect.
    public func play(_ icon: LivingSettingsIcon, imageNode: ASImageNode, container: ASDisplayNode, glyphColor: UIColor, cornerRadius: CGFloat) {
        guard !self.isReduceMotionEnabled, let image = imageNode.image, imageNode.supernode != nil else {
            return
        }
        self.stop()
        self.endPress()

        let tile = icon.tile
        let tileImage = tile?.image()
        if tile != nil && tileImage == nil {
            return
        }
        let style = LivingSettingsIconLayer.Style(
            glyphColor: tile != nil ? .white : glyphColor,
            tileColor: tile?.color ?? glyphColor,
            tileImage: tileImage,
            elementImage: icon == .money ? image : nil
        )
        let tree = LivingIconArtwork.tree(icon.rawValue)
        let frame = self.iconFrame(imageNode, in: container)
        let layer = LivingSettingsIconLayer(rig: icon.rig, tree: tree, style: style, size: frame.size, screenScale: UIScreenScale)

        let host = self.makeHost(in: container, cornerRadius: cornerRadius)
        layer.position = CGPoint(x: frame.midX, y: frame.midY)
        host.addSublayer(layer)
        container.layer.addSublayer(host)

        let start = CACurrentMediaTime()
        layer.apply(icon.rig.run(0.0))
        let wasHidden = imageNode.isHidden
        imageNode.isHidden = true
        self.current = Playback(icon: icon, layer: layer, host: host, imageNode: imageNode, container: container, wasHidden: wasHidden, start: start)
        self.updateDisplayLink()
    }

    /// The tap that opens the row's page: the tile (or glyph) squashes and springs back.
    public func press(imageNode: ASImageNode, container: ASDisplayNode) {
        guard !self.isReduceMotionEnabled, let image = imageNode.image, imageNode.supernode != nil else {
            return
        }
        if self.current?.imageNode === imageNode {
            return
        }
        self.endPress()

        let frame = self.iconFrame(imageNode, in: container)
        let layer = SimpleLayer()
        layer.bounds = CGRect(origin: CGPoint(), size: frame.size)
        layer.position = CGPoint(x: frame.midX, y: frame.midY)
        layer.contents = image.cgImage
        layer.contentsScale = image.scale
        container.layer.addSublayer(layer)

        let wasHidden = imageNode.isHidden
        imageNode.isHidden = true
        self.pressed = Press(layer: layer, imageNode: imageNode, container: container, wasHidden: wasHidden, start: CACurrentMediaTime())
        self.updateDisplayLink()
    }

    /// Stops the icon playing now, if any, and shows the static icon again.
    public func stop() {
        guard let current = self.current else {
            return
        }
        self.current = nil
        current.host.removeFromSuperlayer()
        current.imageNode?.isHidden = current.wasHidden
        self.updateDisplayLink()
    }

    private func endPress() {
        guard let pressed = self.pressed else {
            return
        }
        self.pressed = nil
        pressed.layer.removeFromSuperlayer()
        pressed.imageNode?.isHidden = pressed.wasHidden
        self.updateDisplayLink()
    }

    /// A layer over the whole card, clipped to its rounded rect (the prototype's card hides what leaves it).
    private func makeHost(in container: ASDisplayNode, cornerRadius: CGFloat) -> SimpleLayer {
        let host = SimpleLayer()
        host.frame = container.layer.bounds
        if cornerRadius > 0.0 {
            let mask = SimpleShapeLayer()
            mask.frame = host.bounds
            mask.path = UIBezierPath(roundedRect: host.bounds, cornerRadius: cornerRadius).cgPath
            mask.fillColor = UIColor.black.cgColor
            mask.contentsScale = UIScreenScale
            host.mask = mask
        }
        return host
    }

    private func updateDisplayLink() {
        if self.current != nil || self.pressed != nil {
            if self.displayLink == nil {
                self.displayLink = SharedDisplayLinkDriver.shared.add(framesPerSecond: .max, { [weak self] _ in
                    self?.tick()
                })
            }
        } else if let displayLink = self.displayLink {
            self.displayLink = nil
            displayLink.invalidate()
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()

        if let pressed = self.pressed {
            if let scale = LivingIconFX.pressScale(now - pressed.start), pressed.imageNode?.supernode != nil {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                if let imageNode = pressed.imageNode, let container = pressed.container {
                    let frame = self.iconFrame(imageNode, in: container)
                    pressed.layer.position = CGPoint(x: frame.midX, y: frame.midY)
                }
                pressed.layer.setAffineTransform(CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))
                CATransaction.commit()
            } else {
                self.endPress()
            }
        }

        if let current = self.current {
            let t = now - current.start
            guard t < current.icon.rig.duration, let imageNode = current.imageNode, let container = current.container, imageNode.supernode != nil else {
                // Done (or the row is gone): the static icon again, exactly as it was.
                self.stop()
                return
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            // Follow the row if the list lays it out again meanwhile.
            current.host.frame = container.layer.bounds
            let frame = self.iconFrame(imageNode, in: container)
            current.layer.position = CGPoint(x: frame.midX, y: frame.midY)
            CATransaction.commit()
            current.layer.apply(current.icon.rig.run(t))
        }
    }
}
