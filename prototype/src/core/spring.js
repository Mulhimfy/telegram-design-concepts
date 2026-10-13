// Closed-form damped harmonic oscillator, the same model as CASpringAnimation
// (m·x'' + c·x' + k·x = 0). Frame-rate independent: state is evaluated
// analytically from the moment the spring was (re)targeted, so a 60 fps
// recording and a 120 Hz ProMotion phone produce identical curves.
//
// Velocity hand-off: retargeting keeps the current value and velocity, which is
// what UIKit does with interruptible springs (and what Telegram's
// ContainedViewLayoutTransition does with `beginWithCurrentState`).

export class SpringParams {
  constructor(mass, stiffness, damping) {
    this.mass = mass;
    this.stiffness = stiffness;
    this.damping = damping;
  }

  // SwiftUI / UISpringTimingParameters style: response (s), dampingFraction.
  static fromResponse(response, dampingFraction, mass = 1) {
    const omega = (2 * Math.PI) / response;
    const stiffness = omega * omega * mass;
    const damping = 2 * dampingFraction * Math.sqrt(stiffness * mass);
    return new SpringParams(mass, stiffness, damping);
  }

  get omega0() { return Math.sqrt(this.stiffness / this.mass); }
  get zeta() { return this.damping / (2 * Math.sqrt(this.stiffness * this.mass)); }

  // Same definition as CASpringAnimation.settlingDuration (|x| < 0.001·|x0|).
  settlingDuration(x0 = 1, v0 = 0, epsilon = 0.001) {
    let t = 0;
    const dt = 1 / 240;
    let lastOutside = 0;
    for (; t < 10; t += dt) {
      const { x } = solveSpring(this, x0, v0, t);
      if (Math.abs(x) > epsilon * Math.max(Math.abs(x0), 1e-6)) lastOutside = t;
      if (t - lastOutside > 0.25) break;
    }
    return lastOutside;
  }
}

// Displacement x (current − target) and velocity after time t.
export function solveSpring(p, x0, v0, t) {
  const w0 = p.omega0;
  const z = p.zeta;
  if (z < 1 - 1e-6) {
    const wd = w0 * Math.sqrt(1 - z * z);
    const e = Math.exp(-z * w0 * t);
    const a = x0;
    const b = (v0 + z * w0 * x0) / wd;
    const c = Math.cos(wd * t);
    const s = Math.sin(wd * t);
    const x = e * (a * c + b * s);
    const v = e * ((-z * w0) * (a * c + b * s) + (-a * wd * s + b * wd * c));
    return { x, v };
  } else if (z > 1 + 1e-6) {
    const sq = Math.sqrt(z * z - 1);
    const r1 = -w0 * (z - sq);
    const r2 = -w0 * (z + sq);
    const A = (v0 - r2 * x0) / (r1 - r2);
    const B = x0 - A;
    const e1 = Math.exp(r1 * t);
    const e2 = Math.exp(r2 * t);
    return { x: A * e1 + B * e2, v: A * r1 * e1 + B * r2 * e2 };
  } else {
    const e = Math.exp(-w0 * t);
    const b = v0 + w0 * x0;
    return { x: e * (x0 + b * t), v: e * (b - w0 * (x0 + b * t)) };
  }
}

// An animatable scalar driven by a spring. `set` jumps, `animate` retargets
// with velocity hand-off, `track` follows a finger 1:1 (spring disabled).
export class SpringValue {
  constructor(value, params) {
    this.params = params;
    this.target = value;
    this._x0 = 0;
    this._v0 = 0;
    this._t0 = 0;
    this._value = value;
    this._velocity = 0;
    this.settled = true;
    this.epsilon = 5e-4;
  }

  set(value, now) {
    this.target = value;
    this._x0 = 0;
    this._v0 = 0;
    this._t0 = now;
    this._value = value;
    this._velocity = 0;
    this.settled = true;
  }

  animate(target, now, { params = this.params, velocity } = {}) {
    this.update(now);
    const v = velocity !== undefined ? velocity : this._velocity;
    this.params = params;
    this.target = target;
    this._x0 = this._value - target;
    this._v0 = v;
    this._t0 = now;
    this.settled = false;
  }

  update(now) {
    if (this.settled) return this._value;
    const t = Math.max(0, now - this._t0);
    const { x, v } = solveSpring(this.params, this._x0, this._v0, t);
    this._value = this.target + x;
    this._velocity = v;
    // Perceptual rest: well below a pixel / a tenth of a degree for the values we animate.
    if (Math.abs(x) < this.epsilon && Math.abs(v) < this.epsilon * 10 && t > 0.03) {
      this._value = this.target;
      this._velocity = 0;
      this.settled = true;
    }
    return this._value;
  }

  get value() { return this._value; }
  get velocity() { return this._velocity; }
}

// Apple's rubber band (UIScrollView): f(x) = (1 − 1/(x·c/d + 1))·d, c = 0.55.
export function rubberBand(x, dimension, c = 0.55) {
  const s = Math.sign(x);
  const a = Math.abs(x);
  return s * (1 - 1 / ((a * c) / dimension + 1)) * dimension;
}

// UIScrollView momentum projection (WWDC18 "Designing Fluid Interfaces").
// decelerationRate: 0.998 = .normal, 0.99 = .fast (per millisecond).
export function project(velocity, decelerationRate = 0.99) {
  return ((velocity / 1000) * decelerationRate) / (1 - decelerationRate);
}
