import XCTest
import Foundation
@testable import GlassCoinCore

/// Replays the gestures and calls recorded from the web prototype (tools/golden.mjs) through the Swift model
/// and requires the same trajectory, the same haptic ticks, the same faces passing and the same landings.
final class GoldenTests: XCTestCase {
    private enum InputValue: Decodable {
        case string(String)
        case number(Double)

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
            return 0.0
        }

        var string: String {
            if case let .string(value) = self {
                return value
            }
            return ""
        }
    }

    private struct Sample: Decodable {
        let t: Double
        let yaw: Double
        let pitch: Double
        let lift: Double
        let glass: Double
        let offsetX: Double
        let offsetY: Double
        let face: Int
        let sideA: String
        let sideB: String
        let mode: String
    }

    private struct Land: Decodable, Equatable {
        let changed: Bool
        let face: Int
    }

    private struct Scenario: Decodable {
        let name: String
        let photoCount: Int
        /// The reverse at the start: "0" (the photo itself), "emblem" or "back".
        let back: String
        let input: [[InputValue]]
        let samples: [Sample]
        let ticks: Int
        let lands: [Land]
        /// `onFaceChange` in order.
        let faces: [Int]
    }

    private struct Golden: Decodable {
        let version: Int
        let scenarios: [Scenario]
    }

    private func describe(_ content: GlassCoinFaceContent) -> String {
        switch content {
        case let .photo(index):
            return "\(index)"
        case .emblem:
            return "emblem"
        case .backPhoto:
            return "back"
        }
    }

    /// tools/golden.mjs `backKey`: "0" is the photo itself.
    private func content(_ key: String) -> GlassCoinFaceContent {
        switch key {
        case "emblem":
            return .emblem
        case "back":
            return .backPhoto
        default:
            return .photo(Int(key) ?? 0)
        }
    }

    private func describe(_ mode: GlassCoinModel.Mode) -> String {
        switch mode {
        case .idle:
            return "idle"
        case .pressed:
            return "pressed"
        case .dragging:
            return "dragging"
        case .released:
            return "released"
        case .pulse:
            return "pulse"
        }
    }

    func testGoldenTrajectories() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "golden", withExtension: "json"))
        let golden = try JSONDecoder().decode(Golden.self, from: Data(contentsOf: url))
        XCTAssertFalse(golden.scenarios.isEmpty)

        for scenario in golden.scenarios {
            let model = GlassCoinModel(photoCount: scenario.photoCount)
            model.back = self.content(scenario.back)
            var ticks = 0
            var lands: [Land] = []
            var faces: [Int] = []
            // app.js chooseBack with the back in view: the new back is set once the front is in view.
            var pendingBack: GlassCoinFaceContent?
            model.onTick = { _ in
                ticks += 1
            }
            model.onLand = { changed, face in
                lands.append(Land(changed: changed, face: face))
            }
            model.onFaceChange = { [unowned model] face in
                faces.append(face)
                if let back = pendingBack, abs(face) % 2 == 0 {
                    model.back = back
                    pendingBack = nil
                }
            }
            let t0 = 10.0
            let events = scenario.input.map { values -> (type: String, t: Double, a: InputValue, b: InputValue) in
                return (values[0].string, t0 + values[1].number, values[2], values[3])
            }
            let end = t0 + (events.map { $0.t - t0 }.max() ?? 0.0) + 3.0
            var eventIndex = 0
            var sampleIndex = 0
            var t = t0
            while t <= end + 1e-9 {
                while eventIndex < events.count && events[eventIndex].t <= t + 1e-9 {
                    let event = events[eventIndex]
                    eventIndex += 1
                    let point = CGPoint(x: event.a.number, y: event.b.number)
                    switch event.type {
                    case "down":
                        model.pointerDown(point, at: event.t)
                    case "move":
                        model.pointerMove(point, at: event.t)
                    case "up":
                        model.pointerUp(point, at: event.t)
                    case "turnBy":
                        model.turnBy(Int(event.a.number), at: event.t)
                    case "pulse":
                        model.pulse(at: event.t, hold: event.a.number)
                    case "jump":
                        model.jump(toFace: Int(event.a.number), at: event.t)
                    case "back":
                        model.back = self.content(event.a.string)
                    case "pendingBack":
                        pendingBack = self.content(event.a.string)
                    default:
                        XCTFail("\(scenario.name): unknown event \(event.type)")
                    }
                }
                let state = model.state(at: t)
                if Int(((t - t0) * 120.0).rounded()) % 6 == 0 {
                    XCTAssertLessThan(sampleIndex, scenario.samples.count, "\(scenario.name): more samples than recorded")
                    if sampleIndex < scenario.samples.count {
                        let expected = scenario.samples[sampleIndex]
                        let where_ = "\(scenario.name) @\(expected.t)s"
                        XCTAssertEqual(state.yaw, expected.yaw, accuracy: 1e-6, "yaw \(where_)")
                        XCTAssertEqual(state.pitch, expected.pitch, accuracy: 1e-6, "pitch \(where_)")
                        XCTAssertEqual(state.lift, expected.lift, accuracy: 1e-6, "lift \(where_)")
                        XCTAssertEqual(state.glass, expected.glass, accuracy: 1e-6, "glass \(where_)")
                        XCTAssertEqual(Double(state.offset.x), expected.offsetX, accuracy: 1e-6, "offsetX \(where_)")
                        XCTAssertEqual(Double(state.offset.y), expected.offsetY, accuracy: 1e-6, "offsetY \(where_)")
                        XCTAssertEqual(state.face == 0 ? 0 : state.face, expected.face, "face \(where_)")
                        XCTAssertEqual(self.describe(state.sideA), expected.sideA, "sideA \(where_)")
                        XCTAssertEqual(self.describe(state.sideB), expected.sideB, "sideB \(where_)")
                        XCTAssertEqual(self.describe(model.mode), expected.mode, "mode \(where_)")
                    }
                    sampleIndex += 1
                }
                t = ((t + 1.0 / 120.0) * 1e6).rounded() / 1e6
            }
            XCTAssertEqual(sampleIndex, scenario.samples.count, "\(scenario.name): sample count")
            XCTAssertEqual(ticks, scenario.ticks, "\(scenario.name): haptic ticks")
            XCTAssertEqual(lands, scenario.lands, "\(scenario.name): landings")
            XCTAssertEqual(faces, scenario.faces, "\(scenario.name): faces passing")
        }
    }
}
