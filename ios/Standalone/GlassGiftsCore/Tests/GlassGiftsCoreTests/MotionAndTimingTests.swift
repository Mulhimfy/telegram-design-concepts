import XCTest
import Foundation
@testable import GlassGiftsCore

/// The native-only pieces around the model: the gyroscope integration that feeds the filter, the screen rotation of
/// the light, and the ease-out of the context gesture's press shrink.
final class MotionAndTimingTests: XCTestCase {
    func testIntegratorFollowsTheRotationRate() {
        var integrator = GlassGiftRotationIntegrator()
        // The first sample only sets the clock.
        XCTAssertEqual(integrator.add(rateX: 3.0, rateY: -3.0, timestamp: 100.0), 0.0)
        XCTAssertEqual(integrator.beta, 0.0)
        XCTAssertEqual(integrator.gamma, 0.0)
        // 0.5 rad/s about x and −0.25 rad/s about y for one second at 60 Hz.
        var timestamp = 100.0
        for _ in 0 ..< 60 {
            timestamp += 1.0 / 60.0
            _ = integrator.add(rateX: 0.5, rateY: -0.25, timestamp: timestamp)
        }
        XCTAssertEqual(integrator.beta, 0.5 * 180.0 / Double.pi, accuracy: 1e-9)
        XCTAssertEqual(integrator.gamma, -0.25 * 180.0 / Double.pi, accuracy: 1e-9)
    }

    func testIntegratorCapsGaps() {
        var integrator = GlassGiftRotationIntegrator()
        _ = integrator.add(rateX: 0.0, rateY: 0.0, timestamp: 5.0)
        // A 3 s gap (the sensor was paused) counts as 0.1 s; time going backwards as none.
        XCTAssertEqual(integrator.add(rateX: 1.0, rateY: 0.0, timestamp: 8.0), GlassGiftRotationIntegrator.maxStep)
        XCTAssertEqual(integrator.beta, GlassGiftRotationIntegrator.maxStep * 180.0 / Double.pi, accuracy: 1e-9)
        XCTAssertEqual(integrator.add(rateX: 1.0, rateY: 0.0, timestamp: 7.0), 0.0)
        integrator.reset()
        XCTAssertEqual(integrator.beta, 0.0)
        XCTAssertEqual(integrator.add(rateX: 1.0, rateY: 1.0, timestamp: 9.0), 0.0)
    }

    func testFirstReadingIsTheReference() {
        var filter = GlassGiftMotionFilter()
        XCTAssertNil(filter.update(dt: 1.0 / 60.0))
        XCTAssertFalse(filter.hasReading)
        filter.feed(beta: 45.0, gamma: -10.0)
        XCTAssertTrue(filter.hasReading)
        let value = filter.update(dt: 1.0 / 60.0)
        XCTAssertEqual(value, GlassGiftLight(x: 0.0, y: 0.0))
        filter.reset()
        XCTAssertNil(filter.update(dt: 1.0 / 60.0))
    }

    func testScreenRotationKeepsTheLightOnScreen() {
        let light = GlassGiftLight(x: 3.0, y: -7.0)
        XCTAssertEqual(GlassGiftScreenRotation.portrait.apply(light), light)
        XCTAssertEqual(GlassGiftScreenRotation.portraitUpsideDown.apply(GlassGiftScreenRotation.portraitUpsideDown.apply(light)), light)
        // Turning the phone one way and then back is no turn.
        XCTAssertEqual(GlassGiftScreenRotation.landscapeRight.apply(GlassGiftScreenRotation.landscapeLeft.apply(light)), light)
        // Two quarter turns the same way are a half turn.
        XCTAssertEqual(GlassGiftScreenRotation.landscapeLeft.apply(GlassGiftScreenRotation.landscapeLeft.apply(light)), GlassGiftScreenRotation.portraitUpsideDown.apply(light))
        // Home button on the left: the device's top edge points right, so a tilt that moves the light toward the
        // device's bottom edge (+y) moves it to the screen's left.
        XCTAssertEqual(GlassGiftScreenRotation.landscapeLeft.apply(GlassGiftLight(x: 0.0, y: 1.0)), GlassGiftLight(x: -1.0, y: 0.0))
    }

    func testEaseOutIsCoreAnimationsCurve() {
        XCTAssertEqual(GlassGiftTiming.easeOut(0.0), 0.0, accuracy: 1e-9)
        XCTAssertEqual(GlassGiftTiming.easeOut(1.0), 1.0, accuracy: 1e-9)
        XCTAssertEqual(GlassGiftTiming.easeOut(-1.0), 0.0, accuracy: 1e-9)
        XCTAssertEqual(GlassGiftTiming.easeOut(2.0), 1.0, accuracy: 1e-9)
        // Points of the Bézier (0, 0) (0, 0) (0.58, 1) (1, 1), taken straight from its parametric form.
        for s in stride(from: 0.05, to: 1.0, by: 0.05) {
            let x = 3.0 * (1.0 - s) * s * s * 0.58 + s * s * s
            let y = 3.0 * (1.0 - s) * s * s + s * s * s
            XCTAssertEqual(GlassGiftTiming.easeOut(x), y, accuracy: 1e-7, "s = \(s)")
        }
        var previous = 0.0
        for i in 1 ... 100 {
            let value = GlassGiftTiming.easeOut(Double(i) / 100.0)
            XCTAssertGreaterThanOrEqual(value, previous)
            previous = value
        }
    }

    func testTileComesToRest() {
        // A tap: lean, release, ease home. Within 3 s nothing moves any more, and the burst is over.
        let model = GlassTileModel()
        model.aim(u: 0.7, v: -0.4)
        model.burst(at: 0.0)
        var now = 0.0
        var state = model.update(now: now, dt: 1.0 / 60.0, light: nil)
        XCTAssertTrue(state.isActive)
        model.release()
        while now < 3.0 {
            now += 1.0 / 60.0
            state = model.update(now: now, dt: 1.0 / 60.0, light: nil)
        }
        XCTAssertFalse(state.isActive)
        XCTAssertNil(state.shards)
        XCTAssertNil(model.burstStart)
        XCTAssertEqual(state.yaw, 0.0, accuracy: 0.01)
        XCTAssertEqual(state.pitch, 0.0, accuracy: 0.01)
        XCTAssertEqual(state.scale, 1.0, accuracy: 1e-4)
        // The lean never goes past the limits, however far the finger is.
        model.aim(u: 5.0, v: -5.0)
        for _ in 0 ..< 600 {
            now += 1.0 / 60.0
            state = model.update(now: now, dt: 1.0 / 60.0, light: GlassGiftLight(x: 40.0, y: -40.0))
            XCTAssertLessThanOrEqual(abs(model.yaw), GlassGiftLook.maxYaw + 1e-9)
            XCTAssertLessThanOrEqual(abs(model.pitch), GlassGiftLook.maxPitch + 1e-9)
            XCTAssertLessThanOrEqual(abs(state.yaw), GlassGiftLook.maxYaw + GlassGiftLook.motionLean + 1e-9)
        }
    }
}
