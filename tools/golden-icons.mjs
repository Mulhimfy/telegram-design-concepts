// Golden data of the Living Icons (prototype/src/settings/living-icons.js), replayed by the Swift
// port's tests (ios/Standalone/LivingIconsCore) so the two implementations cannot drift.
//
// For every rig in RIGS, at t = i/60 s from 0 to its duration (the last sample is the first one
// at or past it, the frame the player stops on), it records:
//   · raw — what run(t, P, fx, E) asks for: each part's set({ r, x, y, sx, sy, kx, o, cx, cy })
//     with the defaults filled in, dash(v), every E.<ref>.setAttribute, every fx.<name>(...) call;
//   · fx — what the player then draws: the prototype's own LivingIcons class is played against a
//     minimal fake DOM (no browser), and every value its effects write (wave arcs, sparkles,
//     confetti, the typing dots, rays, the paint stroke, paper, flash, halo, glow/hue filters, spin3d,
//     the turning globe, the tile's spring pop and the sheen) is read back as numbers. Number.prototype
//     .toFixed is widened to full precision while recording, so the Swift side is compared to
//     1e-6 instead of the 2–3 digits the DOM attributes are rounded to;
//   · boxes — what each of its parts holds (partBoxes), and for `parts` rigs the tree itself.
// It also records press() (the tile giving under the finger), every piece of the icon files the rigs
// cut (art) and how Telegram's glyphs are cut (cuts: living-icons.js CUTS and STAR_WEDGES).
//
// usage: node tools/golden-icons.mjs > ios/Standalone/LivingIconsCore/Tests/LivingIconsCoreTests/Resources/golden-icons.json
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const ICONS = fileURLToPath(new URL('../prototype/assets/icons/', import.meta.url));
const { RIGS, LivingIcons, CUTS, STAR_WEDGES } = await import('../prototype/src/settings/living-icons.js');

const FPS = 60;
const DIGITS = 1e9;
const num = (v) => {
  const n = typeof v === 'number' ? v : Number(v);
  if (!Number.isFinite(n)) throw new Error(`not a number: ${v}`);
  const r = Math.round(n * DIGITS) / DIGITS;
  return Object.is(r, -0) ? 0 : r;
};
// Every number in an attribute or style string, in order ("translate(1.5 -2) rotate(3)" → [1.5, -2, 3]).
const numbers = (s) => (String(s).match(/-?(?:\d+\.?\d*|\.\d+)(?:e[-+]?\d+)?/gi) || []).map(Number).map(num);

// Full precision while recording (the player only uses toFixed to format attributes).
Number.prototype.toFixed = function () { return String(this.valueOf()); };

// ------------------------------------------------------------------ a minimal DOM

const camel = (s) => s.trim().replace(/-([a-z])/g, (_, c) => c.toUpperCase());
function makeStyle() {
  const style = {};
  Object.defineProperty(style, 'cssText', {
    enumerable: false,
    set(text) {
      for (const k of Object.keys(style)) delete style[k];
      for (const decl of String(text).split(';')) {
        const i = decl.indexOf(':');
        if (i > 0) style[camel(decl.slice(0, i))] = decl.slice(i + 1).trim();
      }
    },
  });
  style.setProperty = () => {};
  return style;
}

class FakeElement {
  constructor(tagName) {
    this.tagName = tagName;
    this.attrMap = new Map();
    this.children = [];
    this.parentElement = null;
    this.style = makeStyle();
    this.id = '';
    this.box = { left: 0, top: 0, width: 0, height: 0 };
  }
  get attributes() { return [...this.attrMap].map(([name, value]) => ({ name, value })); }
  setAttribute(k, v) { this.attrMap.set(k, String(v)); }
  getAttribute(k) { return this.attrMap.has(k) ? this.attrMap.get(k) : null; }
  hasAttribute(k) { return this.attrMap.has(k); }
  removeAttribute(k) { this.attrMap.delete(k); }
  appendChild(c) { c.remove(); c.parentElement = this; this.children.push(c); return c; }
  insertBefore(c, ref) {
    c.remove();
    c.parentElement = this;
    const i = ref ? this.children.indexOf(ref) : -1;
    if (i < 0) this.children.push(c); else this.children.splice(i, 0, c);
    return c;
  }
  get firstChild() { return this.children[0] || null; }
  remove() {
    if (!this.parentElement) return;
    const s = this.parentElement.children;
    s.splice(s.indexOf(this), 1);
    this.parentElement = null;
  }
  matches(sel) {
    return sel.split(',').map((s) => s.trim()).some((s) => (s.startsWith('[') ? this.attrMap.has(s.slice(1, -1)) : this.tagName === s));
  }
  querySelectorAll(sel) {
    const out = [];
    const walk = (e) => { for (const c of e.children) { if (c.matches(sel)) out.push(c); walk(c); } };
    walk(this);
    return out;
  }
  closest(sel) {
    for (let e = this; e; e = e.parentElement) if (e.matches(sel)) return e;
    return null;
  }
  get offsetLeft() { return this.box.left; }
  get offsetTop() { return this.box.top; }
  get offsetWidth() { return this.box.width; }
  get offsetHeight() { return this.box.height; }
}

// Just enough XML for the icon files: elements, attributes, self-closing tags, <?…?> and comments.
function parseXML(text) {
  const root = new FakeElement('#document');
  let cur = root;
  const re = /<!--[\s\S]*?-->|<\?[\s\S]*?\?>|<\/([\w:-]+)\s*>|<([\w:-]+)((?:\s+[\w:-]+\s*=\s*"[^"]*")*)\s*(\/?)>/g;
  let m;
  while ((m = re.exec(text))) {
    if (m[1]) { cur = cur.parentElement || root; continue; }
    if (!m[2]) continue;
    const e = new FakeElement(m[2]);
    for (const a of m[3].matchAll(/([\w:-]+)\s*=\s*"([^"]*)"/g)) e.setAttribute(a[1], a[2]);
    cur.appendChild(e);
    if (!m[4]) cur = e;
  }
  return root;
}

globalThis.document = {
  createElementNS: (_, tag) => new FakeElement(tag),
  createElement: (tag) => new FakeElement(tag),
};
globalThis.DOMParser = class { parseFromString(text) { return parseXML(text); } };
globalThis.getComputedStyle = () => ({ color: '#fff' });
globalThis.fetch = async (url) => ({ text: async () => readFileSync(url, 'utf8') });

// A Settings row as settings-screen.js builds it: a 30 × 30 tile at (16, 11) in a 52 pt row with
// the glyph inside it, or (accent rows, Money) the glyph alone at (16, 11).
function makeRow(icon) {
  const el = new FakeElement('div');
  el.box = { left: 0, top: 0, width: 382, height: 52.33 };
  const tiled = icon.startsWith('ic-');
  const row = { el, icon, tile: null, glyph: null, color: undefined, tileColor: tiled ? '#ff9f0a' : null };
  if (tiled) {
    row.tile = el.appendChild(new FakeElement('div'));
    row.tile.box = { left: 16, top: 11, width: 30, height: 30 };
    row.glyph = row.tile.appendChild(new FakeElement('span'));
    row.glyph.box = { left: 0, top: 0, width: 30, height: 30 };
  } else {
    row.glyph = el.appendChild(new FakeElement(icon === 'money' ? 'div' : 'span'));
    row.glyph.box = { left: 16, top: 11, width: 30, height: 30 };
    if (icon === 'money') {
      // settings-screen.js moneyIcon(): the gem, and the sparkle in a [data-inner] group (refs.inner).
      const svg = row.glyph.appendChild(new FakeElement('svg'));
      svg.appendChild(new FakeElement('image'));
      const inner = svg.appendChild(new FakeElement('g')).appendChild(new FakeElement('g'));
      inner.setAttribute('data-inner', '');
      inner.appendChild(new FakeElement('image'));
    }
  }
  return row;
}

// ------------------------------------------------------------------ raw rig outputs

const PART_KEYS = ['r', 'x', 'y', 'sx', 'sy', 'kx', 'o', 'cx', 'cy'];
const PART_DEFAULTS = { r: 0, x: 0, y: 0, sx: 1, sy: 1, kx: 0, o: 1, cx: 15, cy: 15 };

function rawFrame(rig, t) {
  const frame = { parts: {}, dash: {}, attrs: {}, fx: [] };
  const P = new Proxy({}, {
    get: (_, name) => ({
      set: (p = {}) => { frame.parts[name] = PART_KEYS.map((k) => num(p[k] ?? PART_DEFAULTS[k])); },
      dash: (v) => { frame.dash[name] = num(v); },
    }),
  });
  const fx = new Proxy({}, {
    get: (_, name) => (...args) => { frame.fx.push([name, ...args.map((a) => (typeof a === 'number' ? num(a) : a))]); },
  });
  const E = new Proxy({}, {
    get: (_, ref) => ({ setAttribute: (k, v) => { frame.attrs[`${ref}.${k}`] = numbers(v); } }),
  });
  rig.run(t, P, fx, E);
  return frame;
}

// ------------------------------------------------------------------ what the player draws

const transformOf = (s) => (s ? numbers(s) : []);
// svg.style.filter: '' | 'drop-shadow(0 0 Rpx rgba(255,255,255,A))' (glow) | 'hue-rotate(Ddeg) saturate(1.4)' (hue)
const filterOf = (s) => {
  if (!s) return [];
  const v = numbers(s);
  return s.startsWith('drop-shadow') ? ['glow', v[2], v[6]] : ['hue', v[0], v[1]];
};
function drawnFrame(c) {
  const { fx, svg, sheen, tile, row, refs } = c;
  const out = {};
  if (tile) out.tile = transformOf(tile.style.transform);
  if (sheen) out.sheen = transformOf(sheen.style.transform);
  out.filter = filterOf(svg.style.filter);
  out.spin = transformOf(c.rig.element ? row.glyph.style.transform : svg.style.transform);
  if (fx._waves) out.waves = fx._waves.map((w) => [num(w.a.getAttribute('opacity')), ...transformOf(w.a.getAttribute('transform'))]);
  if (fx._halo) out.halo = [num(fx._halo.style.opacity), ...transformOf(fx._halo.style.transform)];
  if (fx._sp) out.sparkles = fx._sp.map((p) => [num(p.s.style.opacity), ...transformOf(p.s.style.transform)]);
  if (fx._cf) out.confetti = fx._cf.map((p) => [num(p.s.style.opacity), ...transformOf(p.s.style.transform)]);
  if (refs.dots) out.dots = refs.dots.map((d) => transformOf(d.getAttribute('transform')));
  if (fx._rays) out.rays = fx._rays.map((l) => num(l.getAttribute('opacity')));
  if (fx._stroke) out.stroke = [num(fx._stroke.getAttribute('stroke-dashoffset')), num(fx._stroke.getAttribute('opacity'))];
  if (fx._flash) out.flash = [num(fx._flash.getAttribute('opacity')), num(fx._flash.getAttribute('r'))];
  const paper = svg.children.find((e) => e.tagName === 'rect' && e.getAttribute('rx') === '1.2');
  if (paper) out.paper = [num(paper.getAttribute('y')), num(paper.getAttribute('opacity'))];
  // The turning globe: its two meridians' half-widths and the second's opacity, the turning globe's and the
  // banded one's opacities (the cross-fade).
  const globe = refs.globe;
  if (globe) {
    const m = globe.meridians;
    out.globe = [num(m[0].getAttribute('data-rx') ?? 0), num(m[1].getAttribute('data-rx') ?? 0), num(m[1].getAttribute('opacity') ?? 1), num(globe.turning.getAttribute('opacity')), num(globe.rest.getAttribute('opacity') ?? 1)];
  }
  if (refs.inner) out.inner = transformOf(refs.inner.getAttribute('transform'));
  if (refs.shine) out.shine = [num(refs.shine.getAttribute('stroke-dashoffset')), num(refs.shine.getAttribute('opacity') ?? 1)];
  if (refs.mark) out.mark = numbers(refs.mark.getAttribute('d'));
  return out;
}

// The tree play() cuts a `parts` rig into: groups (by part name), each path with the number of file
// pieces joined in it, its fill rule and stroke; the folder's paper. (Root-level effect elements are left out.)
function structure(c) {
  const nameOf = new Map(Object.entries(c.P).map(([name, p]) => [p.el, name]));
  const visit = (e) => {
    if (e.tagName === 'g') return { group: nameOf.get(e) ?? null, children: e.children.map(visit).filter(Boolean) };
    if (e.tagName === 'path') return { pieces: (e.getAttribute('d').match(/[Mm]/g) || []).length, evenOdd: e.getAttribute('fill-rule') === 'evenodd', stroke: e.getAttribute('stroke-width') ? Number(e.getAttribute('stroke-width')) : null };
    if (e.tagName === 'circle') return { pieces: 1, evenOdd: false, stroke: e.getAttribute('stroke-width') ? Number(e.getAttribute('stroke-width')) : null };
    if (e.tagName === 'ellipse') return { meridian: true };
    return null;
  };
  return c.svg.children.map((e) => (e.tagName === 'rect' && e.getAttribute('rx') === '1.2' ? { paper: true } : e.tagName === 'g' ? visit(e) : null)).filter(Boolean);
}

// What each part holds, for every rig (parts and build(c) alike): the box of every shape under the named part —
// its bounds (a stroke grown by half its width), cut by its own clip and the clips of the groups between it and
// the part; a masked rect (a cut-out) counts with its mask's white shapes only. Transforms are left out (the icon
// at rest). ArtworkTests measures the Swift tree the same way, so web and native cut every icon into the same parts.
const ALL = [-Infinity, -Infinity, Infinity, Infinity];
const join = (a, b) => (!a ? b : !b ? a : [Math.min(a[0], b[0]), Math.min(a[1], b[1]), Math.max(a[2], b[2]), Math.max(a[3], b[3])]);
const meet = (a, b) => {
  if (!a || !b) return null;
  const r = [Math.max(a[0], b[0]), Math.max(a[1], b[1]), Math.min(a[2], b[2]), Math.min(a[3], b[3])];
  return r[0] <= r[2] && r[1] <= r[3] ? r : null;
};
// A box under an SVG transform list of translate() / scale() (the only ones a clip here has).
function transformBox(box, transform) {
  let m = [1, 0, 0, 1, 0, 0];
  for (const [, fn, args] of transform.matchAll(/(\w+)\(([^)]*)\)/g)) {
    const v = args.split(/[\s,]+/).filter(Boolean).map(Number);
    const n = fn === 'translate' ? [1, 0, 0, 1, v[0], v[1] ?? 0] : fn === 'scale' ? [v[0], 0, 0, v[1] ?? v[0], 0, 0] : null;
    if (!n) throw new Error(`transform ${fn}`);
    m = [m[0] * n[0] + m[2] * n[1], m[1] * n[0] + m[3] * n[1], m[0] * n[2] + m[2] * n[3], m[1] * n[2] + m[3] * n[3], m[0] * n[4] + m[2] * n[5] + m[4], m[1] * n[4] + m[3] * n[5] + m[5]];
  }
  const pts = [[box[0], box[1]], [box[2], box[1]], [box[0], box[3]], [box[2], box[3]]].map(([x, y]) => [m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]]);
  return [Math.min(...pts.map((p) => p[0])), Math.min(...pts.map((p) => p[1])), Math.max(...pts.map((p) => p[0])), Math.max(...pts.map((p) => p[1]))];
}
// The bounds of what one element draws (a lone moveto draws nothing).
function shapeBox(e) {
  let box = null;
  if (e.tagName === 'path') {
    for (const b of pathBounds(e.getAttribute('d'))) if (b[0] !== b[2] || b[1] !== b[3]) box = join(box, b);
  } else if (e.tagName === 'circle' || e.tagName === 'ellipse') {
    const cx = Number(e.getAttribute('cx')), cy = Number(e.getAttribute('cy'));
    const rx = Number(e.getAttribute('r') ?? e.getAttribute('rx')), ry = Number(e.getAttribute('r') ?? e.getAttribute('ry'));
    box = [cx - rx, cy - ry, cx + rx, cy + ry];
  }
  const sw = e.getAttribute('fill') === 'none' ? Number(e.getAttribute('stroke-width')) : 0;
  return box && sw ? [box[0] - sw / 2, box[1] - sw / 2, box[2] + sw / 2, box[3] + sw / 2] : box;
}
function partBoxes(c) {
  const byId = (e, id) => {
    if (e.id === id) return e;
    for (const k of e.children) { const f = byId(k, id); if (f) return f; }
    return null;
  };
  const ref = (e, attr) => {
    const v = e.getAttribute(attr);
    return v ? byId(c.svg, /url\(#([^)]+)\)/.exec(v)[1]) : null;
  };
  const clipOf = (e) => {
    const clip = ref(e, 'clip-path');
    if (!clip) return ALL;
    let box = null;
    for (const p of clip.children) {
      let b = shapeBox(p);
      if (b && p.getAttribute('transform')) b = transformBox(b, p.getAttribute('transform'));
      box = join(box, b);
    }
    return box;
  };
  const visit = (e, clip, whiteOnly) => {
    let box = null;
    for (const k of e.children) {
      const kClip = meet(clip, clipOf(k));
      if (k.tagName === 'g') box = join(box, visit(k, kClip, whiteOnly));
      else if (k.tagName === 'path' || k.tagName === 'circle' || k.tagName === 'ellipse') {
        if (whiteOnly && k.getAttribute('fill') !== '#fff' && k.getAttribute('stroke') !== '#fff') continue;
        box = join(box, meet(shapeBox(k), kClip));
      } else if (k.tagName === 'rect' && k.getAttribute('mask')) {
        box = join(box, visit(ref(k, 'mask'), kClip, true));
      }
    }
    return box;
  };
  return Object.fromEntries(Object.entries(c.P).map(([name, p]) => [name, visit(p.el, ALL, false)?.map(num) ?? null]));
}

// ------------------------------------------------------------------ record

const rigs = [];
for (const [name, rig] of Object.entries(RIGS)) {
  const player = new LivingIcons({ iconURL: (icon) => `${ICONS}${icon}.svg` });
  const row = makeRow(name);
  await player.play(row, 0);
  const c = player.current;
  if (!c) throw new Error(`${name}: did not play`);
  const boxes = partBoxes(c);
  // Frame i is drawn at t = i/60; the player stops (restoring the static icon) on the first
  // frame at or past the duration, after drawing it.
  const drawn = [drawnFrame(c)];
  let frames = 1;
  for (let i = 1; player.current; i++) {
    if (i > 600) throw new Error(`${name}: never stopped`);
    player.update(i / FPS);
    drawn.push(drawnFrame(c));
    frames = i + 1;
  }
  const raw = [];
  for (let i = 0; i < frames; i++) raw.push(rawFrame(rig, i / FPS));
  const flags = Object.keys(rig).filter((k) => rig[k] === true);
  const entry = { name, duration: rig.duration, flags, parts: Object.keys(c.P), frames, raw, drawn, boxes };
  if (rig.parts && !rig.build) entry.structure = structure(c);
  rigs.push(entry);
}

// ------------------------------------------------------------------ artwork bounds
// Every piece of every icon file the Swift artwork reads (prototype/assets/icons, split at movetos as
// parse() does) and the geometry rebuilt in living-icons.js, measured here by an independent path
// reader, so the Swift SVG parser is checked against it. Curves and arcs are sampled densely.

function pathBounds(d) {
  const toks = d.match(/[MmLlHhVvCcSsQqTtAaZz]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?/g) || [];
  const pieces = [];
  let box = null;
  let x = 0, y = 0, sx = 0, sy = 0, cmd = null, i = 0, lc = null, lq = null;
  const take = () => Number(toks[i++]);
  const isNum = () => i < toks.length && !/^[A-Za-z]$/.test(toks[i]);
  const flag = () => { const t = toks[i]; if (t.length > 1 && (t[0] === '0' || t[0] === '1')) { toks[i] = t.slice(1); return t[0] === '1'; } i++; return t === '1'; };
  const pt = (px, py) => { if (!box) return; box[0] = Math.min(box[0], px); box[1] = Math.min(box[1], py); box[2] = Math.max(box[2], px); box[3] = Math.max(box[3], py); };
  const cubic = (x1, y1, x2, y2, x3, y3) => {
    for (let k = 1; k <= 400; k++) {
      const t = k / 400, u = 1 - t;
      pt(u * u * u * x + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t * x3, u * u * u * y + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t * y3);
    }
  };
  while (i < toks.length) {
    if (!isNum()) cmd = toks[i++];
    const rel = cmd === cmd.toLowerCase();
    const ox = rel ? x : 0, oy = rel ? y : 0;
    switch (cmd.toUpperCase()) {
      case 'M':
        x = take() + ox; y = take() + oy; sx = x; sy = y;
        box = [x, y, x, y]; pieces.push(box);
        cmd = rel ? 'l' : 'L'; lc = lq = null; break;
      case 'L': x = take() + ox; y = take() + oy; pt(x, y); lc = lq = null; break;
      case 'H': x = take() + ox; pt(x, y); lc = lq = null; break;
      case 'V': y = take() + oy; pt(x, y); lc = lq = null; break;
      case 'C': { const a = [take() + ox, take() + oy, take() + ox, take() + oy, take() + ox, take() + oy]; cubic(...a); x = a[4]; y = a[5]; lc = [a[2], a[3]]; lq = null; break; }
      case 'S': { const r = lc ? [2 * x - lc[0], 2 * y - lc[1]] : [x, y]; const a = [take() + ox, take() + oy, take() + ox, take() + oy]; cubic(r[0], r[1], ...a); x = a[2]; y = a[3]; lc = [a[0], a[1]]; lq = null; break; }
      case 'Q': { const q = [take() + ox, take() + oy]; const e = [take() + ox, take() + oy]; cubic(x + 2 / 3 * (q[0] - x), y + 2 / 3 * (q[1] - y), e[0] + 2 / 3 * (q[0] - e[0]), e[1] + 2 / 3 * (q[1] - e[1]), e[0], e[1]); x = e[0]; y = e[1]; lq = q; lc = null; break; }
      case 'T': { const q = lq ? [2 * x - lq[0], 2 * y - lq[1]] : [x, y]; const e = [take() + ox, take() + oy]; cubic(x + 2 / 3 * (q[0] - x), y + 2 / 3 * (q[1] - y), e[0] + 2 / 3 * (q[0] - e[0]), e[1] + 2 / 3 * (q[1] - e[1]), e[0], e[1]); x = e[0]; y = e[1]; lq = q; lc = null; break; }
      case 'A': {
        let rx = Math.abs(take()), ry = Math.abs(take());
        const phi = take() * Math.PI / 180, fa = flag(), fs = flag();
        const x2 = take() + ox, y2 = take() + oy;
        if (rx === 0 || ry === 0) { pt(x2, y2); x = x2; y = y2; break; }
        const c = Math.cos(phi), s = Math.sin(phi);
        const dx = (x - x2) / 2, dy = (y - y2) / 2;
        const x1p = c * dx + s * dy, y1p = -s * dx + c * dy;
        const lam = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
        if (lam > 1) { rx *= Math.sqrt(lam); ry *= Math.sqrt(lam); }
        let co = Math.sqrt(Math.max(0, (rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p) / (rx * rx * y1p * y1p + ry * ry * x1p * x1p)));
        if (fa === fs) co = -co;
        const cxp = co * rx * y1p / ry, cyp = -co * ry * x1p / rx;
        const cx = c * cxp - s * cyp + (x + x2) / 2, cy = s * cxp + c * cyp + (y + y2) / 2;
        const ang = (ux, uy, vx, vy) => Math.atan2(ux * vy - uy * vx, ux * vx + uy * vy);
        const t1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry);
        let dt = ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry);
        if (!fs && dt > 0) dt -= 2 * Math.PI;
        if (fs && dt < 0) dt += 2 * Math.PI;
        for (let k = 1; k <= 400; k++) {
          const t = t1 + (dt * k) / 400;
          pt(cx + rx * Math.cos(t) * c - ry * Math.sin(t) * s, cy + rx * Math.cos(t) * s + ry * Math.sin(t) * c);
        }
        x = x2; y = y2; lc = lq = null; break;
      }
      case 'Z': x = sx; y = sy; lc = lq = null; break;
      default: i++;
    }
  }
  return pieces.map((b) => b.map(num));
}

const attrOf = (tag, name) => { const m = tag.match(new RegExp(`\\s${name}="([^"]*)"`)); return m ? m[1] : null; };
function fileBounds(name) {
  const text = readFileSync(`${ICONS}${name}.svg`, 'utf8');
  const out = [];
  for (const m of text.matchAll(/<(path|circle|ellipse)\b[^>]*>/g)) {
    const tag = m[0];
    if (m[1] === 'path') out.push(pathBounds(attrOf(tag, 'd')));
    else {
      const cx = Number(attrOf(tag, 'cx')), cy = Number(attrOf(tag, 'cy'));
      const rx = Number(attrOf(tag, 'r') ?? attrOf(tag, 'rx')), ry = Number(attrOf(tag, 'r') ?? attrOf(tag, 'ry'));
      out.push([[cx - rx, cy - ry, cx + rx, cy + ry].map(num)]);
    }
  }
  return out;
}
// The icon files the rigs cut (every icon but the padlock, My Profile and Saved Messages, rebuilt by hand, and Money).
const artFiles = [
  'ic-bell', 'ic-phone', 'ic-folder', 'ic-data', 'ic-devices', 'ic-proxy', 'ic-stars', 'ic-premium', 'ic-power', 'ic-language',
  'ic-gift', 'ic-business', 'ic-ask', 'ic-faq', 'ic-features', 'ic-appearance', 'set-emoji-status', 'set-avatar', 'set-covercolor',
];
const art = { files: {}, paths: {} };
for (const name of artFiles) art.files[name] = fileBounds(name);
// The geometry rebuilt by hand (living-icons.js, "geometry"), from the module's own source.
const source = readFileSync(fileURLToPath(new URL('../prototype/src/settings/living-icons.js', import.meta.url)), 'utf8');
for (const k of ['LOCK_BODY', 'LOCK_SHACKLE', 'PROFILE_BUST']) {
  const m = source.match(new RegExp(`const ${k} = '([^']*)'`));
  if (!m) throw new Error(`${k} not found`);
  art.paths[k] = { d: m[1], bounds: pathBounds(m[1]) };
}

// press(): the tile gives under the finger and springs back (0.6 s).
const pressPlayer = new LivingIcons({ iconURL: (icon) => `${ICONS}${icon}.svg` });
const pressRow = makeRow('ic-bell');
pressPlayer.press(pressRow, 0);
const press = [];
for (let i = 0; i <= 40; i++) {
  pressPlayer.update(i / FPS);
  press.push(transformOf(pressRow.tile.style.transform));
}

// How Telegram's glyphs are cut (living-icons.js CUTS, STAR_WEDGES): the Swift constants must be these.
const cuts = { ...CUTS, starWedges: STAR_WEDGES };

process.stdout.write(JSON.stringify({ version: 2, fps: FPS, rigs, press, art, cuts }));
