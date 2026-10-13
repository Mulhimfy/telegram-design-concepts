import XCTest
import Foundation
@testable import LivingIconsCore

/// Replays every rig of the web prototype (tools/golden-icons.mjs) through the Swift port, frame by frame
/// at 60 fps: what each rig asks for (part transforms, dashes, the bookmark / highlight / sparkle it
/// changes, its effect calls) and what the player then draws (every effect element, the tile's pop and
/// sheen, the press), within 1e-6.
final class GoldenIconsTests: XCTestCase {
    static let tolerance = 1e-6

    static let golden: [String: Any] = {
        let url = Bundle.module.url(forResource: "golden-icons", withExtension: "json")!
        let data = try! Data(contentsOf: url)
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }()

    static var rigs: [[String: Any]] {
        return golden["rigs"] as! [[String: Any]]
    }

    private func numbers(_ value: Any?) -> [Double] {
        guard let array = value as? [Any] else {
            return []
        }
        return array.compactMap { ($0 as? NSNumber)?.doubleValue }
    }

    private func assertClose(_ actual: [Double], _ expected: [Double], _ what: @autoclosure () -> String, file: StaticString = #filePath, line: UInt = #line) {
        guard actual.count == expected.count else {
            XCTFail("\(what()): \(actual.count) values, expected \(expected.count): \(actual) vs \(expected)", file: file, line: line)
            return
        }
        for (i, (a, e)) in zip(actual, expected).enumerated() where !(abs(a - e) <= GoldenIconsTests.tolerance) {
            XCTFail("\(what())[\(i)]: \(a), expected \(e)", file: file, line: line)
            return
        }
    }

    /// Every number of a string, in order (as the recorder reads attributes).
    private func numbers(in string: String) -> [Double] {
        let regex = try! NSRegularExpression(pattern: "-?(?:\\d+\\.?\\d*|\\.\\d+)(?:[eE][-+]?\\d+)?")
        let range = NSRange(string.startIndex ..< string.endIndex, in: string)
        return regex.matches(in: string, range: range).compactMap { match in
            Range(match.range, in: string).flatMap { Double(string[$0]) }
        }
    }

    private func hex(_ color: UInt32) -> String {
        return String(format: "#%06x", color)
    }

    func testEveryRigIsPorted() {
        let names = Set(GoldenIconsTests.rigs.map { $0["name"] as! String })
        XCTAssertEqual(names, Set(LivingIconRigs.all.keys))
        for rig in GoldenIconsTests.rigs {
            let name = rig["name"] as! String
            let swift = LivingIconRigs.all[name]!
            XCTAssertEqual(swift.duration, (rig["duration"] as! NSNumber).doubleValue, name)
            var flags: LivingIconRig.Flags = []
            for flag in rig["flags"] as! [String] {
                switch flag {
                case "paper": flags.insert(.paper)
                case "dots": flags.insert(.dots)
                case "globe": flags.insert(.globe)
                case "spin3d": flags.insert(.spin3d)
                case "hue": flags.insert(.hue)
                case "element": flags.insert(.element)
                default: XCTFail("\(name): unknown flag \(flag)")
                }
            }
            XCTAssertEqual(swift.flags, flags, name)
            // The player draws frames until the first one at or past the duration, then restores the icon.
            var frames = 0
            while Double(frames) / 60.0 < swift.duration {
                frames += 1
            }
            XCTAssertEqual(frames + 1, rig["frames"] as! Int, name)
        }
    }

    /// What `run(t, P, fx, E)` asks for.
    func testRigsMatchTheWeb() {
        for rig in GoldenIconsTests.rigs {
            let name = rig["name"] as! String
            let swift = LivingIconRigs.all[name]!
            for (i, raw) in (rig["raw"] as! [[String: Any]]).enumerated() {
                let t = Double(i) / 60.0
                let frame = swift.run(t)
                let at = "\(name) @\(i)"

                let parts = raw["parts"] as! [String: Any]
                XCTAssertEqual(Set(frame.parts.keys), Set(parts.keys), "\(at) parts")
                for (part, value) in parts {
                    guard let p = frame.parts[part] else {
                        continue
                    }
                    self.assertClose([p.r, p.x, p.y, p.sx, p.sy, p.kx, p.o, p.cx, p.cy], self.numbers(value), "\(at) \(part)")
                }

                let dash = raw["dash"] as! [String: Any]
                XCTAssertEqual(Set(frame.dashes.keys), Set(dash.keys), "\(at) dash")
                for (part, value) in dash {
                    self.assertClose([frame.dashes[part] ?? .nan], [(value as! NSNumber).doubleValue], "\(at) dash \(part)")
                }

                let attrs = raw["attrs"] as! [String: Any]
                var expectedKeys = Set<String>()
                if let b = frame.bookmark {
                    expectedKeys.insert("mark.d")
                    self.assertClose(self.numbers(in: LivingIconArtwork.bookmark(b.n, b.f, b.g)), self.numbers(attrs["mark.d"]), "\(at) mark.d")
                }
                if let shine = frame.shine {
                    expectedKeys.formUnion(["shine.stroke-dashoffset", "shine.opacity"])
                    self.assertClose([shine.dashOffset], self.numbers(attrs["shine.stroke-dashoffset"]), "\(at) shine offset")
                    self.assertClose([shine.opacity], self.numbers(attrs["shine.opacity"]), "\(at) shine opacity")
                }
                if let inner = frame.inner {
                    expectedKeys.insert("inner.transform")
                    self.assertClose([inner.rotation, 15.0, 13.4, 15.0, 13.4, inner.scale, -15.0, -13.4], self.numbers(attrs["inner.transform"]), "\(at) inner")
                }
                XCTAssertEqual(expectedKeys, Set(attrs.keys), "\(at) refs")

                let calls = raw["fx"] as! [[Any]]
                XCTAssertEqual(frame.effects.map(\.name), calls.map { $0[0] as! String }, "\(at) fx")
                for (call, expected) in zip(frame.effects, calls) {
                    var args = Array(expected.dropFirst())
                    if case let .sparkles(_, _, _, color) = call {
                        XCTAssertEqual(self.hex(color), args.last as? String, "\(at) sparkle colour")
                        args.removeLast()
                        self.assertClose(Array(call.arguments.dropLast()), self.numbers(args), "\(at) \(call.name)")
                    } else {
                        self.assertClose(call.arguments, self.numbers(args), "\(at) \(call.name)")
                    }
                }
            }
        }
    }

    /// What the player draws from it (the prototype's own `fx` and `update()` against a fake DOM).
    func testEffectsMatchTheWeb() {
        for rig in GoldenIconsTests.rigs {
            let name = rig["name"] as! String
            let swift = LivingIconRigs.all[name]!
            let tiled = name.hasPrefix("ic-")
            for (i, drawn) in (rig["drawn"] as! [[String: Any]]).enumerated() {
                let t = Double(i) / 60.0
                let frame = swift.run(t)
                let at = "\(name) @\(i)"

                var glint: Double?
                var filter: [Any] = []
                var spin: [Double] = []
                for call in frame.effects {
                    switch call {
                    case let .waves(t, t0, n):
                        let arcs = LivingIconFX.waves(t, t0, n)
                        let expected = drawn["waves"] as! [[Any]]
                        XCTAssertEqual(arcs.count, expected.count, "\(at) waves")
                        for (arc, e) in zip(arcs, expected) {
                            self.assertClose([arc.opacity, arc.dx, 0.0], self.numbers(e), "\(at) wave")
                        }
                    case let .glow(t, t0, k):
                        if let glow = LivingIconFX.glow(t, t0, k) {
                            filter = ["glow", glow.radius, glow.alpha]
                        } else {
                            filter = []
                        }
                    case let .glint(t, t0):
                        glint = LivingIconFX.glint(t, t0)
                    case let .halo(t, t0):
                        let halo = LivingIconFX.halo(t, t0)
                        self.assertClose([halo.opacity, halo.scale], self.numbers(drawn["halo"]), "\(at) halo")
                    case let .sparkles(t, t0, n, _):
                        let sparkles = LivingIconFX.sparkles(t, t0, n)
                        let expected = drawn["sparkles"] as! [[Any]]
                        XCTAssertEqual(sparkles.count, expected.count, "\(at) sparkles")
                        for (s, e) in zip(sparkles, expected) {
                            self.assertClose([s.opacity, s.x, s.y, s.rotation, s.scale], self.numbers(e), "\(at) sparkle")
                        }
                    case let .confetti(t, t0):
                        let pieces = LivingIconFX.confetti(t, t0)
                        let expected = drawn["confetti"] as! [[Any]]
                        XCTAssertEqual(pieces.count, expected.count, "\(at) confetti")
                        for (c, e) in zip(pieces, expected) {
                            self.assertClose(c.isLaunched ? [c.opacity, c.x, c.y, c.rotation] : [c.opacity], self.numbers(e), "\(at) confetto")
                        }
                    case let .dots(t, t0):
                        // The bubble's own dots: translate(0 dy).
                        let dots = LivingIconFX.dots(t, t0)
                        let expected = drawn["dots"] as! [[Any]]
                        XCTAssertEqual(dots.count, expected.count, "\(at) dots")
                        for (dy, e) in zip(dots, expected) {
                            self.assertClose([0.0, dy], self.numbers(e), "\(at) dot")
                        }
                    case let .rays(t, t0):
                        let o = LivingIconFX.rays(t, t0)
                        self.assertClose(Array(repeating: o, count: 5), self.numbers(drawn["rays"]), "\(at) rays")
                    case let .stroke(t, t0):
                        let s = LivingIconFX.stroke(t, t0)
                        self.assertClose([s.dashOffset, s.opacity], self.numbers(drawn["stroke"]), "\(at) stroke")
                    case let .paper(open):
                        let p = LivingIconFX.paper(open)
                        self.assertClose([p.y, p.opacity], self.numbers(drawn["paper"]), "\(at) paper")
                    case let .flash(t, t0):
                        let f = LivingIconFX.flash(t, t0)
                        self.assertClose([f.opacity, f.radius], self.numbers(drawn["flash"]), "\(at) flash")
                    case let .hue(t, d):
                        if let degrees = LivingIconFX.hue(t, d) {
                            filter = ["hue", degrees, LivingIconFX.hueSaturation]
                        } else {
                            filter = []
                        }
                    case let .spin3d(t, t0, d):
                        spin = LivingIconFX.spin3d(t, t0, d).map { [LivingIconFX.spinPerspective, $0] } ?? []
                    case let .globe(u):
                        // The turning globe's meridians (half-widths on Telegram's globe), the second's opacity, and
                        // the cross-fade: the turning globe over the banded one.
                        typealias G = LivingIconArtwork.TurningGlobe
                        let g = LivingIconFX.globe(u)
                        let w = LivingIconFX.globeCrossFade(t, duration: swift.duration)
                        self.assertClose([max(0.01, g.rx0 * G.meridianScale), max(0.01, g.rx1 * G.meridianScale), g.opacity1, w, 1.0 - w], self.numbers(drawn["globe"]), "\(at) globe")
                    }
                }

                // Filters and the 3D turn: "" when off.
                let expectedFilter = drawn["filter"] as! [Any]
                XCTAssertEqual(filter.first as? String, expectedFilter.first as? String, "\(at) filter")
                self.assertClose(filter.dropFirst().compactMap { $0 as? Double }, self.numbers(Array(expectedFilter.dropFirst())), "\(at) filter")
                self.assertClose(spin, self.numbers(drawn["spin"]), "\(at) spin")

                // The frame at or past the duration is drawn, then the player stops and the icon is itself
                // again: the tile's transform is cleared and Money's sparkle loses its transform.
                let restored = t >= swift.duration

                // The tile: its spring pop and the sheen (a glint sends it across again).
                if tiled {
                    self.assertClose(restored ? [] : [LivingIconFX.tileScale(t)], self.numbers(drawn["tile"]), "\(at) tile")
                    self.assertClose([glint ?? LivingIconFX.sheenOffset(t)], self.numbers(drawn["sheen"]), "\(at) sheen")
                } else {
                    XCTAssertNil(drawn["tile"], "\(at) tile")
                }

                // The reference elements as drawn.
                if restored && frame.inner != nil {
                    self.assertClose([], self.numbers(drawn["inner"]), "\(at) inner restored")
                } else if let inner = frame.inner {
                    self.assertClose([inner.rotation, 15.0, 13.4, 15.0, 13.4, inner.scale, -15.0, -13.4], self.numbers(drawn["inner"]), "\(at) inner")
                }
                if let shine = frame.shine {
                    self.assertClose([shine.dashOffset, shine.opacity], self.numbers(drawn["shine"]), "\(at) shine")
                }
                if let b = frame.bookmark {
                    self.assertClose(self.numbers(in: LivingIconArtwork.bookmark(b.n, b.f, b.g)), self.numbers(drawn["mark"]), "\(at) mark")
                }
            }
        }
    }

    /// The press: the tile squashes to 0.88 and springs back, then is itself again after 0.6 s.
    func testPressMatchesTheWeb() {
        let press = GoldenIconsTests.golden["press"] as! [[Any]]
        for (i, expected) in press.enumerated() {
            let t = Double(i) / 60.0
            self.assertClose(LivingIconFX.pressScale(t).map { [$0] } ?? [], self.numbers(expected), "press @\(i)")
        }
    }

    /// The CSS `hue-rotate(...) saturate(1.4)` matrix: identity at 0°, a full turn back to it, and a
    /// known value (pure red turned 120° and saturated).
    func testHueFilter() {
        let still = LivingIconFX.filterColor(red: 0.2, green: 0.5, blue: 0.9, hueDegrees: 0.0, saturation: 1.0)
        self.assertClose([still.red, still.green, still.blue], [0.2, 0.5, 0.9], "hue 0")
        let around = LivingIconFX.filterColor(red: 0.2, green: 0.5, blue: 0.9, hueDegrees: 360.0, saturation: 1.0)
        XCTAssertEqual(around.red, 0.2, accuracy: 1e-9)
        XCTAssertEqual(around.green, 0.5, accuracy: 1e-9)
        XCTAssertEqual(around.blue, 0.9, accuracy: 1e-9)
        // hueRotate(120°) of (1, 0, 0): row sums of the first column of the matrix.
        let c = cos(120.0 * Double.pi / 180.0)
        let s = sin(120.0 * Double.pi / 180.0)
        let turned = LivingIconFX.filterColor(red: 1.0, green: 0.0, blue: 0.0, hueDegrees: 120.0, saturation: 1.0)
        XCTAssertEqual(turned.red, max(0.0, min(1.0, 0.213 + c * 0.787 - s * 0.213)), accuracy: 1e-12)
        XCTAssertEqual(turned.green, max(0.0, min(1.0, 0.213 - c * 0.213 + s * 0.143)), accuracy: 1e-12)
        XCTAssertEqual(turned.blue, max(0.0, min(1.0, 0.213 - c * 0.213 - s * 0.787)), accuracy: 1e-12)
    }
}
