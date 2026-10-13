// A small timeline builder for the demo scripts: a cursor in page seconds and helpers that
// add events at it. Points are screen pt, or functions resolved when the event fires (rows
// move as lists scroll and reorder).

export function timeline() {
  const events = [];
  let T = 0;
  let rate = 1;
  const k = {
    events,
    get t() { return T; },
    set t(v) { T = v; },
    get rate() { return rate; },
    at(t, e) { events.push({ t, ...e }); return k; },
    wait(d) { T += d; return k; },
    // Video seconds → page seconds at the current speed (for waits that should read the same).
    video(d) { T += d * rate; return k; },
    caption(text) { events.push({ t: T, caption: text }); return k; },
    camera(c, duration = 1.0) { events.push({ t: T, camera: c, duration }); return k; },
    // Play speed from here on (slow motion < 1); `ramp`: video seconds to get there.
    speed(r, ramp = 0.3) { events.push({ t: T, rate: r, ramp }); rate = r; return k; },
    call(fn) { events.push({ t: T, call: fn }); return k; },
    tap(p, hold = 0.09) { events.push({ t: T, tap: p, hold }); T += hold; return k; },
    down(p) { events.push({ t: T, down: p }); return k; },
    up() { events.push({ t: T, up: true }); return k; },
    // Finger down at `from`, `hold` s, then through `path` in `duration` s, then up (unless keep).
    gesture({ from, path, hold = 0.12, duration = 0.6, ease = 'inOut', after = 0, keep = false }) {
      events.push({ t: T, down: from });
      T += hold;
      events.push({ t: T, drag: path, duration, ease });
      T += duration + after;
      if (!keep) events.push({ t: T, up: true });
      return k;
    },
    // The script's events, ending where the cursor is (trailing waits count).
    done() { events.push({ t: T, call: () => {} }); return events; },
    drag(path, duration = 0.6, ease = 'inOut') {
      events.push({ t: T, drag: path, duration, ease });
      T += duration;
      return k;
    },
  };
  return k;
}

// Point helpers.
export const off = (p, dx, dy) => (typeof p === 'function' ? () => { const q = p(); return [q[0] + dx, q[1] + dy]; } : [p[0] + dx, p[1] + dy]);
export const path = (p, steps) => () => { const q = typeof p === 'function' ? p() : p; return steps.map(([dx, dy]) => [q[0] + dx, q[1] + dy]); };
