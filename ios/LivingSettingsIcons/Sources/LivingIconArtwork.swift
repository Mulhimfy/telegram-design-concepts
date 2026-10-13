import Foundation
import CoreGraphics

// The icons as parts (prototype/src/settings/living-icons.js): each Settings glyph — Telegram's own, at
// Telegram-iOS f1dd7a2 — cut along its own sub-shapes into the parts its rig moves, exactly as the prototype
// cuts it: by subpath index (`parts`, cut as `play()` does: groups in order, nested parts inside their parent,
// pieces of one source path joined so its holes keep cutting, the `rest` part last, the folder's paper after
// its back) or by hand (`build(c)`: groups, clip paths, masks whose black shapes cut moving holes). The glyph
// data is in LivingIconArtworkFiles. Pure data: LivingSettingsIconLayer turns it into layers.

/// One drawable element of an icon file (`<path>` / `<circle>` / `<ellipse>`), as `parse()` reads it.
public struct LivingIconSource {
    public enum Kind {
        case path(String)
        case circle(cx: Double, cy: Double, r: Double)
        case ellipse(cx: Double, cy: Double, rx: Double, ry: Double)
    }

    public let kind: Kind
    public let evenOdd: Bool
    /// The stroke width of a `fill="none"` element, or nil (filled).
    public let stroke: Double?
    public let roundCap: Bool

    public init(_ kind: Kind, evenOdd: Bool = false, stroke: Double? = nil, roundCap: Bool = false) {
        self.kind = kind
        self.evenOdd = evenOdd
        self.stroke = stroke
        self.roundCap = roundCap
    }

    /// The pieces `parse()` splits it into (one per moveto; circles and ellipses are one piece).
    public var pieces: [CGPath] {
        switch self.kind {
        case let .path(d):
            return LivingIconPath.subpaths(d)
        case let .circle(cx, cy, r):
            return [LivingIconPath.circle(cx: cx, cy: cy, r: r)]
        case let .ellipse(cx, cy, rx, ry):
            return [CGPath(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2.0 * rx, height: 2.0 * ry), transform: nil)]
        }
    }
}

/// The outline of a shape or a clip region, in the coordinates of the part that holds it (30 × 30 icon pt).
public indirect enum LivingIconGeometry {
    case path(String)
    case circle(cx: Double, cy: Double, r: Double)
    case polygon([(Double, Double)])
    /// Pieces of a source path joined into one path (`play()`'s `add`).
    case pieces([CGPath])
    /// A geometry under an SVG `transform` (a, b, c, d, tx, ty).
    case transformed(LivingIconGeometry, CGAffineTransform)

    public func makePath() -> CGPath {
        switch self {
        case let .path(d):
            return LivingIconPath.path(d)
        case let .circle(cx, cy, r):
            return LivingIconPath.circle(cx: cx, cy: cy, r: r)
        case let .polygon(points):
            let path = CGMutablePath()
            for (i, p) in points.enumerated() {
                if i == 0 {
                    path.move(to: CGPoint(x: p.0, y: p.1))
                } else {
                    path.addLine(to: CGPoint(x: p.0, y: p.1))
                }
            }
            path.closeSubpath()
            return path
        case let .pieces(pieces):
            let path = CGMutablePath()
            for piece in pieces {
                path.addPath(piece)
            }
            return path
        case let .transformed(geometry, transform):
            let path = CGMutablePath()
            path.addPath(geometry.makePath(), transform: transform)
            return path
        }
    }
}

/// A filled or stroked shape in the glyph's colour (or the tile's).
public struct LivingIconShape {
    public enum Paint {
        /// The glyph's colour: white on a tile, the accent colour for the profile's own rows.
        case glyph
        /// The tile's colour (fx drawn "cut into" the glyph, e.g. the lamp's highlight).
        case tile
    }

    /// A shape a rig changes directly (`E.<ref>`).
    public enum Ref {
        /// Saved Messages: the bookmark, redrawn from `bookmark(n, f, g)` every frame.
        case bookmark
        /// Telegram Features: the highlight drawn on (`stroke-dashoffset`, path length 1) and faded.
        case shine
    }

    public var geometry: LivingIconGeometry
    public var evenOdd: Bool
    public var stroke: Double?
    public var roundCap: Bool
    public var paint: Paint
    /// A clip path on the shape itself (moves with it).
    public var clip: LivingIconGeometry?
    public var ref: Ref?
    /// A filled shape "drawn" like a stroke: it shows only under a stroke of `reveal.width` along
    /// `reveal.path` (its centre line), which the rig draws back and on with its part's `dash(v)` (the
    /// prototype draws that stroke itself, clipped to the shape: the same pixels).
    public var reveal: (path: LivingIconGeometry, width: Double)?

    public init(_ geometry: LivingIconGeometry, evenOdd: Bool = false, stroke: Double? = nil, roundCap: Bool = false, paint: Paint = .glyph, clip: LivingIconGeometry? = nil, ref: Ref? = nil, reveal: (path: LivingIconGeometry, width: Double)? = nil) {
        self.geometry = geometry
        self.evenOdd = evenOdd
        self.stroke = stroke
        self.roundCap = roundCap
        self.paint = paint
        self.clip = clip
        self.ref = ref
        self.reveal = reveal
    }
}

/// The icon's SVG tree as the prototype builds it, inside the 30 × 30 glyph.
public indirect enum LivingIconNode {
    /// A `<g>`: a part when named (the rig moves it), or a plain container.
    case group(String?, [LivingIconNode])
    case shape(LivingIconShape)
    /// A group under a static `clip-path` (in the coordinates of the group's parent).
    case clipped(LivingIconGeometry, [LivingIconNode])
    /// A masked rect (`c.mask()`): what `white` covers, minus what `holes` cover — the holes are parts
    /// of their own that move inside it.
    case cutout(white: [LivingIconNode], holes: [LivingIconNode])
    /// The folder's paper sheet (`fx.paper`), between the folder's back and its flap.
    case paper
    /// One of Ask a Question's dots (cut out of its bubble, `refs.dots`): it bounces with dot `index`'s offset
    /// (`fx.dots`).
    case typingDot(Int, [LivingIconNode])
    /// Language: Telegram's banded globe (`rest`, the glyph) cross-fading into the same globe turning — a disc
    /// cut by its two latitudes and two moving meridians (`LivingIconArtwork.TurningGlobe`) — and back before
    /// the end (`fx.globe`).
    case turningGlobe(rest: [LivingIconNode])
}

public enum LivingIconArtwork {
    // MARK: - Geometry rebuilt by hand (living-icons.js, "geometry")

    /// The padlock's body and shackle (a 1.66 pt bar on a radius-5 arc; the file merges them).
    public static let lockBody = "M13 13L17 13C18.86 13 19.8 13 20.53 13.31C21.51 13.71 22.29 14.49 22.7 15.47C23 16.2 23 17.14 23 19C23 20.86 23 21.8 22.7 22.53C22.29 23.51 21.51 24.29 20.53 24.7C19.8 25 18.86 25 17 25L13 25C11.14 25 10.2 25 9.47 24.7C8.49 24.29 7.71 23.51 7.3 22.53C7 21.8 7 20.86 7 19C7 17.14 7 16.2 7.3 15.47C7.71 14.49 8.49 13.71 9.47 13.31C10.2 13 11.14 13 13 13Z"
    /// The long leg stays in the body when it opens.
    public static let lockShackle = "M10 19V10A5 5 0 0 1 20 10V14.2"
    /// My Profile: the bust under the head, down to the ring (clipped by its inner edge, r 8.67).
    public static let profileBust = "M8.5 20.73C9.58 19.21 11.52 17.84 15 17.84C18.48 17.84 20.41 19.21 21.5 20.73L26 20.73L26 31L4 31L4 20.73Z"

    /// Saved Messages: the bookmark with a ribbon end that can flap (`n`: notch, `f`: tail flare, `g`:
    /// tail length; 0, 0, 0 is the file's shape). The prototype writes the moving numbers with two
    /// decimals; here they keep full precision.
    public static func bookmark(_ n: Double = 0.0, _ f: Double = 0.0, _ g: Double = 0.0) -> String {
        func s(_ v: Double) -> String {
            return String(v)
        }
        let N: (Double) -> String = { y in s(y + n) }
        let R: (Double) -> String = { x in s(x + f) }
        let L: (Double) -> String = { x in s(x - f) }
        let Y: (Double) -> String = { y in s(y + g) }
        var d = "M7 12.4C7 10.16 7 9.04 7.44 8.18C7.82 7.43 8.43 6.82 9.18 6.44C10.04 6 11.16 6 13.4 6L16.6 6C18.84 6 19.96 6 20.82 6.44C21.57 6.82 22.18 7.43 22.56 8.18C23 9.04 23 10.16 23 12.4L23 19.71C23 21.39 23 22.23 "
        d += "\(R(22.66)) \(Y(22.64))C\(R(22.36)) \(Y(23.01)) \(R(21.92)) \(Y(23.21)) \(R(21.45)) \(Y(23.2))C\(R(20.91)) \(Y(23.18)) \(R(20.29)) \(Y(22.63)) 19.02 21.52"
        d += "L16.58 \(N(19.38))C16.02 \(N(18.89)) 15.74 \(N(18.65)) 15.43 \(N(18.55))C15.15 \(N(18.47)) 14.85 \(N(18.47)) 14.57 \(N(18.55))C14.26 \(N(18.65)) 13.98 \(N(18.89)) 13.42 \(N(19.38))"
        d += "L10.98 21.52C9.71 22.63 9.09 23.18 \(L(8.55)) \(Y(23.2))C\(L(8.08)) \(Y(23.21)) \(L(7.64)) \(Y(23.01)) \(L(7.34)) \(Y(22.64))C7 22.23 7 21.39 7 19.71Z"
        return d
    }

    // MARK: - How Telegram's glyphs are cut (living-icons.js `CUTS`, `STAR_WEDGES`)

    /// Where one outline holds parts that move apart, the cut (the golden data records the prototype's numbers;
    /// ArtworkTests compares them).
    public enum Cuts {
        /// Send a Gift: the lid and the bow are one outline; they part where the bow meets the lid (y 9). The lid
        /// reaches 0.25 pt up into the bow, so the cut never shows at rest.
        public static let giftCut = 9.0
        public static let giftOverlap = 0.25
        /// Telegram FAQ: the question mark was drawn as a 1.66 pt stroke round a radius-3 arc; it is cut out along
        /// that centre line (running on past both round ends, so that the butt ends uncover them whole), 3.2 pt wide.
        public static let faqCenterLine = "M12 14.2L12 13A3 3 0 0 1 18 13C18 14.25 17.3 15.25 16.25 15.75C15.45 16.13 15 16.6 15 17.3L15 18.6"
        public static let faqRevealWidth = 3.2
        /// Telegram Premium: the star's concave corners (top-left, top-right, right, bottom, the tip of the swoosh
        /// cut into it), its tips (arm 0 … 4), the centre of the core between the corners (the star's own centre
        /// lies in the swoosh), and a point out along the swoosh (between the bottom-left and left arms).
        public static let starCorners: [(Double, Double)] = [(11.3, 10.55), (18.7, 10.5), (20.75, 17.3), (14.97, 21.6), (15.5, 15.15)]
        public static let starTips: [(Double, Double)] = [(15.0, 5.0), (25.0, 12.4), (20.5, 24.0), (9.0, 23.6), (5.3, 12.4)]
        public static let starCore: (Double, Double) = (16.5, 14.5)
        public static let starSwooshOut: (Double, Double) = (3.3, 20.85)
        /// Appearance: the dial's ring (inner radius) and the circle its half disc stays in (0.3 pt into the ring:
        /// no seam).
        public static let dialInner = 8.339844
        public static let dialOpening = 8.64

        private static func towardCore(_ p: (Double, Double), _ k: Double) -> (Double, Double) {
            return (p.0 + (starCore.0 - p.0) * k, p.1 + (starCore.1 - p.1) * k)
        }

        private static func awayFromCore(_ p: (Double, Double), _ k: Double) -> (Double, Double) {
            return (p.0 + (p.0 - starCore.0) * k, p.1 + (p.1 - starCore.1) * k)
        }

        /// Premium: arm i lies between corners i and i + 1 — from 22 % inside the core out past both corners and
        /// past its tip (the arms overlap the core: no seams).
        public static let starWedges: [[(Double, Double)]] = (0 ..< 5).map { i -> [(Double, Double)] in
            let a = starCorners[i]
            let b = starCorners[(i + 1) % 5]
            let outA = i == 4 ? starSwooshOut : awayFromCore(a, 2.5)
            let outB = (i + 1) % 5 == 4 ? starSwooshOut : awayFromCore(b, 2.5)
            return [towardCore(a, 0.22), outA, awayFromCore(starTips[i], 0.6), outB, towardCore(b, 0.22)]
        }
    }

    /// Language: the globe turning (living-icons.js `CUTS.globe`) — Telegram's globe (globe.pdf) as a disc of
    /// radius 10 cut by latitudes 1.33 wide at y 11.5 and 18.5 and by meridians 1.33 wide whose half-width at the
    /// equator is 4.165 at rest. The rig's meridian (rx 3.9 on an 8.6 globe) is scaled to that: `meridianScale`.
    public enum TurningGlobe {
        public static let center = (15.0, 15.0)
        public static let radius = 10.0
        public static let latitudes = [11.5, 18.5]
        public static let gap = 1.330078
        public static let meridianScale = 4.165039 / 3.9
        /// The meridians' half-height: their gaps reach the edge near the poles as Telegram's do.
        public static let meridianHeight = 11.0
        /// The cross-fades: from the banded globe in 0.06 s, back to it over the last 0.1 s (the meridian is at
        /// rest by then, `fx.globe(easeOut(t / 1.05))`).
        public static let fadeIn = 0.06
        public static let fadeOut = 0.1
    }

    // MARK: - Parts by subpath index (play(): rig.parts)

    /// `parts` of a rig: a name, the file pieces it takes, the part it moves inside (or `rest`: every piece
    /// no other part took).
    public enum PartSpec {
        case pieces([Int], parent: String? = nil)
        case rest
    }

    /// Cuts a file into parts exactly as `play()` does.
    public static func parts(_ file: [LivingIconSource], _ spec: [(String, PartSpec)], paper: Bool = false) -> [LivingIconNode] {
        final class Group {
            let name: String?
            var children: [Item] = []

            init(name: String?) {
                self.name = name
            }
        }
        enum Item {
            case group(Group)
            case shape(source: Int, pieces: [CGPath])
            case paper
        }

        // Every piece in file order, with the source it came from.
        var pieces: [(source: Int, path: CGPath)] = []
        let split = file.map { $0.pieces }
        for (source, sourcePieces) in split.enumerated() {
            for path in sourcePieces {
                pieces.append((source, path))
            }
        }

        let root = Group(name: nil)
        var groups: [String: Group] = [:]
        var used = Set<Int>()
        func add(_ group: Group, _ index: Int) {
            guard index >= 0 && index < pieces.count else {
                return
            }
            used.insert(index)
            let piece = pieces[index]
            // Subpaths of one source path stay in one path (its holes keep cutting).
            for (i, item) in group.children.enumerated() {
                if case let .shape(source, joined) = item, source == piece.source {
                    group.children[i] = .shape(source: source, pieces: joined + [piece.path])
                    return
                }
            }
            group.children.append(.shape(source: piece.source, pieces: [piece.path]))
        }
        var restName: String?
        for (name, part) in spec {
            switch part {
            case let .pieces(indexes, parent):
                let group = Group(name: name)
                (parent.flatMap { groups[$0] } ?? root).children.append(.group(group))
                groups[name] = group
                for index in indexes {
                    add(group, index)
                }
                // Paper (folder) goes between the back and the flap.
                if paper && name == "back" {
                    root.children.append(.paper)
                }
            case .rest:
                restName = restName ?? name
            }
        }
        if let restName = restName {
            let group = Group(name: restName)
            root.children.append(.group(group))
            for index in 0 ..< pieces.count where !used.contains(index) {
                add(group, index)
            }
        }

        func node(_ item: Item) -> LivingIconNode {
            switch item {
            case let .group(group):
                return .group(group.name, group.children.map(node))
            case let .shape(source, joined):
                let s = file[source]
                return .shape(LivingIconShape(.pieces(joined), evenOdd: s.evenOdd, stroke: s.stroke, roundCap: s.roundCap))
            case .paper:
                return .paper
            }
        }
        return root.children.map(node)
    }

    /// `c.pieces[i]`, …: pieces of a file (all of them when `indexes` is nil).
    private static func piecePaths(_ file: [LivingIconSource], _ indexes: [Int]? = nil) -> [CGPath] {
        var all: [CGPath] = []
        for source in file {
            all.append(contentsOf: source.pieces)
        }
        guard let indexes = indexes else {
            return all
        }
        return indexes.filter { $0 >= 0 && $0 < all.count }.map { all[$0] }
    }

    /// `c.pieces[i].attrs.d`, … joined with spaces: pieces of a file drawn as one path of their own (nonzero unless
    /// the shape says otherwise, as `c.path` draws it).
    private static func pieces(_ file: [LivingIconSource], _ indexes: [Int]? = nil) -> LivingIconGeometry {
        return .pieces(piecePaths(file, indexes))
    }

    /// `M x0 y0 H x1 V y1 H x0 Z`.
    private static func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> LivingIconGeometry {
        return .polygon([(x0, y0), (x1, y0), (x1, y1), (x0, y1)])
    }

    // MARK: - The icons

    /// The icon by the prototype's name, cut into the parts its rig moves (`RIGS[name].parts` / `.build`, line for
    /// line); at rest exactly Telegram's glyph. nil for Money, which turns the row's own image.
    public static func tree(_ name: String) -> [LivingIconNode]? {
        typealias Files = LivingIconArtworkFiles
        switch name {
        case "ic-bell":
            return parts(Files.bell, [("clapper", .pieces([0])), ("body", .pieces([1])), ("dot", .pieces([2, 3], parent: "body"))])
        case "ic-phone":
            // Cut across the middle of its handle: the two ends shake against each other.
            let d = pieces(Files.phone, [0])
            return [.group("handset", [
                .group("ear", [.shape(LivingIconShape(d, clip: .path("M-5 -5H35.6L-5 35.6Z")))]),
                .group("mouth", [.shape(LivingIconShape(d, clip: .path("M35 -5.6V35H-5.6Z")))]),
            ])]
        case "ic-folder":
            return parts(Files.folder, [("back", .pieces([1, 2])), ("front", .pieces([0]))], paper: true)
        case "ic-saved":
            return [.group("mark", [.shape(LivingIconShape(.path(bookmark()), ref: .bookmark))])]
        case "ic-data":
            return parts(Files.data, [("top", .pieces([4, 5])), ("middle", .pieces([0, 1])), ("bottom", .pieces([2, 3]))])
        case "ic-devices":
            return parts(Files.devices, [("laptop", .pieces([2])), ("screen", .pieces([3], parent: "laptop")), ("phone", .pieces([0, 1, 4, 5]))])
        case "ic-lock":
            return [.group("lock", [
                .group("shackle", [.shape(LivingIconShape(.path(lockShackle), stroke: 1.66))]),
                .group("body", [.shape(LivingIconShape(.path(lockBody)))]),
            ])]
        case "ic-profile":
            // The ring with the person cut out of it (a mask), so the person can move inside.
            return [.group("profile", [.cutout(
                white: [.shape(LivingIconShape(.path("M15 5a10 10 0 1 1 0 20a10 10 0 1 1 0-20z")))],
                holes: [
                    .clipped(.path("M15 6.33a8.67 8.67 0 1 1 0 17.34a8.67 8.67 0 1 1 0-17.34z"), [
                        .group("bust", [.shape(LivingIconShape(.path(profileBust)))]),
                    ]),
                    .group("head", [.shape(LivingIconShape(.path("M15 8.66a3.5 3.5 0 1 1 0 7a3.5 3.5 0 1 1 0-7z")))]),
                ]
            )])]
        case "ic-proxy":
            // The shield with its two arrows cut out (a mask): the arrows run through it, one each way.
            let shield = pieces(Files.proxy, [0])
            let inside = CGAffineTransform(translationX: 15.0, y: 15.0).scaledBy(x: 0.8, y: 0.8).translatedBy(x: -15.0, y: -15.0)
            return [.group("shield", [.cutout(
                white: [.shape(LivingIconShape(shield))],
                holes: [.clipped(.transformed(shield, inside), [
                    .group("right", [.shape(LivingIconShape(pieces(Files.proxy, [2])))]),
                    .group("left", [.shape(LivingIconShape(pieces(Files.proxy, [1])))]),
                ])]
            )])]
        case "ic-stars":
            // The disc with the star cut out (a mask): the star spins inside it.
            return [.group("disc", [.cutout(
                white: [.shape(LivingIconShape(pieces(Files.stars, [0])))],
                holes: [.group("star", [.shape(LivingIconShape(pieces(Files.stars, [1])))])]
            )])]
        case "ic-premium":
            // Telegram's star (five rounded arms, a swoosh cut in to its centre) as its core and five arms, cut by
            // clips at its concave corners: the arms fly out while it spins and snap back.
            let star = pieces(Files.premium, [0])
            var children: [LivingIconNode] = [.group("core", [.shape(LivingIconShape(star, evenOdd: true, clip: .polygon(Cuts.starCorners)))])]
            for (i, wedge) in Cuts.starWedges.enumerated() {
                children.append(.group("arm\(i)", [.shape(LivingIconShape(star, evenOdd: true, clip: .polygon(wedge)))]))
            }
            return [.group("star", children)]
        case "ic-power":
            // Telegram's battery: its shell and terminal (pieces 0, 1, 3), and the charge inside (`top`, piece 2).
            // The shell stays put (`bottom` is empty) so the charge jolts inside it.
            return [.group("bolt", [
                .shape(LivingIconShape(pieces(Files.power, [0, 1, 3]))),
                .group("bottom", []),
                .group("top", [.shape(LivingIconShape(pieces(Files.power, [2])))]),
            ])]
        case "ic-language":
            // Telegram's banded globe at rest; while it turns, the same globe drawn as a disc cut by its latitudes
            // and two moving meridians, cross-faded in and out (fx.globe).
            return [.group("globe", [.turningGlobe(rest: [.shape(LivingIconShape(pieces(Files.language)))])])]
        case "ic-gift":
            // Telegram's gift: the box's two halves, and the lid with the bow in one outline, parted where the bow
            // meets the lid (`Cuts.giftCut`).
            let top = pieces(Files.gift, [2])
            return [
                .group("lid", [.shape(LivingIconShape(top, clip: rect(-5.0, Cuts.giftCut - Cuts.giftOverlap, 35.0, 35.0)))]),
                .group("box", [.shape(LivingIconShape(pieces(Files.gift, [0, 1])))]),
                .group("bow", [.shape(LivingIconShape(top, clip: rect(-5.0, -5.0, 35.0, Cuts.giftCut)))]),
            ]
        case "ic-business":
            // Telegram's shop: its awning (the lid that pops open) and the shop under it with its window (the base).
            return [.group("case", [
                .group("base", [.shape(LivingIconShape(pieces(Files.business, [0, 1]), evenOdd: true))]),
                .group("lid", [.shape(LivingIconShape(pieces(Files.business, [2]), evenOdd: true))]),
            ])]
        case "ic-ask":
            // Telegram's bubble with its three dots cut out (a mask): the dots are the typing dots (fx.dots).
            return [.group("bubble", [.cutout(
                white: [.shape(LivingIconShape(pieces(Files.ask, [0])))],
                holes: (0 ..< 3).map { i -> LivingIconNode in .typingDot(i, [.shape(LivingIconShape(pieces(Files.ask, [1 + i])))]) }
            )])]
        case "ic-faq":
            // Telegram's disc with the question mark and its dot cut out (a mask). The mark is cut out under a stroke
            // along its centre line, which the rig undraws and draws again.
            return [.cutout(
                white: [.shape(LivingIconShape(pieces(Files.faq, [0])))],
                holes: [
                    .group("mark", [.shape(LivingIconShape(pieces(Files.faq, [2]), reveal: (.path(Cuts.faqCenterLine), Cuts.faqRevealWidth)))]),
                    .group("dot", [.shape(LivingIconShape(pieces(Files.faq, [1])))]),
                ]
            )]
        case "ic-features":
            // Telegram's lamp: its bulb (piece 1) and its base (piece 0). The glass catches a highlight as it lights
            // (drawn in the tile's colour).
            return [.group("lamp", [
                .group("bulb", [.shape(LivingIconShape(pieces(Files.features, [1])))]),
                .group("base", [.shape(LivingIconShape(pieces(Files.features, [0])))]),
                .group("shine", [.shape(LivingIconShape(.path("M11.2 11.6a3.9 3.9 0 0 1 3.2-3.7"), stroke: 1.3, roundCap: true, paint: .tile, ref: .shine))]),
            ])]
        case "ic-appearance":
            // Telegram's dial: its ring (the handle) and the half disc filling its left side (the tip), which stays
            // inside the ring's opening.
            let ring = LivingIconGeometry.pieces(piecePaths(Files.appearance, [0]) + [LivingIconPath.circle(cx: 15.0, cy: 15.0, r: Cuts.dialInner)])
            return [.group("brush", [
                .group("handle", [.shape(LivingIconShape(ring, evenOdd: true))]),
                .clipped(.circle(cx: 15.0, cy: 15.0, r: Cuts.dialOpening), [
                    .group("tip", [.shape(LivingIconShape(.path("M15 4L15 26L4 26L4 4Z")))]),
                ]),
            ])]
        case "set-emoji-status":
            return parts(Files.setEmojiStatus, [("leftEye", .pieces([0, 1])), ("rightEye", .pieces([2, 3])), ("smile", .pieces([4, 5, 6, 7, 8])), ("pencil", .pieces([9, 10, 11, 12, 13, 14])), ("face", .rest)])
        case "set-avatar":
            return parts(Files.setAvatar, [("camera", .pieces([])), ("body", .pieces([0, 5], parent: "camera")), ("lens", .pieces([1, 2], parent: "camera")), ("flash", .pieces([3], parent: "camera")), ("plus", .pieces([4], parent: "camera"))])
        case "set-covercolor":
            return parts(Files.setCoverColor, [
                ("palette", .pieces([])),
                ("frame", .pieces([0, 1, 2, 3, 4, 6, 9], parent: "palette")),
                ("avatar", .pieces([7, 8], parent: "palette")),
                ("bar", .pieces([5], parent: "palette")),
                ("s1", .pieces([10], parent: "palette")),
                ("s2", .pieces([11], parent: "palette")),
                ("s3", .pieces([12, 13], parent: "palette")),
            ])
        default:
            return nil
        }
    }

    /// Every named part of a tree (the rig's `P`), in tree order.
    public static func partNames(_ nodes: [LivingIconNode]) -> [String] {
        var names: [String] = []
        func visit(_ node: LivingIconNode) {
            switch node {
            case let .group(name, children):
                if let name = name {
                    names.append(name)
                }
                children.forEach(visit)
            case let .clipped(_, children):
                children.forEach(visit)
            case let .cutout(white, holes):
                white.forEach(visit)
                holes.forEach(visit)
            case let .typingDot(_, children):
                children.forEach(visit)
            case let .turningGlobe(rest):
                rest.forEach(visit)
            case .shape, .paper:
                break
            }
        }
        nodes.forEach(visit)
        return names
    }
}
