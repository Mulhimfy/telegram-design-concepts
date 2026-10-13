import XCTest
import Foundation
import CoreGraphics
@testable import LivingIconsCore

/// The artwork: the SVG parser against an independent reader (tools/golden-icons.mjs measures every
/// piece of every icon file and the rebuilt geometry), every icon cut exactly as the prototype cuts it
/// (`parts` trees node for node; what every part holds, for every rig; Telegram's glyphs cut at the same
/// places), and every part a rig moves present in its icon.
final class ArtworkTests: XCTestCase {
    /// Bounds: the recorder samples curves and arcs densely; CoreGraphics keeps arcs as ≤ 90° cubics.
    static let boundsTolerance = 0.005

    private var art: [String: Any] {
        return GoldenIconsTests.golden["art"] as! [String: Any]
    }

    private func bounds(_ path: CGPath) -> [Double]? {
        let box = path.boundingBoxOfPath
        if box.isNull || (box.width == 0.0 && box.height == 0.0) {
            return nil
        }
        return [Double(box.minX), Double(box.minY), Double(box.maxX), Double(box.maxY)]
    }

    private func assertBounds(_ path: CGPath, _ expected: [Double], _ what: String) {
        guard expected[2] > expected[0] || expected[3] > expected[1] else {
            // A lone moveto (the cairo files end with one): nothing drawn.
            XCTAssertNil(self.bounds(path), "\(what): expected an empty piece")
            return
        }
        guard let actual = self.bounds(path) else {
            XCTFail("\(what): empty, expected \(expected)")
            return
        }
        for i in 0 ..< 4 where abs(actual[i] - expected[i]) > ArtworkTests.boundsTolerance {
            XCTFail("\(what): bounds \(actual), expected \(expected)")
            return
        }
    }

    func testIconFilesParseLikeTheWeb() {
        let files = self.art["files"] as! [String: [[[Double]]]]
        XCTAssertEqual(Set(files.keys), Set(LivingIconArtworkFiles.byName.keys))
        for (name, sources) in files {
            let swift = LivingIconArtworkFiles.byName[name]!
            XCTAssertEqual(swift.count, sources.count, "\(name) sources")
            for (i, (source, expected)) in zip(swift, sources).enumerated() {
                let pieces = source.pieces
                XCTAssertEqual(pieces.count, expected.count, "\(name) source \(i) pieces")
                for (j, (piece, box)) in zip(pieces, expected).enumerated() {
                    self.assertBounds(piece, box, "\(name) source \(i) piece \(j)")
                }
            }
        }
    }

    func testRebuiltGeometryParsesLikeTheWeb() {
        let paths = self.art["paths"] as! [String: [String: Any]]
        let swift: [String: String] = [
            "LOCK_BODY": LivingIconArtwork.lockBody,
            "LOCK_SHACKLE": LivingIconArtwork.lockShackle,
            "PROFILE_BUST": LivingIconArtwork.profileBust,
        ]
        XCTAssertEqual(Set(paths.keys), Set(swift.keys))
        for (name, value) in paths {
            XCTAssertEqual(swift[name], value["d"] as? String, "\(name) is the prototype's path data")
            let pieces = LivingIconPath.subpaths(swift[name]!)
            let expected = value["bounds"] as! [[Double]]
            XCTAssertEqual(pieces.count, expected.count, name)
            for (piece, box) in zip(pieces, expected) {
                self.assertBounds(piece, box, name)
            }
        }
    }

    func testPathCommands() {
        // Implicit linetos after a moveto, relative commands, H/V, closepath back to the start.
        let power = LivingIconPath.path("M17.3 4.5 8.4 16.6h5.5l-1.6 8.9 9.3-12.4h-5.6z")
        assertEqualArrays(self.bounds(power)!, [8.4, 4.5, 21.6, 25.5], accuracy: 1e-9)
        // A relative moveto after a closepath starts from the closed subpath's start.
        let pieces = LivingIconPath.subpaths("M15 11.2c-1.2-3.4-5.6-4.6-5.6-1.8 0 1.6 2.8 1.8 5.6 1.8zm0 0c1.2-3.4 5.6-4.6 5.6-1.8 0 1.6-2.8 1.8-5.6 1.8z")
        XCTAssertEqual(pieces.count, 2)
        XCTAssertEqual(Double(pieces[1].boundingBoxOfPath.minX), 15.0, accuracy: 1e-9)
        // Arcs: two half circles make a circle of radius 10 round (15, 15); compact flags ("01.5").
        let ring = LivingIconPath.path("M15 5a10 10 0 1 1 0 20a10 10 0 1 1 0-20z")
        assertEqualArrays(self.bounds(ring)!, [5.0, 5.0, 25.0, 25.0], accuracy: 1e-6)
        let compact = LivingIconPath.path("M0 0a1 1 0 01.5 1")
        XCTAssertEqual(Double(compact.currentPoint.x), 0.5, accuracy: 1e-9)
        XCTAssertEqual(Double(compact.currentPoint.y), 1.0, accuracy: 1e-9)
        // Smooth curves reflect the previous control point.
        let smooth = LivingIconPath.path("M15 5.6c5.5 0 9.6 3.6 9.6 8.2s-4.1 8.2-9.6 8.2")
        XCTAssertEqual(Double(smooth.boundingBoxOfPath.maxX), 24.6, accuracy: 1e-9)
        XCTAssertEqual(Double(smooth.currentPoint.y), 22.0, accuracy: 1e-9)
    }

    func testBookmarkAtRestIsTheFile() {
        // bookmark(0, 0, 0) is the file's shape (ic-saved.svg, rounded to 0.01).
        let rest = LivingIconPath.path(LivingIconArtwork.bookmark())
        let box = rest.boundingBoxOfPath
        XCTAssertEqual(Double(box.minX), 7.0, accuracy: 0.01)
        XCTAssertEqual(Double(box.minY), 6.0, accuracy: 0.01)
        XCTAssertEqual(Double(box.maxX), 23.0, accuracy: 0.01)
        XCTAssertEqual(Double(box.maxY), 23.21, accuracy: 0.02)
    }

    /// A tree as the recorder serializes play()'s: groups by name, paths with their joined pieces.
    private func serialize(_ node: LivingIconNode) -> Any? {
        switch node {
        case let .group(name, children):
            return ["group": name as Any, "children": children.compactMap(self.serialize)]
        case let .shape(shape):
            let pieces: Int
            switch shape.geometry {
            case let .pieces(paths):
                pieces = paths.count
            case .circle:
                pieces = 1
            case let .path(d):
                pieces = LivingIconPath.subpaths(d).count
            default:
                pieces = -1
            }
            return ["pieces": pieces, "evenOdd": shape.evenOdd, "stroke": shape.stroke as Any]
        case .paper:
            return ["paper": true]
        case .clipped, .cutout, .typingDot, .turningGlobe:
            return nil
        }
    }

    private func assertSame(_ actual: Any?, _ expected: Any?, _ path: String) {
        switch (actual, expected) {
        case let (a as [String: Any], e as [String: Any]):
            XCTAssertEqual(Set(a.keys), Set(e.keys), path)
            for (key, value) in e {
                self.assertSame(a[key], value, "\(path).\(key)")
            }
        case let (a as [Any], e as [Any]):
            XCTAssertEqual(a.count, e.count, path)
            for (i, (x, y)) in zip(a, e).enumerated() {
                self.assertSame(x, y, "\(path)[\(i)]")
            }
        case let (a as Bool, e as Bool):
            XCTAssertEqual(a, e, path)
        case let (a as Int, e as NSNumber):
            XCTAssertEqual(Double(a), e.doubleValue, path)
        case let (a as Double, e as NSNumber):
            XCTAssertEqual(a, e.doubleValue, accuracy: 1e-9, path)
        case let (a as String, e as String):
            XCTAssertEqual(a, e, path)
        default:
            let aIsNil = actual == nil || actual is NSNull || String(describing: actual!) == "nil"
            let eIsNil = expected == nil || expected is NSNull
            XCTAssertTrue(aIsNil && eIsNil, "\(path): \(String(describing: actual)) vs \(String(describing: expected))")
        }
    }

    /// `parts` rigs are cut exactly as play() cuts them.
    func testPartsAreCutLikeTheWeb() {
        for rig in GoldenIconsTests.rigs {
            guard let structure = rig["structure"] else {
                continue
            }
            let name = rig["name"] as! String
            let tree = LivingIconArtwork.tree(name)!
            self.assertSame(tree.compactMap(self.serialize), structure, name)
        }
    }

    /// Every icon has its cut (Money turns the row's own image).
    func testEveryIconIsCut() {
        for name in LivingIconRigs.all.keys {
            XCTAssertEqual(LivingIconArtwork.tree(name) == nil, name == "money", name)
        }
    }

    /// The bounds of what a geometry draws (nil: nothing).
    private func box(_ geometry: LivingIconGeometry) -> CGRect? {
        let box = geometry.makePath().boundingBoxOfPath
        return box.isNull || (box.width == 0.0 && box.height == 0.0) ? nil : box
    }

    private func meet(_ a: CGRect?, _ b: CGRect?) -> CGRect? {
        guard let a = a, let b = b else {
            return nil
        }
        let r = a.intersection(b)
        return r.isNull ? nil : r
    }

    private func join(_ a: CGRect?, _ b: CGRect?) -> CGRect? {
        guard let a = a else {
            return b
        }
        guard let b = b else {
            return a
        }
        return a.union(b)
    }

    /// What everything in `nodes` holds, as the recorder measures play()'s tree (`partBoxes`): every shape — its
    /// bounds (a stroke grown by half its width), cut by its own clip, the stroke it is revealed under (the prototype
    /// draws that stroke, clipped by the shape) and the clips of the groups above it (`clip`); a cut-out counts with
    /// its white shapes only.
    private func holds(_ nodes: [LivingIconNode], _ clip: CGRect?) -> CGRect? {
        var total: CGRect?
        for node in nodes {
            switch node {
            case let .group(_, children), let .typingDot(_, children):
                total = self.join(total, self.holds(children, clip))
            case let .shape(shape):
                var b = self.box(shape.geometry)
                if let stroke = shape.stroke {
                    b = b?.insetBy(dx: -CGFloat(stroke) / 2.0, dy: -CGFloat(stroke) / 2.0)
                }
                if let own = shape.clip {
                    b = self.meet(b, self.box(own))
                }
                if let reveal = shape.reveal {
                    b = self.meet(b, self.box(reveal.path)?.insetBy(dx: -CGFloat(reveal.width) / 2.0, dy: -CGFloat(reveal.width) / 2.0))
                }
                total = self.join(total, self.meet(b, clip))
            case let .clipped(geometry, children):
                total = self.join(total, self.holds(children, self.meet(clip, self.box(geometry))))
            case let .cutout(white, _):
                total = self.join(total, self.holds(white, clip))
            case let .turningGlobe(rest):
                // The banded globe and, cross-fading over it, the disc of the turning one.
                typealias G = LivingIconArtwork.TurningGlobe
                total = self.join(total, self.holds(rest, clip))
                total = self.join(total, self.meet(self.box(.circle(cx: G.center.0, cy: G.center.1, r: G.radius)), clip))
            case .paper:
                break
            }
        }
        return total
    }

    /// What each named part of a tree holds.
    private func partBoxes(_ tree: [LivingIconNode]) -> [String: CGRect?] {
        let everywhere = CGRect(x: -1e6, y: -1e6, width: 2e6, height: 2e6)
        var result: [String: CGRect?] = [:]
        func find(_ nodes: [LivingIconNode]) {
            for node in nodes {
                switch node {
                case let .group(name, children):
                    if let name = name {
                        // (updateValue keeps a part that holds nothing, as nil.)
                        result.updateValue(self.holds(children, everywhere), forKey: name)
                    }
                    find(children)
                case let .clipped(_, children), let .typingDot(_, children), let .turningGlobe(children):
                    find(children)
                case let .cutout(white, holes):
                    find(white)
                    find(holes)
                case .shape, .paper:
                    break
                }
            }
        }
        find(tree)
        return result
    }

    /// Every part of every icon holds what the prototype's part holds: the same pieces, cut at the same places.
    func testPartsHoldWhatTheWebsHold() {
        for rig in GoldenIconsTests.rigs {
            let name = rig["name"] as! String
            let expected = rig["boxes"] as! [String: Any]
            guard let tree = LivingIconArtwork.tree(name) else {
                XCTAssertTrue(expected.isEmpty, name)
                continue
            }
            let actual = self.partBoxes(tree)
            XCTAssertEqual(Set(actual.keys), Set(expected.keys), name)
            for (part, value) in expected {
                let what = "\(name) \(part)"
                let held: CGRect? = actual[part] ?? nil
                guard let box = value as? [NSNumber] else {
                    XCTAssertNil(held, "\(what): expected nothing")
                    continue
                }
                guard let a = held else {
                    XCTFail("\(what): holds nothing, expected \(box)")
                    continue
                }
                let e = box.map { $0.doubleValue }
                let values = [Double(a.minX), Double(a.minY), Double(a.maxX), Double(a.maxY)]
                for i in 0 ..< 4 where abs(values[i] - e[i]) > ArtworkTests.boundsTolerance {
                    XCTFail("\(what): holds \(values), expected \(e)")
                    break
                }
            }
        }
    }

    private func point(_ value: Any) -> (Double, Double)? {
        guard let p = value as? [NSNumber], p.count == 2 else {
            return nil
        }
        return (p[0].doubleValue, p[1].doubleValue)
    }

    private func assertPoints(_ actual: [(Double, Double)], _ expected: Any?, _ what: String) {
        let e = (expected as? [Any] ?? []).compactMap(self.point)
        XCTAssertEqual(actual.count, e.count, what)
        for (a, b) in zip(actual, e) {
            XCTAssertEqual(a.0, b.0, accuracy: 1e-9, what)
            XCTAssertEqual(a.1, b.1, accuracy: 1e-9, what)
        }
    }

    /// Telegram's glyphs are cut at the prototype's places (living-icons.js `CUTS`, `STAR_WEDGES`).
    func testCutsAreTheWebs() {
        typealias Cuts = LivingIconArtwork.Cuts
        typealias G = LivingIconArtwork.TurningGlobe
        let cuts = GoldenIconsTests.golden["cuts"] as! [String: Any]
        let number: (String) -> Double = { (cuts[$0] as! NSNumber).doubleValue }
        XCTAssertEqual(Cuts.giftCut, number("giftCut"))
        XCTAssertEqual(Cuts.giftOverlap, number("giftOverlap"))
        XCTAssertEqual(Cuts.faqCenterLine, cuts["faqCenterLine"] as? String)
        XCTAssertEqual(Cuts.faqRevealWidth, number("faqRevealWidth"))
        XCTAssertEqual(Cuts.dialInner, number("dialInner"))
        XCTAssertEqual(Cuts.dialOpening, number("dialOpening"))
        self.assertPoints(Cuts.starCorners, cuts["starCorners"], "starCorners")
        self.assertPoints(Cuts.starTips, cuts["starTips"], "starTips")
        self.assertPoints([Cuts.starCore], [cuts["starCore"]!], "starCore")
        self.assertPoints([Cuts.starSwooshOut], [cuts["starSwooshOut"]!], "starSwooshOut")
        let wedges = cuts["starWedges"] as! [Any]
        XCTAssertEqual(Cuts.starWedges.count, wedges.count)
        for (i, (wedge, expected)) in zip(Cuts.starWedges, wedges).enumerated() {
            self.assertPoints(wedge, expected, "starWedges[\(i)]")
        }
        let globe = cuts["globe"] as! [String: Any]
        let g: (String) -> Double = { (globe[$0] as! NSNumber).doubleValue }
        XCTAssertEqual(G.radius, g("radius"))
        XCTAssertEqual(G.latitudes, (globe["latitudes"] as! [NSNumber]).map { $0.doubleValue })
        XCTAssertEqual(G.gap, g("gap"))
        XCTAssertEqual(G.meridianScale, g("meridianScale"), accuracy: 1e-12)
        XCTAssertEqual(G.meridianHeight, g("meridianHeight"))
        XCTAssertEqual(G.fadeIn, g("fadeIn"))
        XCTAssertEqual(G.fadeOut, g("fadeOut"))
    }

    /// Every part a rig moves exists in its icon, and every part of the icon is one of the prototype's.
    func testEveryPartARigMovesExists() {
        for rig in GoldenIconsTests.rigs {
            let name = rig["name"] as! String
            let expected = Set(rig["parts"] as! [String])
            let rigObject = LivingIconRigs.all[name]!
            var moved = Set<String>()
            var t = 0.0
            while t <= rigObject.duration {
                let frame = rigObject.run(t)
                moved.formUnion(frame.parts.keys)
                moved.formUnion(frame.dashes.keys)
                t += 1.0 / 60.0
            }
            guard let tree = LivingIconArtwork.tree(name) else {
                XCTAssertEqual(name, "money")
                XCTAssertTrue(expected.isEmpty)
                continue
            }
            let parts = LivingIconArtwork.partNames(tree)
            XCTAssertEqual(parts.count, Set(parts).count, "\(name): duplicate part names")
            XCTAssertEqual(Set(parts), expected, name)
            XCTAssertTrue(moved.isSubset(of: Set(parts)), "\(name): \(moved.subtracting(parts)) not in the icon")
        }
    }
}

private func assertEqualArrays(_ a: [Double], _ b: [Double], accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.count, b.count, file: file, line: line)
    for (x, y) in zip(a, b) {
        XCTAssertEqual(x, y, accuracy: accuracy, file: file, line: line)
    }
}
