// Clock-driven animations for the page (sheets, highlights, light). Everything runs on
// the prototype's clock, so a recording on the virtual clock is frame-exact; CSS
// transitions would run on wall time instead.

export const ease = {
  linear: (u) => u,
  out: (u) => 1 - Math.pow(1 - u, 3),
  in: (u) => u * u * u,
  inOut: (u) => (u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2),
  outQuad: (u) => 1 - (1 - u) * (1 - u),
};

export class Animator {
  constructor() {
    this.items = new Set();
  }

  // item.update(now) → true while it still needs frames.
  add(item) {
    this.items.add(item);
    return item;
  }

  tween({ from = 0, to = 1, duration, delay = 0, curve = ease.linear, apply, done }, now) {
    const t0 = now + delay;
    let finished = false;
    const item = {
      update: (t) => {
        if (finished) return false;
        const u = duration > 0 ? Math.max(0, Math.min(1, (t - t0) / duration)) : 1;
        if (t >= t0) apply(from + (to - from) * curve(u));
        if (u >= 1) {
          finished = true;
          done?.();
          return false;
        }
        return true;
      },
      cancel: () => { finished = true; this.items.delete(item); },
    };
    return this.add(item);
  }

  after(delay, fn, now) {
    let done = false;
    const item = {
      update: (t) => {
        if (!done && t >= now + delay) { done = true; fn(t); }
        return !done;
      },
      cancel: () => { done = true; this.items.delete(item); },
    };
    return this.add(item);
  }

  update(now) {
    let busy = false;
    for (const it of [...this.items]) {
      if (it.update(now)) busy = true;
      else this.items.delete(it);
    }
    return busy;
  }

  get busy() {
    return this.items.size > 0;
  }
}
