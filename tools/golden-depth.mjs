// Golden frames of the web Depth Swipe rig (prototype/src/chats/depth.js), replayed by the Swift
// port's tests (ios/Standalone/DepthSwipeCore) so the two implementations cannot drift.
// usage: node tools/golden-depth.mjs > ios/Standalone/DepthSwipeCore/Tests/DepthSwipeCoreTests/Resources/golden-depth.json
//
// DepthRig builds and moves DOM elements, so it runs here against a minimal fake DOM (elements are
// plain objects with a `style` record and the offset/rect fields depth.js reads). Everything it
// computes is read back from what update() writes into those styles. The prototype rounds the
// numbers it writes (toFixed); while recording, Number.prototype.toFixed returns the full double,
// so the golden values are the maths itself, not its CSS rendering.
//
// The row is driven the way prototype/src/chats/chat-list.js (ChatRow) drives it: depthStart on
// swipe begin and on any animated move of more than 0.5 pt, the reveal spring (revealCurve, 0.6 s),
// the per-frame velocity vel = vel·0.45 + v·0.55 of the presented offset, pull = offset − initial
// while the finger holds the row, the spin when the full-swipe action arms (the haptic,
// reveal-options.js), and end() once nothing moves, the row is still and nothing is round the rim.
// Telegram's release rules (ItemListRevealOptionsItemNode): a release under 100 pt/s opens the
// strip if the drag started closed or went past it, a faster one follows the flick; strips are
// 130 pt (Read, Pin) and 190 pt (Mute, Delete, Archive); 100 pt of over-swipe arms the outer
// action, and letting go armed on the right strip archives (offset → −W − 74).
import { DepthRig } from '../prototype/src/chats/depth.js';
import { revealCurve } from '../prototype/src/chats/chat-list.js';
import { VelocityTracker } from '../prototype/src/core/velocity.js';

// ---------------------------------------------------------------- a minimal DOM

class FakeElement {
  constructor(tag = 'div') {
    this.tagName = tag;
    this.className = '';
    this.style = {};
    this.children = [];
    this.parentElement = null;
    this.isConnected = true;
    this.offsetLeft = 0;
    this.offsetWidth = 0;
    this.offsetHeight = 0;
    this.offsetParent = null;
    this._text = '';
  }

  get firstChild() { return this.children[0] ?? null; }
  get textContent() { return this._text; }
  set textContent(v) { this._text = String(v); }

  appendChild(child) {
    child.remove();
    this.children.push(child);
    child.parentElement = this;
    child.isConnected = true;
    return child;
  }

  insertBefore(child, ref) {
    child.remove();
    const i = ref ? this.children.indexOf(ref) : -1;
    if (i < 0) this.children.push(child); else this.children.splice(i, 0, child);
    child.parentElement = this;
    child.isConnected = true;
    return child;
  }

  remove() {
    if (this.parentElement) {
      const p = this.parentElement;
      p.children = p.children.filter((c) => c !== this);
      this.parentElement = null;
    }
  }

  cloneNode() {
    const e = new FakeElement(this.tagName);
    e.className = this.className;
    e.style = { ...this.style };
    return e;
  }

  querySelector(selector) {
    const cls = selector.replace(/^\./, '');
    for (const c of this.children) {
      if (c.className.split(/\s+/).includes(cls)) return c;
      const inner = c.querySelector(selector);
      if (inner) return inner;
    }
    return null;
  }
}

// The name's text node and its measured layout: one advance per UTF-16 unit (the golden records
// the resulting glyph centres, so the Swift test needs no font).
class FakeTitle extends FakeElement {
  constructor(text, advances, left) {
    super('span');
    this.textNode = { nodeType: 3, text };
    this.children = [this.textNode];
    this._text = text;
    this.advances = advances;
    this.left = left;
    this.offsetWidth = advances.reduce((a, b) => a + b, 0);
    this.offsetHeight = 21;
  }

  getBoundingClientRect() {
    return { left: this.left, top: 0, width: this.offsetWidth, height: this.offsetHeight };
  }

  rangeRect(start, end) {
    const before = this.advances.slice(0, start).reduce((a, b) => a + b, 0);
    const width = this.advances.slice(start, end).reduce((a, b) => a + b, 0);
    return { left: this.left + before, top: 0, width, height: this.offsetHeight };
  }
}

let currentTitle = null;
globalThis.document = {
  createElement: (tag) => new FakeElement(tag),
  createRange: () => {
    const r = { start: 0, end: 0 };
    r.setStart = (_node, offset) => { r.start = offset; };
    r.setEnd = (_node, offset) => { r.end = offset; };
    r.getBoundingClientRect = () => currentTitle.rangeRect(r.start, r.end);
    return r;
  },
};
globalThis.getComputedStyle = (el) => ({ color: el.style.color || 'rgb(0, 0, 0)', position: el.style.position || 'static' });

// ---------------------------------------------------------------- the row (chat-list.js ChatMetrics)

const W = 393;                    // iPhone 15 / 16 (Pro) width
const TEXT_X = 86;
const AVATAR = { x: 16, size: 60 };
const STRIP = { left: 130, right: 190 };
const ARM = 100;                  // EXPANDED_ACTIVATION = 50 · (3 − 1)
const FILL = -W - 74;             // animateRevealOptionsFill
const REVEAL_DURATION = 0.6;

// SF Pro Text Semibold 16 pt (tracking −0.312), approximate advances.
const ADVANCE = {
  A: 10.6, M: 14.1, S: 9.6, T: 9.4, K: 10.2, N: 11.6, E: 8.9, R: 10.0, J: 7.8, W: 15.2,
  a: 8.5, e: 8.6, i: 3.9, l: 4.0, x: 8.0, o: 9.0, r: 5.9, g: 9.0, n: 8.9, m: 13.4, s: 7.6, t: 5.5, h: 8.9,
  y: 8.2, d: 9.0, u: 8.9, k: 8.1, ' ': 3.9,
};

function makeParts({ title: name, lines, icons }) {
  const advances = [...name].map((c) => ADVANCE[c] ?? 8.5);
  const title = new FakeTitle(name, advances, 200);
  currentTitle = title;
  title.offsetLeft = 0;
  title.offsetParent = { offsetLeft: TEXT_X };   // .chat-title-text inside .chat-title (left: 86)
  const titleRow = { offsetLeft: TEXT_X };
  const iconEls = [];
  let iconX = title.offsetWidth;
  for (const kind of icons) {
    const e = new FakeElement('span');
    e.className = `chat-icon ${kind}`;
    const margin = kind === 'verified' ? 3 : -2;   // telegram.css .chat-icon.verified / .muted
    const width = kind === 'verified' ? 16 : 24;
    e.offsetLeft = iconX + margin;
    e.offsetWidth = width;
    e.offsetParent = titleRow;
    iconX += margin + width;
    iconEls.push(e);
  }
  const box = new FakeElement('div');
  box.className = 'chat-text';
  box.offsetLeft = TEXT_X;
  box.offsetWidth = W - TEXT_X - 16 - 26;
  const lineEls = [];
  for (let i = 0; i < lines; i++) {
    const l = new FakeElement('div');
    l.className = 'chat-line';
    box.appendChild(l);
    lineEls.push(l);
  }
  const avatar = new FakeElement('div');
  avatar.className = 'chat-avatar';
  avatar.offsetLeft = AVATAR.x;
  avatar.offsetWidth = AVATAR.size;
  const pic = new FakeElement('div');
  pic.className = 'avatar-pic';
  avatar.appendChild(pic);
  return { title, icons: iconEls, lines: lineEls, avatar, avatarColor: [0.35, 0.4, 0.45], dark: false };
}

// ---------------------------------------------------------------- reading back what update() wrote

const num = (s) => (s === '' || s === undefined ? 1 : parseFloat(s));

function fnArgs(t, name) {
  const m = new RegExp(`${name}\\(([^)]*)\\)`, 'g');
  const out = [];
  let r;
  while ((r = m.exec(t))) out.push(r[1].split(',').map((v) => parseFloat(v)));
  return out;
}

function readGlyph(g) {
  const t = g.el.style.transform || '';
  const rx = fnArgs(t, 'rotateX');
  const tz = fnArgs(t, 'translateZ');
  const a = rx.length ? rx[0][0] : 0;
  const lift = tz.length ? tz[tz.length - 1][0] : 0;
  let rim = null;
  if (t.startsWith('translate3d')) {
    const [tx, , dz] = fnArgs(t, 'translate3d')[0];
    const deg = -fnArgs(t, 'rotateY')[0][0];
    const kz = fnArgs(t, 'scale3d')[0][2];
    rim = [tx, dz, deg, kz];
  }
  return {
    roll: g.roll.value,
    a,
    lift,
    rim,
    shade: num(g.shade.style.opacity),
    face: num(g.face.style.opacity),
    layers: num(g.layers[0].style.opacity),
    hidden: g.el.style.visibility === 'hidden',
  };
}

function readIcon(ic) {
  const t = ic.el.style.transform || '';
  if (!t) return null;
  const [tx, , dz] = fnArgs(t, 'translate3d')[0];
  const deg = -fnArgs(t, 'rotateY')[0][0];
  return [tx, dz, deg, num(ic.el.style.opacity)];
}

function readMask(box) {
  const m = box.style.maskImage || '';
  if (!m) return null;
  const px = [...m.matchAll(/(-?[\d.e+-]+)px/g)].map((r) => parseFloat(r[1]));
  return [px[0], px[1]];
}

function readDisc(av) {
  const t = av.disc.style.transform || '';
  const [dx, , z] = fnArgs(t, 'translate3d')[0];
  const angle = fnArgs(t, 'rotateY')[0][0];
  const origin = av.el.style.perspectiveOrigin || '';
  const parallax = fnArgs(av.inner.style.transform, 'translateX')[0][0];
  const glint = parseFloat(/translateX\(([^%]+)%\)/.exec(av.glint.style.transform)[1]);
  return {
    lean: av.lean.value,
    angle,
    dx,
    z,
    origin: origin ? parseFloat(origin) : null,
    parallax,
    glint,
    glintOpacity: num(av.glint.style.opacity),
    dim: num(av.dim.style.opacity),
    opacity: num(av.el.style.opacity),
    hidden: av.el.style.visibility === 'hidden',
  };
}

const round = (v) => (typeof v === 'number' ? +v.toPrecision(13) : v);
const roundAll = (v) => (Array.isArray(v) ? v.map(roundAll) : v && typeof v === 'object' ? Object.fromEntries(Object.entries(v).map(([k, x]) => [k, roundAll(x)])) : round(v));

// ---------------------------------------------------------------- the driver (chat-list.js ChatRow)

function revealOpen(side, initial, offset, vx) {
  const width = STRIP[side];
  if (Math.abs(vx) < 100) return side === 'left' ? (initial === 0 && offset > 0) || offset > width : (initial === 0 && offset < 0) || offset < -width;
  return side === 'left' ? vx > 0 : vx < 0;
}

function runScenario(sc) {
  const parts = makeParts(sc);
  const rig = new DepthRig(parts);
  const tracker = new VelocityTracker(0.08);
  const row = { offset: 0, model: 0, anim: null, tracking: false, initial: 0, trackX0: 0, start: 0, swiping: false, armed: false };
  let prevX = 0;
  let vel = 0;
  const t0 = 10;
  let lastNow = t0;
  const frames = [];
  const samples = [];
  const events = sc.input.map(([type, t, x]) => ({ type, t: t0 + t, x }));
  const until = t0 + sc.duration;
  let ei = 0;
  let index = 0;

  const depthStart = (now) => { rig.begin(now); };
  // updateRevealOffsetInternal: animated calls are recorded with the offset presented then.
  const setOffset = (offset, now, animated, calls) => {
    if (animated) calls.push(['set', offset, row.offset]);
    if (animated && Math.abs(offset - row.offset) > 0.5) depthStart(now);
    if (!animated) {
      row.anim = null;
      row.model = offset;
      row.offset = offset;
      return;
    }
    row.anim = { from: row.offset, to: offset, t0: now };
    row.model = offset;
  };

  for (let t = t0; t <= until + 1e-9; t = Math.round((t + 1 / 120) * 1e6) / 1e6) {
    const now = t;
    const calls = [];
      // input (between frames)
    while (ei < events.length && events[ei].t <= now + 1e-9) {
      const e = events[ei++];
      if (e.type === 'down') {
        tracker.reset();
        tracker.add(now, e.x, 0);
        row.start = e.x;
        row.swiping = false;
      } else if (e.type === 'move') {
        tracker.add(now, e.x, 0);
        if (!row.swiping && Math.abs(e.x - row.start) > 4) {
          // beginSwipe: caught mid-animation it continues from where it is
          row.swiping = true;
          row.tracking = true;
          row.trackX0 = e.x;
          if (row.anim) { row.model = row.offset; row.anim = null; }
          row.initial = row.model;
          calls.push(['swipe', row.initial]);
          depthStart(now);
        }
        if (row.swiping) setOffset(row.initial + (e.x - row.trackX0), now, false, calls);
      } else if (e.type === 'up') {
        const vx = tracker.velocity(now).x;
        if (row.swiping) {
          row.tracking = false;
          row.swiping = false;
          calls.push(['release', vx]);
          const side = row.model > 0 ? 'left' : row.model < 0 ? 'right' : null;
          if (side) {
            const open = revealOpen(side, row.initial, row.model, vx);
            if (open && row.armed && side === 'right') setOffset(FILL, now, true, calls);   // archive
            else setOffset(open ? (side === 'left' ? STRIP.left : -STRIP.right) : 0, now, true, calls);
          }
        }
      } else if (e.type === 'tap') {
        if (row.model !== 0 || row.anim) setOffset(0, now, true, calls);
      }
    }
    // frame: the presented offset
    if (row.anim) {
      const a = row.anim;
      row.offset = a.from + (a.to - a.from) * revealCurve(now - a.t0);
      if (now - a.t0 >= REVEAL_DURATION) { row.offset = a.to; row.anim = null; }
    }
    const animating = !!row.anim;
    const x = row.offset;
    // the strip under the finger: arming the outer action is the haptic, and the spin
    if (row.tracking) {
      const side = x > 0 ? 'left' : x < 0 ? 'right' : null;
      const armed = side ? Math.abs(x) - STRIP[side] > ARM : false;
      if (armed !== row.armed) {
        if (armed) {
          calls.push(['spin', side === 'left' ? 1 : -1]);
          rig.spin(now, side === 'left' ? 1 : -1);
        }
        row.armed = armed;
      }
    }
    const dt = Math.max(0, Math.min(0.05, now - lastNow));
    lastNow = now;
    const v = dt > 0 ? (x - prevX) / dt : 0;
    vel = vel * 0.45 + v * 0.55;
    prevX = x;
    const pull = row.tracking ? x - row.initial : 0;
    let ended = false;
    let moving = null;
    if (rig.active) {  // ChatRow.update: the rig runs while it is active
      moving = rig.update(now, x, vel, pull);
      const still = !row.tracking && !row.anim && Math.abs(vel) < 1;
      if (!moving && still && !rig.rolled) { rig.end(); ended = true; }
    }
    // [now, x, v, pull, tracking, animating, calls, ended]: the inputs at full precision.
    frames.push([now, x, vel, pull, row.tracking ? 1 : 0, animating ? 1 : 0, calls, ended ? 1 : 0]);
    // Every `every`-th frame the rig ran on: everything it computed.
    if (rig.active && moving !== null && index % sc.every === 0) {
      samples.push(roundAll({
        i: index,
        moving,
        rolled: rig.rolled,
        dir: x < -0.5 ? -1 : x > 0.5 ? 1 : Math.sign(vel) || -1,
        glyphs: rig.glyphs.map(readGlyph).map((g) => [g.roll, g.a, g.lift, g.rim, g.shade, g.face, g.layers, g.hidden ? 1 : 0]),
        icons: rig.icons.map(readIcon),
        mask: readMask(parts.lines[0].parentElement),
        linesOrigin: parts.lines[0].parentElement.style.perspectiveOrigin || '',
        lines: rig.lines.map((l) => [l.lean.value, l.el.style.transform ? 0 : 1]),
        disc: readDisc(rig.avatar),
      }));
    }
    index += 1;
  }
  // The geometry as buildTitle / buildAvatar measured it (a fresh rig, begun once to read it).
  const probe = new DepthRig(makeParts(sc));
  probe.begin(0);
  const geometry = roundAll({
    titleX: probe.titleX,
    titleOrigin: probe.titleOrigin,
    glyphs: probe.glyphs.map((p) => p.cx),
    icons: probe.icons.map((p) => p.cx),
    textLeft: parts.lines[0].parentElement.offsetLeft,
    lines: probe.lines.length,
    avatarCenter: probe.avatar.cx,
    avatarHalf: probe.avatar.half,
  });
  probe.end();
  return { name: sc.name, title: sc.title, every: sc.every, geometry, frames, samples };
}

// ---------------------------------------------------------------- scenarios

// Finger paths as events at 120 Hz: ['down' | 'move' | 'up' | 'tap', t (s), x (screen pt)].
function drag(x0, dx, start, duration, ease = 'out') {
  const ev = [];
  const n = Math.max(2, Math.round(duration * 120));
  for (let i = 1; i <= n; i++) {
    const u = i / n;
    const k = ease === 'out' ? 1 - (1 - u) * (1 - u) : u;
    ev.push(['move', +(start + duration * u).toFixed(6), x0 + dx * k]);
  }
  return ev;
}

function hold(x, start, duration) {
  const ev = [];
  const n = Math.round(duration * 120);
  for (let i = 1; i <= n; i++) ev.push(['move', +(start + i / 120).toFixed(6), x]);
  return ev;
}

const scenarios = [
  {
    // Right swipe: the name rolls from its right end, the lines lift their right ends, the disc
    // tilts; let go slowly, the row opens (+130) on the reveal spring; a tap closes it.
    name: 'rightSwipe', title: 'Alex Morgan', every: 4, duration: 3.0, lines: 2, icons: ['verified'],
    input: [['down', 0, 100], ...drag(100, 170, 0, 0.4), ...hold(270, 0.4, 0.12), ['up', 0.53, 270], ['tap', 1.6, 200]],
  },
  {
    // Left swipe past the rim: the disc, then the name letter by letter, roll over the screen's
    // left edge; open at −190 it rests rolled; a tap closes it and they roll back out.
    name: 'leftRim', title: 'Alicia Torres', every: 4, duration: 3.4, lines: 2, icons: ['verified', 'muted'],
    input: [['down', 0, 300], ...drag(300, -215, 0, 0.45), ...hold(85, 0.45, 0.1), ['up', 0.56, 85], ['tap', 1.8, 200]],
  },
  {
    // Full swipe: past 290 pt the archive action arms (the haptic): the letters spin reel by reel
    // and the disc flips; let go, the row fills out to −W − 74.
    name: 'fullSwipe', title: 'Mark', every: 4, duration: 2.6, lines: 2, icons: [],
    input: [['down', 0, 360], ...drag(360, -340, 0, 0.34, 'linear'), ...hold(20, 0.34, 0.2), ['up', 0.55, 20]],
  },
  {
    // Flick: 40 pt in 35 ms; the release follows the flick (−190) — the lean comes from the speed.
    name: 'flick', title: 'Jenny Kim', every: 4, duration: 2.6, lines: 1, icons: ['muted'],
    input: [['down', 0, 280], ...drag(280, -40, 0, 0.035, 'linear'), ['up', 0.04, 240], ['tap', 1.1, 200]],
  },
  {
    // Right, then back through zero to the left: the wave and the leans turn round; let go near 0.
    name: 'reverse', title: 'Sam Wilson', every: 4, duration: 2.6, lines: 2, icons: ['verified'],
    input: [['down', 0, 150], ...drag(150, 80, 0, 0.2), ...drag(230, -140, 0.2, 0.35, 'linear'), ...drag(90, 50, 0.55, 0.25), ['up', 0.82, 140]],
  },
];

const fixed = Number.prototype.toFixed;
const out = [];
try {
  // Full precision in everything DepthRig writes (see the header).
  Number.prototype.toFixed = function fullPrecision() { return String(Number(this)); };
  for (const sc of scenarios) {
    out.push(runScenario(sc));
  }
} finally {
  Number.prototype.toFixed = fixed;
}
process.stdout.write(JSON.stringify({ version: 1, source: 'prototype/src/chats/depth.js', width: W, scenarios: out }));
