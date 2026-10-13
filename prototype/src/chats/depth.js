// Depth Swipe: what is new. Pull a chat and it comes off the surface in 3D:
//   · the name becomes extruded 3D type whose letters roll back on their own axis, like the
//     reels of Telegram's rolling counters, in a wave that starts on the side the row moves
//     toward; their widths never change, so the name stays in one piece;
//   · each line of the message leans as one rigid plate, its leading end lifting, a beat later;
//   · the photo becomes a thick disc that tilts with the pull, the picture sitting deeper than
//     its rim (parallax) and a glint crossing it;
//   · swiped to the left, nothing is cut off by the screen edge: the edge is the rounded rim of
//     the surface, and the disc, then the name letter by letter, roll over it into the depth —
//     each one turns away on the rim (its thickness and extrusion showing, the light leaving its
//     face) and sinks behind it; swiped back, they roll out of the edge the same way. The
//     message text fades into the rim;
//   · the full-swipe moment (the haptic) spins the letters once, reel by reel, and flips the
//     disc like a coin.
// When the row settles everything rolls back flat with one soft overshoot and the flat text
// takes over again (crisp at rest, nothing 3D left in the page).
//
// Timing: the springs answer in ~0.16–0.22 s and the lean comes from the velocity, so a swipe's
// first ~20–30 pt already shows it. On a left swipe the disc reaches the rim after ~10 pt and
// takes ~55 pt more to go over it; each letter takes the same 55 pt as it gets there.

import { SpringParams, SpringValue } from '../core/spring.js';
import { diag, diagOn } from '../core/diag.js';

const clamp = (x, a = 0, b = 1) => Math.max(a, Math.min(b, x));
const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a)); return t * t * (3 - 2 * t); };
const DEG = Math.PI / 180;
const HALF = Math.PI / 2;

export const DepthLook = {
  v0: 620,                    // pt/s: motion lean = max · tanh(|v| / v0)
  holdDistance: 60,           // pt of pull for most of the "tension" lean while the finger holds the row
  perspective: 330,
  title: { roll: 40, hold: 18, lift: 4, depth: 6, layers: 7, stagger: 0.022, shade: 0.4, spring: SpringParams.fromResponse(0.17, 0.5) },
  lines: { lean: 18, hold: 8, lift: 0, delay: 0.03, stagger: 0.035, spring: SpringParams.fromResponse(0.22, 0.58) },
  avatar: { lean: 48, hold: 22, lift: 7, depth: 6, layers: 6, delay: 0.008, spring: SpringParams.fromResponse(0.22, 0.58), parallax: 7 },
  // Left swipes: the rim at the screen's left edge. A piece whose flat centre has gone d pt past
  // the hinge line is d / radius rad round it (on screen at hinge − radius·sin, radius·(1 − cos)
  // deep); it fades out between fade[0] and fade[1] degrees and is gone behind the rim after.
  edge: { hinge: 36, radius: 34, shade: 0.5, fade: [62, 90], flipBy: 0.68 },
  spin: { duration: 0.56, stagger: 0.03 },                        // the full-swipe moment
};

// Angles in degrees: at rest within 0.02° (SpringValue's default is for points).
function spring(params) {
  const s = new SpringValue(0, params);
  s.epsilon = 0.02;
  return s;
}

const reduceMotion = typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;

// Grapheme clusters, or words for scripts whose letters join (Hebrew, Arabic, Indic…):
// splitting those would break their shaping.
const JOINING = /[֐-ࣿऀ-෿יִ-﷿ﹰ-﻿]/;
function units(text) {
  if (JOINING.test(text)) return text.split(/(\s+)/).filter(Boolean);
  if (typeof Intl !== 'undefined' && Intl.Segmenter) return [...new Intl.Segmenter(undefined, { granularity: 'grapheme' }).segment(text)].map((s) => s.segment);
  return Array.from(text);
}

const ease = (u) => (u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2);

export class DepthRig {
  // parts: { title (span holding only the name), lines: [message line elements],
  //          avatar (the avatar element), avatarColor ([r,g,b] 0…1 for its rim), dark }
  constructor(parts) {
    this.parts = parts;
    this.active = false;
    this.samples = [];   // { t, v, x } of the row, newest last
    this.enabled = !reduceMotion;
    this.spinT0 = null;
  }

  // Row velocity / offset at time t (linear between samples).
  sample(t) {
    const s = this.samples;
    if (!s.length) return { v: 0, x: 0 };
    if (t >= s[s.length - 1].t) return s[s.length - 1];
    for (let i = s.length - 1; i > 0; i--) {
      if (s[i - 1].t <= t) {
        const a = s[i - 1], b = s[i];
        const u = (t - a.t) / Math.max(1e-6, b.t - a.t);
        return { v: a.v + (b.v - a.v) * u, x: a.x + (b.x - a.x) * u };
      }
    }
    return s[0];
  }

  begin(now) {
    if (!this.enabled) {
      diag('depth-off', { reduceMotion });
      return;
    }
    // Still running from the last move: it carries on, unless its letters left the page (the
    // row was redrawn), then it starts afresh.
    if (this.active && this.titleLayer && !this.titleLayer.isConnected) {
      diag('depth-detached', { title: this.stats?.title });
      this.end();
    }
    if (this.active) {
      if (this.stats) this.stats.continued++;
      return;
    }
    this.active = true;
    this.samples = [];
    this.spinT0 = null;
    this.buildTitle();
    this.buildLines();
    this.buildAvatar();
    // Field numbers for this run of the rig (core/diag.js).
    this.stats = !diagOn ? null : { title: (this.parts.title?.textContent || '').slice(0, 24), glyphs: this.glyphs?.length || 0, frames: 0, minX: 0, maxX: 0, maxRim: 0, maxRoll: 0, continued: 0, peak: null, peakX: 0 };
  }

  // ---------------------------------------------------------------- building

  buildTitle() {
    const host = this.parts.title;
    if (!host || !host.firstChild) return;
    const L = DepthLook.title;
    const text = host.textContent;
    const box = host.getBoundingClientRect();
    // Every letter where the browser put it (kerning kept); the 3D letters go on top.
    const range = document.createRange();
    const node = host.firstChild;
    const pieces = units(text);
    const k = host.offsetWidth / Math.max(1, box.width);   // client px → layout px (scaled previews)
    const layer = document.createElement('div');
    layer.className = 'depth-title';
    layer.style.cssText = `position:absolute;left:0;top:0;width:${host.offsetWidth}px;height:${host.offsetHeight}px;perspective:${DepthLook.perspective}px;pointer-events:none`;
    const face = getComputedStyle(host).color;
    // The extrusion: lit next to the face, darker toward the back.
    const ramp = (u) => {
      const [a, b] = this.parts.dark ? [[200, 200, 206], [58, 58, 62]] : [[64, 64, 68], [158, 158, 164]];
      return `rgb(${a.map((v, i) => Math.round(v + (b[i] - v) * u)).join(',')})`;
    };
    const shadeColor = this.parts.dark ? '#55555b' : '#9a9aa0';
    this.glyphs = [];
    let at = 0;
    for (const p of pieces) {
      let r = null;
      try {
        range.setStart(node, at);
        range.setEnd(node, at + p.length);
        r = range.getBoundingClientRect();
      } catch (_) { r = null; }
      at += p.length;
      if (!r || !p.trim()) continue;
      const g = document.createElement('span');
      const x = (r.left - box.left) * k;
      const w = r.width * k;
      g.style.cssText = `position:absolute;left:${x.toFixed(2)}px;top:0;width:${Math.max(1, w).toFixed(2)}px;height:100%;transform-style:preserve-3d;will-change:transform;white-space:pre;transform-origin:50% 55%`;
      for (let j = L.layers; j >= 1; j--) {
        const s = document.createElement('span');
        s.textContent = p;
        s.style.cssText = `position:absolute;left:0;top:0;color:${ramp((j - 1) / Math.max(1, L.layers - 1))};transform:translateZ(${(-j * L.depth / L.layers).toFixed(2)}px)`;
        g.appendChild(s);
      }
      const f = document.createElement('span');
      f.textContent = p;
      f.style.cssText = `position:absolute;left:0;top:0;color:${face}`;
      g.appendChild(f);
      // Rolled away from the light the face darkens: its copy in shadow fades in.
      const sh = document.createElement('span');
      sh.textContent = p;
      sh.style.cssText = `position:absolute;left:0;top:0;color:${shadeColor};opacity:0;transform:translateZ(0.05px)`;
      g.appendChild(sh);
      layer.appendChild(g);
      this.glyphs.push({ el: g, shade: sh, face: f, layers: [...g.children].slice(0, L.layers), cx: x + w / 2, roll: spring(L.spring), last: '', lastShade: '', op: '', hidden: false });
    }
    if (getComputedStyle(host).position === 'static') host.style.position = 'relative';
    host.appendChild(layer);
    this.titleLayer = layer;
    // Where the name sits in the row (flat, row at rest), for the rim.
    this.titleX = host.offsetLeft + (host.offsetParent ? host.offsetParent.offsetLeft : 0);
    this.titleOrigin = host.offsetWidth / 2;
    // The badges after the name roll over the rim as well.
    this.icons = (this.parts.icons || []).filter((e) => e.offsetWidth > 0).map((e) => ({
      el: e, cx: e.offsetLeft + e.offsetWidth / 2 + (e.offsetParent ? e.offsetParent.offsetLeft : 0), last: '',
    }));
    this.titleColor = host.style.color;
    host.style.color = 'transparent';   // the flat name keeps its place; the 3D one shows
  }

  buildLines() {
    const lines = this.parts.lines || [];
    this.lines = lines.map((el) => ({ el, lean: spring(DepthLook.lines.spring), last: '' }));
    if (lines[0]) lines[0].parentElement.style.perspective = `${DepthLook.perspective}px`;
    for (const l of this.lines) l.el.style.willChange = 'transform';
  }

  buildAvatar() {
    const av = this.parts.avatar;
    if (!av) return;
    const A = DepthLook.avatar;
    const c = this.parts.avatarColor || [0.4, 0.4, 0.45];
    const shade = (k) => `rgb(${c.map((v) => Math.round(v * 255 * k)).join(',')})`;
    // The disc: rim slices behind the face, the picture inset in it, a glint on top.
    const disc = document.createElement('div');
    disc.className = 'depth-disc';
    disc.style.cssText = 'position:absolute;inset:0;transform-style:preserve-3d;will-change:transform;pointer-events:none';
    for (let j = A.layers; j >= 1; j--) {
      const s = document.createElement('div');
      const lit = 0.55 + 0.25 * (1 - j / A.layers);
      s.style.cssText = `position:absolute;inset:0;border-radius:50%;background:${shade(lit)};transform:translateZ(${(-j * A.depth / A.layers).toFixed(2)}px)`;
      disc.appendChild(s);
    }
    // The back: the same picture (one photo, both sides — as on the glass avatar).
    const pic = av.querySelector('.avatar-pic');
    const back = document.createElement('div');
    back.style.cssText = `position:absolute;inset:0;border-radius:50%;overflow:hidden;backface-visibility:hidden;-webkit-backface-visibility:hidden;transform:translateZ(${(-A.depth - 0.05).toFixed(2)}px) rotateY(180deg)`;
    if (pic) {
      const b = pic.cloneNode(true);
      b.style.visibility = 'visible';
      back.appendChild(b);
    }
    const backShade = document.createElement('div');
    backShade.style.cssText = 'position:absolute;inset:0;border-radius:50%;box-shadow:inset 0 0 0 0.75px rgba(255,255,255,0.3),inset 0 0 8px rgba(0,0,0,0.3)';
    back.appendChild(backShade);
    disc.insertBefore(back, disc.firstChild);
    const face = document.createElement('div');
    face.style.cssText = 'position:absolute;inset:0;border-radius:50%;overflow:hidden;backface-visibility:hidden;-webkit-backface-visibility:hidden';
    const inner = pic ? pic.cloneNode(true) : document.createElement('div');
    inner.style.position = 'absolute';
    inner.style.inset = '0';
    inner.style.willChange = 'transform';
    face.appendChild(inner);
    const rim = document.createElement('div');
    rim.style.cssText = 'position:absolute;inset:0;border-radius:50%;box-shadow:inset 0 0 0 0.75px rgba(255,255,255,0.35),inset 0 0 6px rgba(0,0,0,0.25)';
    face.appendChild(rim);
    const glint = document.createElement('div');
    glint.style.cssText = 'position:absolute;inset:-30%;opacity:0;background:linear-gradient(105deg,rgba(255,255,255,0) 38%,rgba(255,255,255,0.55) 50%,rgba(255,255,255,0) 62%);will-change:transform,opacity';
    face.appendChild(glint);
    const dim = document.createElement('div');
    dim.style.cssText = 'position:absolute;inset:0;border-radius:50%;background:#000;opacity:0';
    face.appendChild(dim);
    disc.appendChild(face);
    av.style.perspective = `${DepthLook.perspective}px`;
    av.style.zIndex = '1';   // the disc stays in front of the message while it moves
    av.appendChild(disc);
    if (pic) pic.style.visibility = 'hidden';
    this.avatar = { el: av, disc, inner, glint, dim, pic, lean: spring(A.spring), last: '', cx: av.offsetLeft + av.offsetWidth / 2, half: av.offsetWidth / 2, origin: '' };
  }

  // ---------------------------------------------------------------- the full-swipe moment

  // dir: +1 / −1, the way the row is going.
  spin(now, dir) {
    if (!this.active) return;
    this.spinT0 = now;
    this.spinDir = dir;
  }

  spinAngle(now, order) {
    if (this.spinT0 == null) return 0;
    const S = DepthLook.spin;
    return 360 * ease(clamp((now - this.spinT0 - order * S.stagger) / S.duration));
  }

  spinning(now) {
    return this.spinT0 != null && now - this.spinT0 < DepthLook.spin.duration + DepthLook.spin.stagger * ((this.glyphs?.length || 0) + 4);
  }

  // ---------------------------------------------------------------- per frame

  // x: the row's offset (pt, + = right), v: its velocity (pt/s), pull: how far the finger has
  // pulled it since it touched (pt, 0 once let go). Returns true while anything moves.
  update(now, x, v, pull = 0) {
    if (!this.active) return false;
    this.samples.push({ t: now, v, x });
    while (this.samples.length > 2 && this.samples[0].t < now - 0.6) this.samples.shift();
    const D = DepthLook;
    const dir = x < -0.5 ? -1 : x > 0.5 ? 1 : Math.sign(v) || -1;   // the side the row moves toward
    const tension = Math.abs(Math.tanh(pull / D.holdDistance));
    const motion = (t) => Math.tanh(Math.abs(this.sample(t).v) / D.v0);
    let moving = false;
    // Advance to now, then retarget (velocity carried over); a target that stays put lets the
    // spring come to rest.
    const step = (sv, target) => {
      sv.update(now);
      if (Math.abs(target - sv.target) > 0.01) sv.animate(target, now);
      if (!sv.settled) moving = true;
      return sv.value;
    };

    // The rim (left swipes): how far round it a piece whose flat centre is at X (screen pt) is,
    // where it shows, how lit it is and how much of it is left.
    const E = D.edge;
    let rolled = false;
    const rim = (X) => {
      const th = Math.max(0, (E.hinge - X) / E.radius);
      if (th <= 0) return null;
      rolled = true;
      const c = Math.min(th, HALF);
      const deg = th / DEG;
      return {
        th, deg,
        r: Math.min(1, th / HALF),                  // 0 flat … 1 edge-on
        dx: E.hinge - E.radius * Math.sin(c) - X,   // from its flat place to the rim
        dz: -E.radius * (1 - Math.cos(c)),
        lit: 1 - Math.cos(c),                       // the light leaving its face
        fade: 1 - smooth(E.fade[0], E.fade[1], deg),
      };
    };

    // The name: letters roll back (top away, into the surface), the wave from the leading side;
    // at the rim each one turns round it.
    if (this.glyphs) {
      const T = D.title;
      const n = this.glyphs.length;
      const P = D.perspective;
      const O = this.titleOrigin;
      this.glyphs.forEach((g, i) => {
        const order = dir < 0 ? i : n - 1 - i;
        const t0 = now - order * T.stagger;
        const roll = step(g.roll, T.roll * motion(t0) + T.hold * tension);
        const R = rim(this.titleX + g.cx + x);
        const k = R ? 1 - R.r : 1;
        // Rolling over the rim each letter flips over once, like a reel rolling off the edge — done by
        // ~60° round, before it fades, and back the other way as it comes out (left swipes always show it).
        const flip = R ? 360 * ease(clamp(R.r / DepthLook.edge.flipBy)) : 0;
        const a = (roll + this.spinAngle(now, order)) * k + flip;
        const lift = T.lift * Math.min(1, Math.abs(Math.sin(a * DEG)) * 1.4) * k;
        let t;
        if (R) {
          // Placed so that, seen through the name's perspective, it lands on the rim.
          // Its depth flattens as it turns, so the side never outgrows the letter.
          const tx = O + (g.cx + R.dx - O) * (P - R.dz) / P - g.cx;
          const kz = 1 - 0.85 * R.r;
          t = `translate3d(${tx.toFixed(2)}px,0,${R.dz.toFixed(2)}px) rotateY(${(-R.deg).toFixed(2)}deg) scale3d(1,1,${kz.toFixed(3)}) translateZ(${lift.toFixed(2)}px) rotateX(${a.toFixed(2)}deg)`;
        } else {
          t = `translateZ(${lift.toFixed(2)}px) rotateX(${a.toFixed(2)}deg)`;
        }
        if (t !== g.last) { g.last = t; g.el.style.transform = t; }
        const shade = Math.max(T.shade * (1 - Math.abs(Math.cos(a * DEG))), R ? E.shade * R.lit : 0);
        const fade = R ? R.fade : 1;
        const sh = (shade * fade).toFixed(3);
        if (sh !== g.lastShade) { g.lastShade = sh; g.shade.style.opacity = sh; }
        // Near edge-on it fades (layer by layer, so the letter keeps its depth) and then it's
        // behind; its sides fade a little as it turns, so the face stays the letter.
        const fo = fade >= 0.999 ? '' : fade.toFixed(3);
        const lo = R ? (fade * (1 - 0.6 * R.r)).toFixed(3) : '';
        const op = `${fo}|${lo}`;
        if (op !== g.op) {
          g.op = op;
          g.face.style.opacity = fo;
          for (const l of g.layers) l.style.opacity = lo === '1.000' ? '' : lo;
        }
        const hide = fade <= 0.001;
        if (hide !== g.hidden) { g.hidden = hide; g.el.style.visibility = hide ? 'hidden' : ''; }
      });
    }

    // The badges after the name (verified, muted): flat pieces on the same rim.
    if (this.icons) {
      const P = D.perspective;
      for (const ic of this.icons) {
        const R = rim(ic.cx + x);
        let t = '';
        let o = '';
        if (R) {
          const tx = R.dx * (P - R.dz) / P;
          t = `perspective(${P}px) translate3d(${tx.toFixed(2)}px,0,${R.dz.toFixed(2)}px) rotateY(${(-R.deg).toFixed(2)}deg)`;
          o = R.fade >= 0.999 ? '' : R.fade.toFixed(3);
        }
        const key = `${t}|${o}`;
        if (key !== ic.last) { ic.last = key; ic.el.style.transform = t; ic.el.style.opacity = o; }
      }
    }

    // The message: its text fades into the rim (a mask over the box, in its own coordinates).
    const box = this.parts.lines?.[0]?.parentElement;
    if (box) {
      const left = box.offsetLeft + x;
      const m = left < E.hinge
        ? `linear-gradient(90deg, transparent ${(E.hinge - E.radius * 0.92 - left).toFixed(1)}px, #000 ${(E.hinge - left).toFixed(1)}px)`
        : '';
      if (m !== this.textMask) {
        this.textMask = m;
        box.style.webkitMaskImage = m;
        box.style.maskImage = m;
      }
      if (m) rolled = true;
    }

    // The message lines: rigid plates, the leading end lifting, line 2 after line 1. Seen from
    // their left end on a left swipe (they lift there without spreading over the photo).
    if (this.lines) {
      const P = D.lines;
      const box = this.parts.lines[0]?.parentElement;
      const po = dir < 0 ? '0% 50%' : '';
      if (box && po !== this.linesOrigin) { this.linesOrigin = po; box.style.perspectiveOrigin = po; }
      this.lines.forEach((l, i) => {
        const lean = step(l.lean, (P.lean * motion(now - P.delay - i * P.stagger) + P.hold * tension) * -dir);
        const origin = dir < 0 ? '100% 50%' : '0% 50%';
        const t = Math.abs(lean) < 0.05 ? '' : `rotateY(${lean.toFixed(2)}deg)`;
        if (t !== l.last) {
          l.last = t;
          l.el.style.transformOrigin = origin;
          l.el.style.transform = t;
        }
      });
    }

    // The disc: heavier (lags a little more). On a left swipe it rolls over the rim: its lean
    // hands over to the turn round the rim, following the position directly.
    if (this.avatar) {
      const A = D.avatar;
      const av = this.avatar;
      const lean = step(av.lean, (A.lean * motion(now - A.delay) + A.hold * tension) * dir);
      const R = rim(av.cx + x);
      const k = R ? 1 - R.r : 1;
      const a = lean * k - (R ? R.deg : 0) + this.spinAngle(now, -3) * -dir;
      const s = Math.sin(a * DEG);
      const lift = A.lift * Math.min(1, Math.abs(s) * 1.3) * k;
      const dx = R ? R.dx : 0;
      const t = `translate3d(${dx.toFixed(2)}px,0,${((R ? R.dz : 0) + lift).toFixed(2)}px) rotateY(${a.toFixed(2)}deg)`;
      if (t !== av.last) {
        av.last = t;
        av.disc.style.transform = t;
        // Seen from straight in front of where it is (on the rim too).
        const origin = R ? `${(av.half + dx).toFixed(2)}px 50%` : '';
        if (origin !== av.origin) { av.origin = origin; av.el.style.perspectiveOrigin = origin; }
        // The picture sits deeper than the rim: it slides against the tilt.
        av.inner.style.transform = `translateX(${(-A.parallax * s).toFixed(2)}px) scale(1.14)`;
        av.glint.style.transform = `translateX(${(s * 34).toFixed(2)}%)`;
        av.glint.style.opacity = (Math.min(1, Math.abs(s) * 1.6) * (R ? R.fade : 1)).toFixed(3);
        av.dim.style.opacity = (R ? E.shade * R.lit : 0).toFixed(3);
        // (Faded on the photo's box, not on the disc: opacity there would flatten its rim.)
        av.el.style.opacity = R && R.fade < 0.999 ? R.fade.toFixed(3) : '';
        av.el.style.visibility = R && R.fade <= 0.001 ? 'hidden' : '';
      }
    }
    // While anything is round the rim the rig stays (the row may rest open like that).
    this.rolled = rolled;
    const S = this.stats;
    if (S) {
      S.frames++;
      S.minX = Math.min(S.minX, Math.round(x));
      S.maxX = Math.max(S.maxX, Math.round(x));
      for (const g of this.glyphs || []) {
        const m = /rotateY\((-?[0-9.]+)deg\).*rotateX\((-?[0-9.]+)deg/.exec(g.last) || /rotateX\((-?[0-9.]+)deg/.exec(g.last);
        if (!m) continue;
        if (m.length > 2) { S.maxRim = Math.max(S.maxRim, Math.round(Math.abs(+m[1]))); S.maxRoll = Math.max(S.maxRoll, Math.round(Math.abs(+m[2]) % 360)); } else S.maxRoll = Math.max(S.maxRoll, Math.round(Math.abs(+m[1]) % 360));
      }
      // What the browser made of it, at the farthest point of the move.
      if (Math.abs(x) > Math.abs(S.peakX) + 24 && this.glyphs?.[0]) {
        S.peakX = x;
        const g = this.glyphs[Math.min(2, this.glyphs.length - 1)].el;
        const cs = getComputedStyle(g);
        const r = g.getBoundingClientRect();
        S.peak = { x: Math.round(x), tf: cs.transform.slice(0, 48), vis: cs.visibility, w: +r.width.toFixed(1), h: +r.height.toFixed(1), layer: !!this.titleLayer?.isConnected, host: getComputedStyle(this.parts.title).color };
      }
    }
    return moving || this.spinning(now);
  }

  // Back to flat DOM (call once update() has settled).
  end() {
    if (!this.active) return;
    if (this.stats) diag('depth', this.stats);
    this.stats = null;
    this.active = false;
    this.rolled = false;
    if (this.titleLayer) {
      this.titleLayer.remove();
      this.parts.title.style.color = this.titleColor;
      this.titleLayer = null;
      this.glyphs = null;
    }
    if (this.icons) {
      for (const ic of this.icons) { ic.el.style.transform = ''; ic.el.style.opacity = ''; }
      this.icons = null;
    }
    const box = this.parts.lines?.[0]?.parentElement;
    if (box && this.textMask) {
      box.style.webkitMaskImage = '';
      box.style.maskImage = '';
    }
    this.textMask = '';
    if (this.lines) {
      for (const l of this.lines) {
        l.el.style.transform = '';
        l.el.style.willChange = '';
      }
      const box = this.parts.lines[0]?.parentElement;
      if (box) box.style.perspectiveOrigin = '';
      this.linesOrigin = '';
      this.lines = null;
    }
    if (this.avatar) {
      this.avatar.disc.remove();
      this.avatar.el.style.perspectiveOrigin = '';
      this.avatar.el.style.zIndex = '';
      this.avatar.el.style.opacity = '';
      this.avatar.el.style.visibility = '';
      if (this.avatar.pic) this.avatar.pic.style.visibility = '';
      this.avatar = null;
    }
  }
}
