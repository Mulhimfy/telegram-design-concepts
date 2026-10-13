// GlassCoin interaction model.
//
// The collapsed profile avatar behaves like a two-sided glass coin on a spindle.
// Gesture constants are Telegram's own draggable coin (PremiumCoinComponent.swift):
//   · yaw follows the finger at 1 pt = 1°            (handlePan, deg2rad(translation.x))
//   · pitch is rubber-banded: range 60°, coefficient 0.4
//   · release under 90° and under 200 pt/s springs back, otherwise it turns over
//   · flicks over 600 pt/s "burst" (here: the coin is tossed and lifts higher)
// Springs are Telegram's: TouchEffect lift-on / lift-off (GlassBackgroundComponent),
// iOS 26 `.spring` (k 555.027, c 47.118) and the coin's own (m 1, k 21, c 5.8).
// What is new: the coin can turn over several faces, the landing face is chosen
// with UIScrollView's momentum projection (WWDC18 Fluid Interfaces), every face
// that passes edge-on ticks a haptic, and the two sides are the profile photo and its
// back (the profile emblem, or a back photo the user adds).
// The avatar lifts straight up (no tilt on press: every edge stays the same), and the
// glass starts dissolving during the last few degrees of a landing, so it is back to
// the flat photo about 0.4 s after a release.

import { SpringParams, SpringValue, project } from '../core/spring.js';
import { VelocityTracker } from '../core/velocity.js';

const PI = Math.PI;
const deg = PI / 180;

export const CoinConfig = {
  radius: 50,                    // pt, avatarSize / 2 (PeerInfoHeaderNode.swift:534)
  yawPerPoint: 1 * deg,          // PremiumCoinComponent: 1 pt = 1°
  pitchRange: 60,                // PremiumCoinComponent rubberBandingOffset range (°)
  pitchCoefficient: 0.4,         // … and coefficient
  pressYaw: 0,                   // PremiumCoinComponent tilts toward a tap (0.6 / 0.3 rad); an avatar lifts flat
  pressPitch: 0,
  pressDeadZone: 20,             // pt from the centre before a press tilts (same as the coin)
  dragSlop: 6,
  smallAngle: PI / 2,            // release under 90°…
  smallVelocity: 200,            // …and under 200 pt/s springs back
  tossVelocity: 600,             // pt/s: "explode" threshold → toss
  decelerationRate: 0.995,       // between UIScrollView .fast (0.99) and .normal (0.998): a swipe = one photo, a flick = several
  maxFaces: 9,                   // a single flick turns over at most this many faces
  translateFollow: 0.18,
  translateLimit: 12,

  // springs
  liftOn: new SpringParams(1.36, 568.0, 39.7),       // TouchEffect.swift lift-on   (ζ 0.71)
  uiSpring: new SpringParams(1.0, 555.027, 47.118),  // iOS 26 `.spring`             (ζ 1.0)
  coinSpring: new SpringParams(1.0, 21.0, 5.8),      // PremiumCoinComponent         (ζ 0.63)
  flipResponse: 0.40,                                // one face over: response…
  flipDamping: 0.80,                                 // …and damping (lands with ~1.5 % overshoot)
  backResponse: 0.34,                                // released before edge-on: back home
  backDamping: 0.82,
  settle: SpringParams.fromResponse(0.28, 0.9),      // lift, tilt and offset after a release
  glassOut: SpringParams.fromResponse(0.22, 1.0),    // glass → flat photo
  landAngle: 0.2,                                    // rad: land while approaching within ~11°…
  landVelocity: 5,                                   // …slower than this (rad/s)
  spinDamping: 0.8,
  settleDelay: 0,
  tossLift: 1.18,                                    // lift target while a tossed coin spins
};

export class GlassCoin {
  constructor({ photoCount = 1, back = 'emblem', config = {}, onTick, onLand, onFaceChange } = {}) {
    this.c = { ...CoinConfig, ...config };
    this.photoCount = photoCount;
    this.back = back;
    this.onTick = onTick || (() => {});
    this.onLand = onLand || (() => {});
    this.onFaceChange = onFaceChange || (() => {});
    const c = this.c;

    this.yaw = new SpringValue(0, c.uiSpring);
    this.pitch = new SpringValue(0, c.uiSpring);
    this.lift = new SpringValue(0, c.liftOn);   // scale/z: may overshoot (jelly)
    this.glass = new SpringValue(0, c.liftOn);  // material amount: never bounces through 0
    this.offsetX = new SpringValue(0, c.uiSpring);
    this.offsetY = new SpringValue(0, c.uiSpring);

    this.mode = 'idle';      // idle | pressed | dragging | released
    this.tracker = new VelocityTracker(0.08);
    this.startHalfTurn = 0;
    this.targetHalfTurn = 0;
    this.lastHalfTurn = 0;
    this.lastTickTime = 0;
    this.restTime = 0;
    this.lastNow = 0;
  }

  // Face index in front: 0 = current photo, +1 = next (swipe left), −1 = previous.
  faceAt(yaw) { return -Math.round(yaw / PI); }
  get face() { return this.faceAt(this.yaw.value); }

  contentForFace(f) {
    if (this.photoCount <= 1) return (((f % 2) + 2) % 2) === 0 ? 0 : this.back;
    return ((f % this.photoCount) + this.photoCount) % this.photoCount;
  }

  // The reverse side: 0 (the photo itself, the default: the same picture on both sides),
  // 'emblem' (profile colour + emoji) or the key of a back photo.
  setBack(key) { this.back = key; }

  // Content of the two physical sides of the card. A side only changes while it
  // faces away from the viewer, so nothing pops in view.
  sides() {
    const u = -this.yaw.value / PI;
    const evenFace = 2 * Math.round(u / 2);
    const oddFace = 2 * Math.floor(u / 2) + 1;
    return { a: this.contentForFace(evenFace), b: this.contentForFace(oddFace) };
  }

  hitTest(p) {
    return Math.hypot(p.x, p.y) <= this.c.radius + 10;
  }

  // p: pt relative to the coin centre, screen axes (y down).
  pointerDown(p, now) {
    this.update(now);
    const c = this.c;
    this.tracker.reset();
    this.tracker.add(now, p.x, p.y);
    this.downPoint = { x: p.x, y: p.y };
    if (this.mode === 'released' && (this.spin || Math.abs(this.yaw.velocity) > 3)) this.onTick('catch');
    this.spin = null;
    this.mode = 'pressed';
    this.restTime = 0;
    // Catch: freeze the current angle under the finger.
    this.yaw.set(this.yaw.value, now);
    this.startHalfTurn = Math.round(this.yaw.value / PI);
    this.baseYaw = this.yaw.value;
    // Press tilt toward the touch, like PremiumCoinComponent's tap (dead zone 20 pt).
    const tiltYaw = Math.abs(p.x) > c.pressDeadZone ? Math.sign(p.x) * c.pressYaw * Math.min(1, Math.abs(p.x) / c.radius) : 0;
    const tiltPitch = Math.abs(p.y) > c.pressDeadZone ? Math.sign(p.y) * c.pressPitch * Math.min(1, Math.abs(p.y) / c.radius) : 0;
    this.yaw.animate(this.baseYaw + tiltYaw, now, { params: c.liftOn });
    this.pitch.animate(tiltPitch, now, { params: c.liftOn });
    this.lift.animate(1, now, { params: c.liftOn });
    this.glass.animate(1, now, { params: c.liftOn });
  }

  pointerMove(p, now) {
    if (this.mode !== 'pressed' && this.mode !== 'dragging') return;
    this.update(now);
    const c = this.c;
    this.tracker.add(now, p.x, p.y);
    const dx = p.x - this.downPoint.x;
    const dy = p.y - this.downPoint.y;
    if (this.mode === 'pressed' && Math.hypot(dx, dy) > c.dragSlop) {
      this.mode = 'dragging';
      this.dragOrigin = { x: p.x, y: p.y };
      this.dragYaw0 = this.yaw.value;
      this.dragPitch0 = this.pitch.value;
    }
    if (this.mode !== 'dragging') return;
    const tx = p.x - this.dragOrigin.x;
    const ty = p.y - this.dragOrigin.y;
    // Direct manipulation: angles track the finger (a 60 ms follow spring smooths
    // 60 Hz touch sampling without adding perceptible lag).
    const follow = SpringParams.fromResponse(0.06, 1.0);
    this.yaw.animate(this.dragYaw0 + tx * c.yawPerPoint, now, { params: follow });
    const band = (o) => (1 - 1 / ((Math.abs(o) * c.pitchCoefficient) / c.pitchRange + 1)) * c.pitchRange * Math.sign(o);
    this.pitch.animate(this.dragPitch0 + band(ty) * deg, now, { params: follow });
    const rb = (v) => (1 - 1 / ((Math.abs(v) * 0.55) / c.translateLimit + 1)) * c.translateLimit * Math.sign(v);
    this.offsetX.animate(rb((p.x - this.downPoint.x) * c.translateFollow), now, { params: follow });
    this.offsetY.animate(rb((p.y - this.downPoint.y) * c.translateFollow), now, { params: follow });
  }

  pointerUp(p, now) {
    if (this.mode !== 'pressed' && this.mode !== 'dragging') return { tap: false };
    this.update(now);
    const wasTap = this.mode === 'pressed';
    const v = wasTap ? { x: 0, y: 0 } : this.tracker.velocity(now);
    this.release(v.x, now);
    return { tap: wasTap };
  }

  cancel(now) {
    if (this.mode === 'pressed' || this.mode === 'dragging') this.release(0, now);
  }

  // Release with a horizontal finger velocity (pt/s).
  release(vx, now) {
    const c = this.c;
    const yaw = this.yaw.value;
    const w0 = vx * c.yawPerPoint;
    const startAngle = this.startHalfTurn * PI;
    let target;
    if (Math.abs(yaw - startAngle) < c.smallAngle && Math.abs(vx) < c.smallVelocity) {
      target = this.startHalfTurn;                                   // spring back
    } else if (Math.abs(vx) < c.smallVelocity) {
      target = Math.round(yaw / PI);                                 // tipped past edge-on: complete the turn
    } else {
      const projected = yaw + project(vx, c.decelerationRate) * c.yawPerPoint;
      target = Math.round(projected / PI);
      const dir = Math.sign(w0);
      if ((target - this.startHalfTurn) * dir <= 0) target = this.startHalfTurn + dir; // a flick always turns it over
      const limit = this.startHalfTurn + dir * c.maxFaces;
      if ((target - limit) * dir > 0) target = limit;
    }
    const targetAngle = target * PI;
    const distance = Math.abs(targetAngle - yaw);
    let params;
    this.spin = null;
    if (distance > 1.25 * PI && Math.abs(w0) > 1) {
      // Several faces: constant friction (a coin spinning down), landing exactly on the
      // chosen face; the last half-turn is handed to the flip spring for a real landing.
      const dir = Math.sign(targetAngle - yaw);
      const w = Math.abs(w0);
      const a = (w * w) / (2 * distance);
      this.spin = { t0: now, theta0: yaw, dir, w0: w, a, T: w / a, target: targetAngle, handoff: 0.55 * PI };
      params = null;
    } else if (target === this.startHalfTurn) {
      params = SpringParams.fromResponse(c.backResponse, c.backDamping);
    } else {
      params = SpringParams.fromResponse(c.flipResponse, c.flipDamping);
    }
    if (params) this.yaw.animate(targetAngle, now, { params, velocity: w0 });
    else this.yaw.set(yaw, now);
    this.pitch.animate(0, now, { params: c.settle });
    this.offsetX.animate(0, now, { params: c.settle });
    this.offsetY.animate(0, now, { params: c.settle });
    this.tossed = Math.abs(vx) > c.tossVelocity && distance > 0.5 * PI;
    if (this.tossed) this.lift.animate(c.tossLift, now, { params: SpringParams.fromResponse(0.35, 0.9) });
    this.targetHalfTurn = target;
    this.mode = 'released';
    this.restTime = 0;
  }

  // Shows `face` at rest without animation (Reduce Motion) — GlassCoinModel.jump(toFace:at:).
  jumpToFace(face, now) {
    this.update(now);
    this.spin = null;
    const angle = -face * PI;
    this.yaw.set(angle, now);
    this.pitch.set(0, now);
    this.lift.set(0, now);
    this.glass.set(0, now);
    this.offsetX.set(0, now);
    this.offsetY.set(0, now);
    this.lastHalfTurn = Math.round(angle / PI);
    this.startHalfTurn = this.lastHalfTurn;
    this.targetHalfTurn = this.lastHalfTurn;
    this.mode = 'idle';
  }

  // Turns over by `n` faces on its own (showing a new back photo): lifts into glass, turns
  // on the flip spring and lands like a released coin.
  turnBy(n, now) {
    this.update(now);
    const c = this.c;
    this.spin = null;
    this.startHalfTurn = Math.round(this.yaw.value / PI);
    this.targetHalfTurn = this.startHalfTurn - n;
    this.lift.animate(1, now, { params: c.liftOn });
    this.glass.animate(1, now, { params: c.liftOn });
    this.yaw.animate(this.targetHalfTurn * PI, now, { params: SpringParams.fromResponse(c.flipResponse * (n > 1 ? 1.3 : 1), c.flipDamping) });
    this.pitch.animate(0, now, { params: c.settle });
    this.offsetX.animate(0, now, { params: c.settle });
    this.offsetY.animate(0, now, { params: c.settle });
    this.tossed = false;
    this.mode = 'released';
    this.restTime = 0;
  }

  // A short lift into glass and back, without turning (a colour change).
  pulse(now, hold = 0.3) {
    this.update(now);
    if (this.mode !== 'idle') return;
    this.mode = 'pulse';
    this.pulseEnd = now + hold;
    this.lift.animate(1, now, { params: this.c.liftOn });
    this.glass.animate(1, now, { params: this.c.liftOn });
  }

  // Programmatic flick (demo, VoiceOver adjustable action): velocity in pt/s.
  flick(vx, now) {
    this.update(now);
    this.startHalfTurn = Math.round(this.yaw.value / PI);
    this.lift.animate(1, now, { params: this.c.liftOn });
    this.glass.animate(1, now, { params: this.c.liftOn });
    this.release(vx, now);
  }

  update(now) {
    const dt = this.lastNow ? Math.max(0, now - this.lastNow) : 0;
    this.lastNow = now;
    const c = this.c;
    if (this.spin) {
      const sp = this.spin;
      const t = Math.min(now - sp.t0, sp.T);
      const theta = sp.theta0 + sp.dir * (sp.w0 * t - 0.5 * sp.a * t * t);
      const w = sp.dir * (sp.w0 - sp.a * t);
      this.spinVelocity = w;
      if ((sp.target - theta) * sp.dir <= sp.handoff || t >= sp.T) {
        this.spin = null;
        this.yaw.set(theta, now);
        this.yaw.animate(sp.target, now, { params: SpringParams.fromResponse(c.flipResponse, c.flipDamping), velocity: w });
      } else {
        this.yaw.set(theta, now);
      }
    }
    const yaw = this.yaw.update(now);
    this.pitch.update(now);
    this.lift.update(now);
    this.glass.update(now);
    this.offsetX.update(now);
    this.offsetY.update(now);

    // Detent tick each time a new face swings past edge-on.
    const half = Math.round(yaw / PI);
    if (half !== this.lastHalfTurn) {
      this.lastHalfTurn = half;
      if (now - this.lastTickTime > 0.045) {
        this.lastTickTime = now;
        this.onTick('face');
      }
      this.onFaceChange(this.faceAt(yaw));
    }

    if (this.mode === 'pulse' && now >= this.pulseEnd) {
      this.mode = 'idle';
      this.lift.animate(0, now, { params: c.settle });
      this.glass.animate(0, now, { params: c.glassOut });
    }

    if (this.mode === 'released') {
      // A tossed coin comes back down for the last half-turn.
      if (this.tossed && Math.abs(this.targetHalfTurn * PI - yaw) < 0.9 * PI && this.lift.target !== 1) {
        this.lift.animate(1, now, { params: c.settle });
      }
      // Land while the coin makes its last few degrees toward the face (or once it is
      // at rest): the glass dissolves over the end of the motion instead of after it.
      const err = this.targetHalfTurn * PI - yaw;
      const vel = this.yaw.velocity;
      const atRest = Math.abs(err) < 0.035 && Math.abs(vel) < 0.6;
      const arriving = Math.abs(err) < c.landAngle && err * vel >= 0 && Math.abs(vel) < c.landVelocity;
      if (!this.spin && Math.abs(this.pitch.value) < 0.08 && (atRest || arriving)) {
        this.restTime += dt;
        if (this.restTime >= c.settleDelay) {
          this.mode = 'idle';
          this.lift.animate(0, now, { params: c.settle });
          this.glass.animate(0, now, { params: c.glassOut });
          this.onLand(this.targetHalfTurn !== this.startHalfTurn, this.faceAt(this.targetHalfTurn * PI));
        }
      } else {
        this.restTime = 0;
      }
    }
  }

  state(now) {
    this.update(now);
    const sides = this.sides();
    return {
      yaw: this.yaw.value,
      pitch: this.pitch.value,
      lift: this.lift.value,
      glass: Math.max(0, Math.min(1, this.glass.value)),
      offsetX: this.offsetX.value,
      offsetY: this.offsetY.value,
      sideA: sides.a,
      sideB: sides.b,
      face: this.face,
      mode: this.mode,
      yawVelocity: this.spin ? this.spinVelocity : this.yaw.velocity,
    };
  }

  get isAnimating() {
    return !!this.spin || this.mode !== 'idle' || !this.lift.settled || !this.glass.settled || !this.pitch.settled || !this.yaw.settled || !this.offsetX.settled || !this.offsetY.settled;
  }
}
