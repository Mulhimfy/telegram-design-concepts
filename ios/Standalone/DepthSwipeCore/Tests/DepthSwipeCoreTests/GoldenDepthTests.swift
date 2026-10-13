import XCTest
import Foundation
@testable import DepthSwipeCore

/// Replays the swipes recorded from the web prototype (tools/golden-depth.mjs drives
/// prototype/src/chats/depth.js the way chat-list.js does) through the Swift rig and tracker, frame
/// by frame, and requires the same numbers: every letter's roll, angle, lift, place on the rim,
/// shade and fade, the badges, the text mask, the line leans and the disc — and the same frames
/// for starting, spinning and ending.
final class GoldenDepthTests: XCTestCase {
    /// A JSON value (the golden frames mix numbers, strings, arrays and nulls).
    private enum JSON: Decodable {
        case number(Double)
        case string(String)
        case bool(Bool)
        case array([JSON])
        case object([String: JSON])
        case null

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Double.self) {
                self = .number(value)
            } else if let value = try? container.decode(String.self) {
                self = .string(value)
            } else if let value = try? container.decode([JSON].self) {
                self = .array(value)
            } else {
                self = .object(try container.decode([String: JSON].self))
            }
        }

        subscript(_ index: Int) -> JSON {
            if case let .array(values) = self, index < values.count {
                return values[index]
            }
            return .null
        }

        subscript(_ key: String) -> JSON {
            if case let .object(values) = self, let value = values[key] {
                return value
            }
            return .null
        }

        var number: Double {
            switch self {
            case let .number(value):
                return value
            case let .bool(value):
                return value ? 1.0 : 0.0
            default:
                return .nan
            }
        }

        var optionalNumber: Double? {
            if case .null = self {
                return nil
            }
            return self.number
        }

        var bool: Bool {
            switch self {
            case let .bool(value):
                return value
            case let .number(value):
                return value != 0.0
            default:
                return false
            }
        }

        var string: String {
            if case let .string(value) = self {
                return value
            }
            return ""
        }

        var array: [JSON] {
            if case let .array(values) = self {
                return values
            }
            return []
        }

        var isNull: Bool {
            if case .null = self {
                return true
            }
            return false
        }
    }

    /// Angles, points and opacities agree to well under a thousandth of a degree / point.
    private let accuracy = 1e-7

    private func check(_ value: Double, _ expected: JSON, _ what: @autoclosure () -> String, file: StaticString = #filePath, line: UInt = #line) {
        let e = expected.number
        XCTAssertFalse(e.isNaN, "missing \(what())", file: file, line: line)
        XCTAssertEqual(value, e, accuracy: self.accuracy * max(1.0, abs(e)), what(), file: file, line: line)
    }

    func testGoldenFrames() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "golden-depth", withExtension: "json"))
        let golden = try JSONDecoder().decode(JSON.self, from: Data(contentsOf: url))
        let scenarios = golden["scenarios"].array
        XCTAssertEqual(scenarios.count, 5)

        for scenario in scenarios {
            let name = scenario["name"].string
            let g = scenario["geometry"]
            let geometry = DepthSwipeGeometry(
                titleX: g["titleX"].number,
                titleOrigin: g["titleOrigin"].number,
                glyphCenters: g["glyphs"].array.map(\.number),
                iconCenters: g["icons"].array.map(\.number),
                textLeft: g["textLeft"].optionalNumber,
                lineCount: Int(g["lines"].number),
                avatarCenter: g["avatarCenter"].optionalNumber,
                avatarHalf: g["avatarHalf"].number
            )
            let rig = DepthSwipeRig(geometry: geometry)
            var tracker = DepthSwipeTracker()
            var gestureInitialOffset: Double?
            let samples = scenario["samples"].array
            var sampleIndex = 0
            var starts = 0
            var spins = 0
            var ends = 0

            for (index, f) in scenario["frames"].array.enumerated() {
                let now = f[0].number
                let x = f[1].number
                let where_ = "\(name) frame \(index)"
                // Input before the frame: a swipe begins / the finger lets go / the row is moved
                // (animated) / the full-swipe action arms.
                for call in f[6].array {
                    switch call[0].string {
                    case "swipe":
                        gestureInitialOffset = call[1].number
                        rig.begin(at: now)
                        starts += 1
                    case "release":
                        gestureInitialOffset = nil
                    case "set":
                        if DepthSwipeTracker.animatedMoveStarts(target: call[1].number, presented: call[2].number) {
                            rig.begin(at: now)
                            starts += 1
                        }
                    case "spin":
                        rig.spin(at: now, direction: Int(call[1].number))
                        spins += 1
                    default:
                        XCTFail("unknown call \(call[0].string) at \(where_)")
                    }
                }
                XCTAssertEqual(gestureInitialOffset != nil, f[4].bool, "tracking \(where_)")

                let v = tracker.frame(at: now, offset: x)
                self.check(v, f[2], "velocity \(where_)")
                let pull = DepthSwipeTracker.pull(offset: x, gestureInitialOffset: gestureInitialOffset)
                self.check(pull, f[3], "pull \(where_)")

                var ended = false
                if rig.isActive {
                    let moving = rig.update(at: now, offset: x, velocity: v, pull: pull)
                    let still = DepthSwipeTracker.isStill(isTracking: gestureInitialOffset != nil, isAnimating: f[5].bool, velocity: v)
                    if sampleIndex < samples.count, Int(samples[sampleIndex]["i"].number) == index {
                        self.compare(rig.frame, samples[sampleIndex], where_)
                        sampleIndex += 1
                    }
                    if DepthSwipeTracker.shouldEnd(isMoving: moving, isStill: still, isRolled: rig.isRolled) {
                        rig.end()
                        ended = true
                        ends += 1
                    }
                }
                XCTAssertEqual(ended, f[7].bool, "end \(where_)")
            }
            XCTAssertEqual(sampleIndex, samples.count, "\(name): samples replayed")
            XCTAssertGreaterThan(starts, 0, "\(name): starts")
            if name == "fullSwipe" {
                XCTAssertEqual(spins, 1, "\(name): one spin")
            }
            if name == "rightSwipe" {
                XCTAssertEqual(ends, 2, "\(name): flat after opening and after closing")
            }
        }
    }

    private func compare(_ frame: DepthSwipeFrame, _ s: JSON, _ where_: String) {
        XCTAssertEqual(frame.isMoving, s["moving"].bool, "moving \(where_)")
        XCTAssertEqual(frame.isRolled, s["rolled"].bool, "rolled \(where_)")
        XCTAssertEqual(frame.direction, Int(s["dir"].number), "direction \(where_)")
        XCTAssertEqual(s["linesOrigin"].string, frame.direction < 0 ? "0% 50%" : "", "lines' perspective origin \(where_)")

        let glyphs = s["glyphs"].array
        XCTAssertEqual(frame.glyphs.count, glyphs.count, "letters \(where_)")
        for (i, (glyph, e)) in zip(frame.glyphs, glyphs).enumerated() {
            let at = "letter \(i) \(where_)"
            self.check(glyph.roll, e[0], "roll \(at)")
            self.check(glyph.angle, e[1], "angle \(at)")
            self.check(glyph.lift, e[2], "lift \(at)")
            if e[3].isNull {
                XCTAssertNil(glyph.rim, "rim \(at)")
            } else if let rim = glyph.rim {
                self.check(rim.tx, e[3][0], "rim tx \(at)")
                self.check(rim.dz, e[3][1], "rim dz \(at)")
                self.check(rim.angle, e[3][2], "rim angle \(at)")
                self.check(rim.depthScale, e[3][3], "rim depth \(at)")
            } else {
                XCTFail("rim missing \(at)")
            }
            self.check(glyph.shade, e[4], "shade \(at)")
            self.check(glyph.faceOpacity, e[5], "face \(at)")
            self.check(glyph.layerOpacity, e[6], "extrusion \(at)")
            XCTAssertEqual(glyph.isHidden, e[7].bool, "hidden \(at)")
        }

        let icons = s["icons"].array
        XCTAssertEqual(frame.icons.count, icons.count, "badges \(where_)")
        for (i, (icon, e)) in zip(frame.icons, icons).enumerated() {
            let at = "badge \(i) \(where_)"
            if e.isNull {
                XCTAssertNil(icon, at)
            } else if let icon {
                self.check(icon.tx, e[0], "tx \(at)")
                self.check(icon.dz, e[1], "dz \(at)")
                self.check(icon.angle, e[2], "angle \(at)")
                self.check(icon.opacity, e[3], "opacity \(at)")
            } else {
                XCTFail("rim missing \(at)")
            }
        }

        if s["mask"].isNull {
            XCTAssertNil(frame.textMask, "text mask \(where_)")
        } else if let mask = frame.textMask {
            self.check(mask.start, s["mask"][0], "mask start \(where_)")
            self.check(mask.end, s["mask"][1], "mask end \(where_)")
        } else {
            XCTFail("text mask missing \(where_)")
        }

        let lines = s["lines"].array
        XCTAssertEqual(frame.lines.count, lines.count, "lines \(where_)")
        for (i, (line, e)) in zip(frame.lines, lines).enumerated() {
            self.check(line.lean, e[0], "lean line \(i) \(where_)")
            XCTAssertEqual(line.isFlat, e[1].bool, "flat line \(i) \(where_)")
        }

        let d = s["disc"]
        guard let disc = frame.disc else {
            XCTFail("disc missing \(where_)")
            return
        }
        self.check(disc.lean, d["lean"], "disc lean \(where_)")
        self.check(disc.angle, d["angle"], "disc angle \(where_)")
        self.check(disc.dx, d["dx"], "disc dx \(where_)")
        self.check(disc.z, d["z"], "disc z \(where_)")
        if d["origin"].isNull {
            XCTAssertNil(disc.perspectiveOriginX, "disc perspective origin \(where_)")
        } else if let origin = disc.perspectiveOriginX {
            self.check(origin, d["origin"], "disc perspective origin \(where_)")
        } else {
            XCTFail("disc perspective origin missing \(where_)")
        }
        self.check(disc.parallax, d["parallax"], "disc parallax \(where_)")
        self.check(disc.glint, d["glint"], "glint \(where_)")
        self.check(disc.glintOpacity, d["glintOpacity"], "glint opacity \(where_)")
        self.check(disc.dim, d["dim"], "dim \(where_)")
        self.check(disc.opacity, d["opacity"], "disc opacity \(where_)")
        XCTAssertEqual(disc.isHidden, d["hidden"].bool, "disc hidden \(where_)")
    }

    /// The spring itself against spring.js's closed form at a few hand-checked points.
    func testSpringMatchesClosedForm() {
        let spring = DepthSwipeSpring(response: 0.17, dampingFraction: 0.5)
        XCTAssertEqual(spring.stiffness, pow(2.0 * Double.pi / 0.17, 2.0), accuracy: 1e-9)
        XCTAssertEqual(spring.damping, 2.0 * 0.5 * spring.stiffness.squareRoot(), accuracy: 1e-9)
        let value = DepthSwipeSpringValue(0.0, spring: spring)
        value.epsilon = 0.02
        value.animate(to: 40.0, at: 0.0)
        XCTAssertEqual(value.update(at: 0.0), 0.0, accuracy: 1e-12)
        var t = 0.0
        while !value.isSettled && t < 2.0 {
            t += 1.0 / 120.0
            value.update(at: t)
        }
        XCTAssertTrue(value.isSettled)
        XCTAssertEqual(value.value, 40.0)
        XCTAssertLessThan(t, 0.6)
    }
}
