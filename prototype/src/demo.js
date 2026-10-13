// Scripted, frame-exact demo playback for video recording. The finger goes through the
// same input paths as real touches (router.inject: the Settings router, the chat list or a
// pushed page, whichever has the screen), so the video shows the real interaction model.
//
// Two clocks: the page's (every animation, the finger) and the video's. They run together
// except in slow motion, where the page runs at `rate` of the video's speed.
//
// Script entries — `t` in page seconds; points in screen pt, or functions returning them
// (resolved when the event fires):
//   { t, camera: { zoom, focus:[x,y], anchor:[px,py], tilt:[rx,ry] }, duration }  camera (video s)
//   { t, down: [x,y] }                                                 finger down
//   { t, drag: [[x,y], …], duration, ease: 'inOut'|'out'|'in'|'linear' } — move through points
//   { t, up: true }                                                    finger up
//   { t, tap: [x,y], hold }                                            a tap (down, up after `hold` s)
//   { t, rate: 0.25, ramp: 0.25 }                                      play speed from here (ramp: video s)
//   { t, caption: 'text' | null }                                      caption under the phone
//   { t, tag: 'html' }                                                 corner label (Before / After)
//   { t, call: (ctx) => {} }                                           anything else

import { easeInOutCubic } from './stage.js';

const eases = {
  linear: (u) => u,
  inOut: easeInOutCubic,
  out: (u) => 1 - Math.pow(1 - u, 3),
  in: (u) => u * u * u,
  outQuad: (u) => 1 - (1 - u) * (1 - u),
  inOutSine: (u) => 0.5 - 0.5 * Math.cos(Math.PI * u),
};

function catmull(points, u) {
  // Smooth path through the waypoints (Catmull-Rom, uniform).
  if (points.length === 1) return points[0];
  const n = points.length - 1;
  const f = Math.min(n - 1e-9, u * n);
  const i = Math.floor(f);
  const t = f - i;
  const p0 = points[Math.max(0, i - 1)];
  const p1 = points[i];
  const p2 = points[Math.min(n, i + 1)];
  const p3 = points[Math.min(n, i + 2)];
  const c = (a, b, c2, d) => 0.5 * ((2 * b) + (-a + c2) * t + (2 * a - 5 * b + 4 * c2 - d) * t * t + (-a + 3 * b - 3 * c2 + d) * t * t * t);
  return [c(p0[0], p1[0], p2[0], p3[0]), c(p0[1], p1[1], p2[1], p3[1])];
}

const resolve = (v) => (typeof v === 'function' ? v() : v);

// The play speed: eases toward each new rate over `ramp` video seconds (smoothstep).
class Rate {
  constructor() { this.value = 1; this.from = 1; this.to = 1; this.ramp = 0; this.u = 1; }
  set(to, ramp) { this.from = this.value; this.to = to; this.ramp = ramp; this.u = ramp > 0 ? 0 : 1; if (!(ramp > 0)) this.value = to; }
  step(dt) {
    if (this.u < 1) {
      this.u = Math.min(1, this.u + dt / this.ramp);
      const e = this.u * this.u * (3 - 2 * this.u);
      this.value = this.from + (this.to - this.from) * e;
    }
    return this.value;
  }
}

export class Demo {
  constructor({ script, clock, stage, router, render }) {
    // Taps expand into a down and an up.
    const expanded = [];
    for (const e of script) {
      if (e.tap) {
        expanded.push({ t: e.t, down: e.tap });
        expanded.push({ t: e.t + (e.hold ?? 0.09), up: true });
      } else {
        expanded.push(e);
      }
    }
    // Stable sort: events at the same time keep their script order.
    this.script = expanded.map((e, i) => [e, i]).sort((a, b) => a[0].t - b[0].t || a[1] - b[1]).map((x) => x[0]);
    this.clock = clock;
    this.stage = stage;
    this.router = router;
    this.render = render;
    this.t = 0;           // page time since the start
    this.vt = 0;          // video time
    this.next = 0;
    this.rate = new Rate();
    this.finger = null;   // [x, y]
    this.down = false;
    this.drag = null;
    this.touchAlpha = 0;
  }

  // Page seconds the script lasts.
  get duration() {
    return this.script.reduce((m, e) => Math.max(m, e.t + (e.drag ? e.duration || 0 : 0)), 0);
  }

  // Video frames the script takes at `fps` (slow motion makes it longer than duration · fps).
  frameCount(fps) {
    const rate = new Rate();
    const rates = this.script.filter((e) => e.rate != null);
    let k = 0;
    let t = 0;
    let frames = 0;
    const end = this.duration;
    while (t < end - 1e-9 && frames < 1e6) {
      while (k < rates.length && rates[k].t <= t + 1e-9) { rate.set(rates[k].rate, rates[k].ramp ?? 0.25); k++; }
      t += (1 / fps) * rate.step(1 / fps);
      frames++;
    }
    return frames;
  }

  get done() { return this.t >= this.duration - 1e-9; }

  // dt: video seconds. draw = false advances everything without rendering (fast seeking).
  step(dt, draw = true) {
    // Events due at the current page time (rate changes take effect for this frame).
    const fire = [];
    while (this.next < this.script.length && this.script[this.next].t <= this.t + 1e-9) fire.push(this.script[this.next++]);
    for (const e of fire) if (e.rate != null) this.rate.set(e.rate, e.ramp ?? 0.25);
    const r = this.rate.step(dt);
    const pdt = dt * r;
    this.vt += dt;
    const now = this.clock.advance(pdt);
    this.t += pdt;
    for (const e of fire) {
      if (e.camera) this.stage.cameraTo(resolve(e.camera), this.vt, e.duration ?? 1.0);
      if (e.caption !== undefined) this.stage.setCaption(e.caption, this.vt);
      if (e.tag !== undefined) this.stage.setTag?.(e.tag, this.vt);
      if (e.down) {
        this.finger = resolve(e.down).slice();
        this.down = true;
        this.router.inject('down', this.finger, now);
      }
      if (e.drag) {
        this.drag = { from: this.finger.slice(), points: resolve(e.drag), t0: this.t - pdt, duration: e.duration, ease: eases[e.ease || 'inOut'] };
      }
      if (e.up) {
        this.drag = null;
        this.down = false;
        this.router.inject('up', this.finger, now);
      }
      if (e.call) e.call({ now, demo: this });
    }
    this.stage.setSlow?.(this.rate.to, this.vt);
    // Finger motion (sampled every frame, like a digitizer).
    if (this.drag && this.down) {
      const d = this.drag;
      const u = Math.min(1, (this.t - d.t0) / d.duration);
      const p = catmull([d.from, ...d.points], d.ease(u));
      this.finger = p;
      this.router.inject('move', p, now);
      if (u >= 1) this.drag = null;
    }
    // Touch indicator fades in 0.08 s, out 0.15 s (video time: it reads the same in slow motion).
    this.touchAlpha += (this.down ? dt / 0.08 : -dt / 0.15);
    this.touchAlpha = Math.max(0, Math.min(1, this.touchAlpha));
    if (this.finger) {
      this.stage.touch.style.left = `${this.finger[0]}px`;
      this.stage.touch.style.top = `${this.finger[1]}px`;
    }
    this.stage.touch.style.opacity = String(this.touchAlpha);
    this.stage.apply(this.vt);
    if (draw) this.render(now, pdt);
    else this.render(now, pdt, false);
    return this.t;
  }
}
