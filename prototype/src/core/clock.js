// Real time (performance.now) or virtual time advanced by the recorder, so every
// animation in a rendered demo is frame-exact regardless of machine speed.
export class Clock {
  constructor(virtual = false) {
    this.virtual = virtual;
    this.t = 1;
  }

  now() {
    return this.virtual ? this.t : performance.now() / 1000;
  }

  advance(dt) {
    this.t += dt;
    return this.t;
  }
}
