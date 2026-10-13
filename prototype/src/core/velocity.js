// Pan velocity like UIPanGestureRecognizer.velocity(in:): least-squares slope
// over the most recent samples (default window 80 ms), in points per second.
export class VelocityTracker {
  constructor(windowSeconds = 0.08) {
    this.windowSeconds = windowSeconds;
    this.samples = [];
  }

  reset() { this.samples.length = 0; }

  add(t, x, y) {
    this.samples.push({ t, x, y });
    const cutoff = t - 0.25;
    while (this.samples.length > 2 && this.samples[0].t < cutoff) this.samples.shift();
  }

  velocity(now) {
    const recent = this.samples.filter((s) => s.t >= now - this.windowSeconds);
    // A finger held still before lifting reports zero, as on iOS.
    if (recent.length < 2) return { x: 0, y: 0 };
    const n = recent.length;
    let st = 0, sx = 0, sy = 0, stt = 0, stx = 0, sty = 0;
    const t0 = recent[0].t;
    for (const s of recent) {
      const t = s.t - t0;
      st += t; sx += s.x; sy += s.y; stt += t * t; stx += t * s.x; sty += t * s.y;
    }
    const den = n * stt - st * st;
    if (Math.abs(den) < 1e-9) return { x: 0, y: 0 };
    return { x: (n * stx - st * sx) / den, y: (n * sty - st * sy) / den };
  }
}
