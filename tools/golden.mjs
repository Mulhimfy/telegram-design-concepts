// Golden trajectories of the web physics (prototype/src/coin/coin-physics.js), replayed by
// the Swift port's tests (ios/Standalone/Core/Tests) so the two implementations cannot drift.
// Runs the physics module directly in node (no DOM, no browser).
// usage: node tools/golden.mjs > ios/Standalone/Core/Tests/GlassCoinCoreTests/Resources/golden.json
//
// Input events: [type, t, a, b] with t in s from the start of the scenario:
//   down / move / up  a, b = finger in pt from the coin centre (screen axes)
//   turnBy            a = faces (GlassCoin.turnBy: turns over on its own to show a new back)
//   pulse             a = hold (s) (GlassCoin.pulse: a colour change)
//   jump              a = face (GlassCoin.jumpToFace: Reduce Motion, restoring)
//   back              a = the reverse ('0' the photo itself, 'emblem', 'back'): set at once
//   pendingBack       a = the reverse, set as app.js `chooseBack` does with the back in view:
//                     on the next even face in front (onFaceChange), when the back faces away
import { GlassCoin } from '../prototype/src/coin/coin-physics.js';

const scenarios = [
  { name: 'tap', photoCount: 3, input: [['down', 0, 30, 4], ['up', 0.12, 30, 4]] },
  { name: 'slowDragBack', photoCount: 3, input: drag(0, 0, 60, 10, 0.8, 'out') },
  { name: 'slowDragOver', photoCount: 3, input: drag(0, 0, 120, 6, 1.0, 'out') },
  { name: 'gentleSwipe', photoCount: 4, input: drag(10, 0, -80, 4, 0.25, 'linear') },
  { name: 'flick', photoCount: 4, input: drag(30, 0, -150, 10, 0.08, 'linear') },
  { name: 'hardFlick', photoCount: 1, input: drag(30, 0, -220, 12, 0.06, 'linear') },
  { name: 'tiltAround', photoCount: 2, input: path([[4, 10], [30, -30], [-10, -46], [-40, 4], [-6, 40], [26, 10]], 2.0) },
  { name: 'catchSpin', photoCount: 5, input: [...drag(-26, 0, 130, 4, 0.12, 'linear'), ['down', 0.55, 4, 6], ['up', 1.2, 4, 6]] },
  // The back is the photo itself by default; with the front in view a new back photo is set at
  // once (out of sight) and the photo turns over by itself to show it (app.js chooseBack).
  { name: 'addBackPhoto', photoCount: 1, back: '0', input: [['back', 0, 'back', 0], ['turnBy', 0, 1, 0], ...drag(-20, 4, 110, 8, 0.7, 'out', 1.6)] },
  // With the back in view: it turns two faces (1.3× the flip response), the new back is set as the
  // front passes (onFaceChange) and it lands on the new back; then "None": one face back to the front.
  { name: 'changeBackPhoto', photoCount: 1, back: 'back', input: [['jump', 0, 1, 0], ['pendingBack', 0.1, 'emblem', 0], ['turnBy', 0.1, 2, 0], ['pendingBack', 1.6, '0', 0], ['turnBy', 1.6, 1, 0]] },
  // "None" with the front in view: the back becomes the photo again, a short lift (pulse 0.18 s);
  // a colour change (pulse 0.18 s) and a pulse while it turns (ignored).
  { name: 'pulse', photoCount: 1, back: 'back', input: [['back', 0, '0', 0], ['pulse', 0, 0.18, 0], ['pulse', 0.9, 0.18, 0], ['turnBy', 1.6, 1, 0], ['pulse', 1.7, 0.3, 0]] },
  // Caught mid-turn: the finger takes it (a catch tick) and throws it back.
  { name: 'catchTurn', photoCount: 1, back: 'back', input: [['turnBy', 0, 1, 0], ...drag(6, 2, 90, 10, 0.3, 'linear', 0.16)] },
];

function drag(x0, y0, x1, y1, duration, ease, start = 0) {
  const ev = [['down', start, x0, y0]];
  const n = Math.max(2, Math.round(duration * 120));
  for (let i = 1; i <= n; i++) {
    const u = i / n;
    const k = ease === 'out' ? 1 - (1 - u) * (1 - u) : u;
    ev.push(['move', start + 0.02 + duration * u, x0 + (x1 - x0) * k, y0 + (y1 - y0) * k]);
  }
  ev.push(['up', start + 0.02 + duration, x1, y1]);
  return ev;
}

function path(points, duration) {
  const ev = [['down', 0, points[0][0], points[0][1]]];
  const n = Math.round(duration * 120);
  for (let i = 1; i <= n; i++) {
    const u = i / n;
    const f = u * (points.length - 1);
    const j = Math.min(points.length - 2, Math.floor(f));
    const t = f - j;
    ev.push(['move', 0.02 + duration * u, points[j][0] + (points[j + 1][0] - points[j][0]) * t, points[j][1] + (points[j + 1][1] - points[j][1]) * t]);
  }
  const last = points[points.length - 1];
  ev.push(['up', 0.02 + duration, last[0], last[1]]);
  return ev;
}

// '0' → 0 (the photo itself), other keys as they are ('emblem', 'back').
const backKey = (key) => (key === '0' ? 0 : key);

const out = [];
for (const sc of scenarios) {
  const coin = new GlassCoin({ photoCount: sc.photoCount, back: backKey(sc.back ?? 'emblem') });
  const ticks = [];
  const lands = [];
  const faces = [];
  let pendingBack;
  coin.onTick = (k) => ticks.push(k);
  coin.onLand = (changed, face) => lands.push({ changed, face });
  coin.onFaceChange = (face) => {
    faces.push(face);
    if (pendingBack !== undefined && Math.abs(face) % 2 === 0) {
      coin.setBack(pendingBack);
      pendingBack = undefined;
    }
  };
  const t0 = 10;
  const samples = [];
  const events = sc.input.map(([type, t, a, b]) => ({ type, t: t0 + t, a, b }));
  const end = Math.max(...events.map((e) => e.t)) + 3.0;
  let ei = 0;
  for (let t = t0; t <= end + 1e-9; t = Math.round((t + 1 / 120) * 1e6) / 1e6) {
    while (ei < events.length && events[ei].t <= t + 1e-9) {
      const e = events[ei++];
      const p = { x: e.a, y: e.b };
      if (e.type === 'down') coin.pointerDown(p, e.t);
      else if (e.type === 'move') coin.pointerMove(p, e.t);
      else if (e.type === 'up') coin.pointerUp(p, e.t);
      else if (e.type === 'turnBy') coin.turnBy(e.a, e.t);
      else if (e.type === 'pulse') coin.pulse(e.t, e.a);
      else if (e.type === 'jump') coin.jumpToFace(e.a, e.t);
      else if (e.type === 'back') coin.setBack(backKey(e.a));
      else if (e.type === 'pendingBack') pendingBack = backKey(e.a);
      else throw new Error(`unknown event ${e.type}`);
    }
    const s = coin.state(t);
    if (Math.round((t - t0) * 120) % 6 === 0) {
      samples.push({ t: +(t - t0).toFixed(6), yaw: s.yaw, pitch: s.pitch, lift: s.lift, glass: s.glass, offsetX: s.offsetX, offsetY: s.offsetY, face: s.face, sideA: String(s.sideA), sideB: String(s.sideB), mode: s.mode });
    }
  }
  out.push({ name: sc.name, photoCount: sc.photoCount, back: sc.back ?? 'emblem', input: sc.input, samples, ticks: ticks.length, lands, faces });
}
process.stdout.write(JSON.stringify({ version: 2, scenarios: out }, null, 1));
