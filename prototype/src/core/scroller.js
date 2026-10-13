// UIScrollView along one axis: 1:1 tracking with Apple's rubber band past the ends
// (c = 0.55 over the viewport), momentum with deceleration 0.998 per ms (.normal), and a
// critically damped bounce back from an edge carrying the incoming velocity. The same model
// as the profile header's scrolling (ui/profile-scroll.js), without the header.

import { SpringParams, SpringValue, rubberBand } from './spring.js';

const DECELERATION = 0.998;
const clamp = (x, a, b) => Math.max(a, Math.min(b, x));

export class Scroller {
  constructor({ viewport, content = 0 }) {
    this.viewport = viewport;      // pt visible
    this.content = content;        // pt of content
    this.offset = 0;
    this.mode = 'idle';            // idle | drag | decel | spring
    this.tracking = false;
    this.spring = new SpringValue(0, SpringParams.fromResponse(0.45, 1));
    this.spring.epsilon = 0.05;
  }

  get maxOffset() { return Math.max(0, this.content - this.viewport); }

  fromRaw(raw) {
    const max = this.maxOffset;
    if (raw < 0) return -rubberBand(-raw, this.viewport);
    if (raw > max) return max + rubberBand(raw - max, this.viewport);
    return raw;
  }

  toRaw(o) {
    const max = this.maxOffset;
    const inv = (y) => (this.viewport / 0.55) * (1 / (1 - Math.min(0.999, y / this.viewport)) - 1);
    if (o < 0) return -inv(-o);
    if (o > max) return max + inv(o - max);
    return o;
  }

  // A touch landing stops any motion (as on iOS); dragging starts from where it is.
  begin(y) {
    this.tracking = true;
    this.mode = 'drag';
    this.dragY = y;
    this.dragRaw = this.toRaw(this.offset);
  }

  drag(y) {
    if (!this.tracking) return;
    this.offset = this.fromRaw(this.dragRaw + (this.dragY - y));
  }

  // vy: finger velocity (pt/s, + = down).
  end(vy, now) {
    if (!this.tracking) return;
    this.tracking = false;
    const v = -vy;
    const max = this.maxOffset;
    if (this.offset < 0 || this.offset > max) {
      this.springTo(clamp(this.offset, 0, max), v, now);
      return;
    }
    if (Math.abs(v) < 20) { this.mode = 'idle'; return; }
    this.mode = 'decel';
    this.decel = { t0: now, o0: this.offset, v0: v };
  }

  springTo(target, velocity, now, response = 0.45) {
    this.mode = 'spring';
    this.spring.set(this.offset, now);
    this.spring.animate(target, now, { params: SpringParams.fromResponse(response, 1.0), velocity });
  }

  stop() {
    if (this.mode === 'decel' || this.mode === 'spring') this.mode = 'idle';
  }

  get moving() { return this.mode === 'decel' || this.mode === 'spring'; }

  update(now) {
    if (this.mode === 'decel') {
      const d = this.decel;
      const k = Math.pow(DECELERATION, 1000 * (now - d.t0));
      const o = d.o0 + (d.v0 * (k - 1)) / (1000 * Math.log(DECELERATION));
      const v = d.v0 * k;
      const max = this.maxOffset;
      if (o < 0 || o > max) {
        // Carries its velocity past the edge, then comes back.
        this.offset = clamp(o, 0, max);
        this.springTo(this.offset, v, now);
      } else {
        this.offset = o;
        if (Math.abs(v) < 8) this.mode = 'idle';
      }
    } else if (this.mode === 'spring') {
      this.offset = this.spring.update(now);
      if (this.spring.settled) this.mode = 'idle';
    }
    return this.moving || this.tracking;
  }
}
