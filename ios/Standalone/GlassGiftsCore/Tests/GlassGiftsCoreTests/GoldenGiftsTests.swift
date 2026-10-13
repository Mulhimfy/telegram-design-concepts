import XCTest
import Foundation
@testable import GlassGiftsCore

/// Replays the frames recorded from the web prototype (tools/golden-gifts.mjs → Resources/golden-gifts.json) through
/// the Swift model and requires the same values, frame by frame: every number `GlassTile.update` writes (the tile's
/// transform, sheen, prismatic streak, rim, gift slide, shadow, shards and sparkles, and whether it still moves), and
/// every value `MotionSource.update` returns.
final class GoldenGiftsTests: XCTestCase {
    /// The recording keeps 8 decimals.
    private static let tolerance = 1e-6

    private enum Value: Decodable {
        case number(Double)
        case string(String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Double.self) {
                self = .number(value)
            } else {
                self = .string(try container.decode(String.self))
            }
        }

        var number: Double {
            if case let .number(value) = self {
                return value
            }
            return .nan
        }

        var string: String {
            if case let .string(value) = self {
                return value
            }
            return ""
        }
    }

    private struct Look: Decodable {
        struct Depth: Decodable {
            let gift: Double
            let ribbon: Double
            let badge: Double
        }

        let maxYaw: Double
        let maxPitch: Double
        let motionLean: Double
        let held: Double
        let depth: Depth
        let perspective: Double
    }

    private struct TileOutput: Decodable {
        /// active, translateX, translateY, scale, pitch, yaw, roll, sheen x/y/opacity, holo x/y/opacity, rim angle,
        /// gift x/y, shadow x/y/scale/opacity.
        let o: [Double]
        /// 3 shards × (opacity, translateX %, rotate) + 4 sparkles × (opacity, scale, rotate), while a burst writes.
        let b: [Double]?
    }

    private struct TileStep: Decodable {
        let act: [[Value]]?
        let light: [Double]?
        let out: [TileOutput]
    }

    private struct TileScenario: Decodable {
        let name: String
        let tiles: Int
        let dts: [Double]
        let steps: [TileStep]
    }

    private enum MotionSet: Decodable {
        case value(GlassGiftLight)
        case clear

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode([Double].self), value.count == 2 {
                self = .value(GlassGiftLight(x: value[0], y: value[1]))
            } else if try container.decode(String.self) == "clear" {
                self = .clear
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "set")
            }
        }
    }

    private struct MotionStep: Decodable {
        let feed: [Double]?
        let set: MotionSet?
        let out: [Double]?
    }

    private struct MotionScenario: Decodable {
        let name: String
        let dts: [Double]
        let steps: [MotionStep]
    }

    private struct Golden: Decodable {
        let version: Int
        let t0: Double
        let look: Look
        let tileScenarios: [TileScenario]
        let motionScenarios: [MotionScenario]
    }

    private func loadGolden() throws -> Golden {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "golden-gifts", withExtension: "json"))
        return try JSONDecoder().decode(Golden.self, from: Data(contentsOf: url))
    }

    func testLookMatchesPrototype() throws {
        let look = try self.loadGolden().look
        XCTAssertEqual(GlassGiftLook.maxYaw, look.maxYaw)
        XCTAssertEqual(GlassGiftLook.maxPitch, look.maxPitch)
        XCTAssertEqual(GlassGiftLook.motionLean, look.motionLean)
        XCTAssertEqual(GlassGiftLook.held, look.held)
        XCTAssertEqual(GlassGiftLook.giftDepth, look.depth.gift)
        XCTAssertEqual(GlassGiftLook.ribbonDepth, look.depth.ribbon)
        XCTAssertEqual(GlassGiftLook.badgeDepth, look.depth.badge)
        XCTAssertEqual(GlassGiftLook.perspective, look.perspective)
    }

    func testTileFrames() throws {
        let golden = try self.loadGolden()
        XCTAssertFalse(golden.tileScenarios.isEmpty)
        let names = ["active", "translateX", "translateY", "scale", "pitch", "yaw", "roll", "sheenX", "sheenY", "sheenOpacity", "holoX", "holoY", "holoOpacity", "rimAngle", "giftX", "giftY", "shadowX", "shadowY", "shadowScale", "shadowOpacity"]
        var frames = 0
        var bursts = 0

        for scenario in golden.tileScenarios {
            let models = (0 ..< scenario.tiles).map { _ in GlassTileModel() }
            var elapsed = 0.0
            for (index, step) in scenario.steps.enumerated() {
                // The recorder's clock: step 0 at t0 with one 60 Hz frame, then the scenario's frame times.
                let dt = scenario.dts[index % scenario.dts.count]
                if index > 0 {
                    elapsed += dt
                }
                let now = golden.t0 + elapsed
                for action in step.act ?? [] {
                    let model = models[Int(action[0].number)]
                    switch action[1].string {
                    case "aim":
                        model.aim(u: action[2].number, v: action[3].number)
                    case "burst":
                        model.burst(at: now)
                    case "release":
                        model.release()
                    default:
                        XCTFail("\(scenario.name): unknown action \(action[1].string)")
                    }
                }
                let light = step.light.map { GlassGiftLight(x: $0[0], y: $0[1]) }
                XCTAssertEqual(step.out.count, models.count)

                for (tileIndex, model) in models.enumerated() {
                    let state = model.update(now: now, dt: index == 0 ? 1.0 / 60.0 : dt, light: light)
                    let expected = step.out[tileIndex]
                    let actual: [Double] = [
                        state.isActive ? 1.0 : 0.0,
                        state.translationX, state.translationY, state.scale, state.pitch, state.yaw, state.roll,
                        state.sheenX, state.sheenY, state.sheenOpacity,
                        state.holoX, state.holoY, state.holoOpacity,
                        state.rimAngle,
                        state.giftX, state.giftY,
                        state.shadowX, state.shadowY, state.shadowScale, state.shadowOpacity
                    ]
                    let place = "\(scenario.name) step \(index) tile \(tileIndex)"
                    XCTAssertEqual(expected.o.count, actual.count, place)
                    for (i, (a, e)) in zip(actual, expected.o).enumerated() {
                        XCTAssertEqual(a, e, accuracy: GoldenGiftsTests.tolerance, "\(names[i]) \(place)")
                    }

                    // Shards and sparkles exactly when the prototype writes them.
                    XCTAssertEqual(state.shards != nil, expected.b != nil, "burst written \(place)")
                    XCTAssertEqual(state.sparkles != nil, expected.b != nil, "burst written \(place)")
                    if let shards = state.shards, let sparkles = state.sparkles, let b = expected.b {
                        var values: [Double] = []
                        for shard in shards {
                            values += [shard.opacity, shard.translation, shard.rotation]
                        }
                        for sparkle in sparkles {
                            values += [sparkle.opacity, sparkle.scale, sparkle.rotation]
                        }
                        XCTAssertEqual(values.count, b.count, place)
                        for (i, (a, e)) in zip(values, b).enumerated() {
                            XCTAssertEqual(a, e, accuracy: GoldenGiftsTests.tolerance, "burst[\(i)] \(place)")
                        }
                        bursts += 1
                    }
                    frames += 1
                }
            }
        }
        XCTAssertGreaterThan(frames, 1000)
        XCTAssertGreaterThan(bursts, 200)
    }

    func testMotionFilter() throws {
        let golden = try self.loadGolden()
        XCTAssertFalse(golden.motionScenarios.isEmpty)
        for scenario in golden.motionScenarios {
            var filter = GlassGiftMotionFilter()
            for (index, step) in scenario.steps.enumerated() {
                let dt = scenario.dts[index % scenario.dts.count]
                if let feed = step.feed {
                    filter.feed(beta: feed[0], gamma: feed[1])
                }
                switch step.set {
                case let .value(value):
                    filter.override = value
                case .clear:
                    filter.override = nil
                case .none:
                    break
                }
                let value = filter.update(dt: dt)
                let place = "\(scenario.name) step \(index)"
                if let expected = step.out {
                    guard let value else {
                        XCTFail("no value \(place)")
                        continue
                    }
                    XCTAssertEqual(value.x, expected[0], accuracy: GoldenGiftsTests.tolerance, "x \(place)")
                    XCTAssertEqual(value.y, expected[1], accuracy: GoldenGiftsTests.tolerance, "y \(place)")
                } else {
                    XCTAssertNil(value, place)
                }
            }
        }
    }
}
