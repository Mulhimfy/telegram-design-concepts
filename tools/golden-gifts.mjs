// Golden frames of the web glass gifts (prototype/src/profile/glass-gifts.js: GiftLook, GlassTile, MotionSource),
// replayed by the Swift port's tests (ios/Standalone/GlassGiftsCore) so the two implementations cannot drift.
// usage: node tools/golden-gifts.mjs > ios/Standalone/GlassGiftsCore/Tests/GlassGiftsCoreTests/Resources/golden-gifts.json
//
// The prototype is imported as it is. In node its tiles write into fake elements (a `style` object with
// `setProperty`), and its MotionSource listens on a fake `window`. Two things make the DOM writes show the model
// itself rather than its display rounding:
//   · Number.prototype.toFixed prints full precision while recording (the page rounds what it writes: 2 decimals for
//     angles, 4 for the scale, whole degrees for the sparkles' turn — formatting, not behaviour);
//   · `tile.last` is cleared before every update, so every frame writes (the page skips a frame whose rounded
//     transform string didn't change).
// Scenarios script what the page does on touch (profile-page.js): aim + burst on touch down, aims as the finger moves,
// release on lift, and in inspect mode release / burst / aim as the finger crosses tiles; with and without the phone's
// tilt (`light`). Frames run at 60 Hz unless a scenario jitters them.
import { GiftLook, GlassTile, MotionSource } from '../prototype/src/profile/glass-gifts.js';

Number.prototype.toFixed = function toFixed() {
  return String(Number(this));
};

const T0 = 10;            // seconds: the clock at a scenario's start (away from 0, like tools/golden.mjs)
const FRAME = 1 / 60;
const PRECISION = 1e8;    // recorded values keep 8 decimals (the Swift tests compare within 1e-6)

const round = (x) => Math.round(x * PRECISION) / PRECISION;
const NUMBER = /[-+]?(?:\d+\.?\d*|\.\d+)(?:e[-+]?\d+)?/gi;
const numbers = (s) => (String(s ?? '').match(NUMBER) || []).map(Number);

function element() {
  const style = {
    setProperty(name, value) {
      this[name] = value;
    },
  };
  return { style };
}

function makeTile() {
  const parts = {
    gift: element(),
    ribbon: element(),
    badges: [element(), element()],
    sheen: element(),
    holo: element(),
    rim: element(),
    shadow: element(),
    shards: [0, 1, 2].map(() => element()),
    sparkles: [0, 1, 2, 3].map(() => element()),
  };
  const el = element();
  return { tile: new GlassTile(el, parts), el, parts };
}

// One tile's frame, read back from what GlassTile.update wrote:
//   o: [active (0/1), translateX, translateY, scale, rotateX (pitch), rotateY (yaw), rotateZ,
//       sheen x %, sheen y %, sheen opacity, holo x %, holo y %, holo opacity, rim angle,
//       gift x, gift y, shadow x, shadow y, shadow scale, shadow opacity]
//   b (only while a burst writes): [shard 0 opacity, translateX %, rotate, shard 1 …, shard 2 …,
//       sparkle 0 opacity, scale, rotate, sparkle 1 …, sparkle 2 …, sparkle 3 …]
function read(t, active, burstWritten) {
  const P = t.parts;
  const tf = numbers(t.el.style.transform);              // perspective, tx, ty, scale, rotateX, rotateY, rotateZ
  const sheen = numbers(P.sheen.style.transform);       // translate(x%, y%)
  const holo = numbers(P.holo.style.backgroundPosition); // x% y%
  const rim = numbers(P.rim.style['--rim-angle']);
  const gift = numbers(P.gift.style.transform);         // translateZ(14px) translate(x, y)
  const shadow = numbers(P.shadow.style.transform);     // translate(x, y) scale(s)
  if (tf.length !== 7 || tf[0] !== GiftLook.perspective || sheen.length !== 2 || holo.length !== 2 || rim.length !== 1
      || gift.length !== 3 || gift[0] !== GiftLook.depth.gift || shadow.length !== 3) {
    throw new Error(`unexpected DOM writes: ${JSON.stringify(t.el.style)} ${JSON.stringify(P.gift.style)}`);
  }
  const out = {
    o: [
      active ? 1 : 0,
      ...tf.slice(1),
      ...sheen, Number(P.sheen.style.opacity),
      ...holo, Number(P.holo.style.opacity),
      rim[0],
      ...gift.slice(1),
      ...shadow, Number(P.shadow.style.opacity),
    ].map(round),
  };
  if (burstWritten) {
    out.b = [
      ...P.shards.flatMap((sh) => [Number(sh.style.opacity), ...numbers(sh.style.transform)]),   // translateX(t%) rotate(r)
      ...P.sparkles.flatMap((sp) => [Number(sp.style.opacity), ...numbers(sp.style.transform)]), // scale(s) rotate(r)
    ].map(round);
    if (out.b.length !== 21) throw new Error(`unexpected burst writes: ${out.b}`);
  }
  return out;
}

// ---- tile scenarios

// The clock of a scenario, step by step: step 0 is at T0 and updates with one 60 Hz frame (the page's first dt); step
// i > 0 advances by dts[i % dts.length]. The Swift tests run the same sums.
// events: [time, tile, action, ...args]; action: 'aim' u v | 'burst' | 'release'. light: (t) => [x, y] | null.
// A step records: `act` (the actions applied before its update, in order; omitted when none), `light` (omitted when
// null) and `out` (one entry per tile, see `read`).
function tileScenario({ name, tiles = 1, duration, events, light = () => null, dts = [FRAME] }) {
  const made = Array.from({ length: tiles }, () => makeTile());
  const steps = [];
  const queue = events.slice().sort((a, b) => a[0] - b[0]);
  let qi = 0;
  let elapsed = 0;
  let index = 0;
  while (elapsed <= duration + 1e-9) {
    const dt = dts[index % dts.length];
    if (index > 0) elapsed += dt;
    const now = T0 + elapsed;
    const act = [];
    while (qi < queue.length && queue[qi][0] <= elapsed + 1e-9) {
      const [, ti, action, ...args] = queue[qi++];
      const tile = made[ti].tile;
      if (action === 'aim') tile.aim(args[0], args[1]);
      else if (action === 'burst') tile.burst(now);
      else if (action === 'release') tile.release();
      else throw new Error(action);
      act.push([ti, action, ...args]);
    }
    const raw = light(elapsed);
    const l = raw ? raw.map((x) => Math.round(x * 1e6) / 1e6) : null;   // both sides use the recorded values
    const lightValue = l ? { x: l[0], y: l[1] } : null;
    const out = made.map((m) => {
      m.el.style.transform = undefined;
      m.tile.last = '';
      for (const sh of m.parts.shards) sh.style.transform = undefined;
      const active = m.tile.update(now, index === 0 ? FRAME : dt, lightValue);
      const burstWritten = m.parts.shards[0].style.transform !== undefined;
      return read(m, active, burstWritten);
    });
    const step = {};
    if (act.length) step.act = act;
    if (l) step.light = l;
    step.out = out;
    steps.push(step);
    index += 1;
  }
  return { name, tiles, dts, steps };
}

// The finger along f(t) every frame from t0 to t1: [tile, 'aim', u, v] (inputs rounded to 6 decimals; both sides
// apply the recorded values).
const path = (t0, t1, f) => {
  const ev = [];
  for (let t = t0; t <= t1 + 1e-9; t += FRAME) {
    const [tile, action, u, v] = f(t);
    ev.push([+t.toPrecision(12), tile, action, Math.round(u * 1e6) / 1e6, Math.round(v * 1e6) / 1e6]);
  }
  return ev;
};

const tileScenarios = [
  tileScenario({
    name: 'tapCentre',
    duration: 1.4,
    events: [[0, 0, 'aim', 0, 0], [0, 0, 'burst'], [0.15, 0, 'release']],
  }),
  tileScenario({
    name: 'tapCorner',
    duration: 2.0,
    events: [[0, 0, 'aim', 0.85, -0.75], [0, 0, 'burst'], [0.12, 0, 'release']],
  }),
  tileScenario({
    name: 'holdAndRock',
    duration: 2.6,
    events: [
      [0, 0, 'aim', -0.2, 0.1], [0, 0, 'burst'],
      ...path(0.05, 1.2, (t) => [0, 'aim', 0.9 * Math.sin((2 * Math.PI * t) / 0.8), 0.7 * Math.cos((2 * Math.PI * t) / 1.1)]),
      [1.25, 0, 'release'],
    ],
  }),
  tileScenario({
    name: 'beyondEdges',
    duration: 2.0,
    events: [[0, 0, 'aim', 1.6, -1.4], [0, 0, 'burst'], [0.3, 0, 'aim', -2, 2], [0.5, 0, 'release']],
  }),
  tileScenario({
    // Press, hold, slide: the finger crosses from tile 0 to tile 1, a gap, then tile 2 (profile-page.js inspect).
    name: 'inspectAcross',
    tiles: 3,
    duration: 2.6,
    events: [
      [0, 0, 'aim', 0.1, 0.2], [0, 0, 'burst'],
      [0.05, 0, 'aim', 0.2, 0.25],
      ...path(0.2, 0.3, (t) => [0, 'aim', 0.2 + (t - 0.2) * 7.5, 0.3]),
      [0.35, 0, 'release'], [0.35, 1, 'burst'], [0.35, 1, 'aim', -0.9, 0.3],
      ...path(0.4, 0.6, (t) => [1, 'aim', -0.9 + (t - 0.4) * 8.5, 0.3 - (t - 0.4) * 2]),
      [0.65, 1, 'release'],
      [0.75, 2, 'burst'], [0.75, 2, 'aim', -0.8, -0.5],
      ...path(0.8, 1.2, (t) => [2, 'aim', -0.8 + (t - 0.8) * 3, -0.5 + (t - 0.8) * 2.5]),
      [1.3, 2, 'release'],
    ],
  }),
  tileScenario({
    // No touch: the phone's tilt moves the light (and a hint of lean); past ±20 it clamps; then the light goes.
    name: 'motionOnly',
    duration: 2.4,
    events: [],
    light: (t) => (t < 1.6
      ? [14 * Math.sin((2 * Math.PI * t) / 1.6), 9 * Math.sin((2 * Math.PI * t) / 2.3 + 1)]
      : t < 2.0 ? [24, -22] : null),
  }),
  tileScenario({
    name: 'tapWithMotion',
    duration: 2.2,
    events: [[0.3, 0, 'aim', -0.5, 0.6], [0.3, 0, 'burst'], [0.45, 0, 'release']],
    light: (t) => (t < 1.0 ? [8, -5] : [-12, 7]),
  }),
  tileScenario({
    // Bursts on top of bursts (the finger taps again while the light still runs).
    name: 'rapidBursts',
    duration: 2.2,
    events: [
      [0, 0, 'aim', 0.3, -0.3], [0, 0, 'burst'],
      [0.2, 0, 'aim', -0.4, 0.2], [0.2, 0, 'burst'],
      [0.4, 0, 'aim', 0, 0.8], [0.4, 0, 'burst'],
      [0.55, 0, 'release'],
    ],
  }),
  tileScenario({
    // Uneven frames (8–50 ms, the page's dt range) with a tap and the tilt.
    name: 'jitteredFrames',
    duration: 2.0,
    dts: [1 / 120, 1 / 60, 1 / 40, 1 / 30, 0.05, 1 / 90],
    events: [[0, 0, 'aim', -0.6, -0.4], [0, 0, 'burst'], [0.2, 0, 'release']],
    light: (t) => [10 * Math.sin(2 * Math.PI * t), -6 * Math.cos(2 * Math.PI * t)],
  }),
];

// ---- motion scenarios (MotionSource: first reading = reference, 0.1 s smoothing, ~4 s re-centring, ±20 clamp)

// Step i updates with dts[i % dts.length]; before it, the reading `feed` (beta, gamma; rounded to 6 decimals, both
// sides use the recorded values) goes through the source's own deviceorientation listener, and `set` scripts a tilt
// ('clear' goes back to the sensors). `out` is update's value, or null.
function motionScenario({ name, duration, feed = () => null, sets = [], dts = [FRAME] }) {
  const handlers = {};
  globalThis.window = { addEventListener: (type, fn) => { handlers[type] = fn; } };
  const source = new MotionSource(undefined);
  source.start();
  if (!handlers.deviceorientation) throw new Error('MotionSource did not listen');
  const queue = sets.slice();
  const steps = [];
  let elapsed = 0;
  let index = 0;
  while (elapsed <= duration + 1e-9) {
    const dt = dts[index % dts.length];
    if (index > 0) elapsed += dt;
    const step = {};
    const raw = feed(elapsed);
    if (raw) {
      const reading = raw.map((x) => Math.round(x * 1e6) / 1e6);
      handlers.deviceorientation({ beta: reading[0], gamma: reading[1] });
      step.feed = reading;
    }
    while (queue.length && queue[0][0] <= elapsed + 1e-9) {
      const [, value] = queue.shift();
      source.set(value ? { x: value[0], y: value[1] } : null);
      step.set = value ?? 'clear';
    }
    const v = source.update(dt);
    step.out = v ? [round(v.x), round(v.y)] : null;
    steps.push(step);
    index += 1;
  }
  return { name, dts, steps };
}

const motionScenarios = [
  motionScenario({
    // The phone moves for 3 s, then is held: the light returns to neutral as the reference follows (~4 s).
    name: 'moveThenHold',
    duration: 8.0,
    feed: (t) => {
      const u = Math.min(t, 3);
      return [40 + 10 * Math.sin((2 * Math.PI * u) / 3), -5 + 8 * Math.sin(Math.PI * u)];
    },
  }),
  motionScenario({
    name: 'noReadingYet',
    duration: 1.0,
    feed: (t) => (t >= 0.2 ? [12, -30] : null),
  }),
  motionScenario({
    name: 'clampAndJumps',
    duration: 4.0,
    feed: (t) => (t < 0.3 ? [10, 10] : t < 1.5 ? [50, -45] : [12, 9]),
  }),
  motionScenario({
    name: 'scriptedTilt',
    duration: 2.0,
    feed: (t) => [20 + 5 * t, 3 - 4 * t],
    sets: [[0.5, [12, -4]], [1.0, null]],
  }),
  motionScenario({
    name: 'jitteredFrames',
    duration: 3.0,
    dts: [1 / 120, 1 / 60, 1 / 40, 1 / 30, 0.05, 1 / 90],
    feed: (t) => [35 + 25 * Math.sin(1.7 * t), 15 * Math.cos(2.3 * t)],
  }),
];

const look = {
  maxYaw: GiftLook.maxYaw,
  maxPitch: GiftLook.maxPitch,
  motionLean: GiftLook.motionLean,
  held: GiftLook.held,
  depth: GiftLook.depth,
  perspective: GiftLook.perspective,
};

process.stdout.write(JSON.stringify({ version: 1, source: 'prototype/src/profile/glass-gifts.js', t0: T0, look, tileScenarios, motionScenarios }));
