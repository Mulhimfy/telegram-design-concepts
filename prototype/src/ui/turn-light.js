// The light of the glass colour while the photo turns (only with a colour chosen; Clear glass
// stays plain). The glass face throws its colour as it tilts:
//   · the name and the line under it are swept by it: a band of the colour crosses the letters
//     in the direction the photo turns (turn it right and the light runs over the name from
//     left to right; turn it back and it runs back), once every quarter turn, so a spin sweeps
//     them again and again; the letters light up in the colour and glow around it;
//   · a sheen crosses the glass buttons and their rim facing the avatar lights up;
//   · a soft aura of the colour grows around the photo (and in the emoji pattern next to it).
// Nothing moves across the background itself; it all fades with the glass when the photo lands.
//
// Cost per frame while it moves: one header-sized canvas under the avatar (one gradient and a
// masked copy for the pattern), a gradient + a mask per text line and a transform + two
// opacities per button.

import { rgba, lighten } from './light.js';

const PI = Math.PI;
const clamp = (x, a = 0, b = 1) => Math.max(a, Math.min(b, x));
const smooth = (a, b, x) => {
  const t = clamp((x - a) / (b - a));
  return t * t * (3 - 2 * t);
};
const mix = (a, b, t) => a.map((v, i) => v + (b[i] - v) * t);

const REACH = 62 * PI / 180;  // tilt at which the light has left the header
const WIDTH = 46;              // pt, half-width of the light passing over the letters and buttons
const LENGTH = 260;            // pt, half-length (covers the header from the bar to the subtitle)
const SWEEP = 1.2;             // rad of tilt for the band to cross the letters (one quarter turn ≈ one sweep)
const GLOW_PAD = 44;           // pt around a text line for its glow


export class TurnLight {
  constructor(screen, { device, ui, light, cover, style, scale = 1 }) {
    const G = ui.geometry;
    this.W = device.width;
    this.H = G.backgroundHeight;    // the banner at rest: the light stays on the header
    this.ox = G.avatarCenter.x;
    this.oy = G.avatarCenter.y;
    this.screen = screen;
    this.light = light;             // its origin / visibility follow the header as it scrolls
    this.cover = cover;
    this.style = style;             // () => { color, tint }
    this.scale = scale;
    const c = document.createElement('canvas');
    c.className = 'abs';
    c.style.cssText = `left:0;top:0;width:${this.W}px;height:${this.H}px;z-index:2;pointer-events:none;mix-blend-mode:screen;display:none`;
    c.width = Math.round(this.W * scale);
    c.height = Math.round(this.H * scale);
    screen.insertBefore(c, ui.coin);   // under the avatar: the glass itself stays clear
    this.canvas = c;
    this.ctx = c.getContext('2d');
    this.temp = document.createElement('canvas');
    this.texts = [
      { el: ui.titleText, strength: 1, glow: 1 },
      { el: ui.subtitle, strength: 0.85, glow: 0.7 },
    ].map((t) => {
      const text = t.el.textContent;
      return { ...t, halo: makeGlow(t.el, text), shine: makeShine(t.el, text), bg: '', mask: '', op: '', key: '' };
    });
    this.buttons = [ui.qr, ui.cap].map((el) => makeButton(el));
    this.active = false;
    this.prev = null;
  }

  // Box of an element in screen pt at rest (measured once; the header doesn't move at rest).
  box(el) {
    const s = this.screen.getBoundingClientRect();
    const r = el.getBoundingClientRect();
    const k = this.W / s.width;
    const x = (r.left - s.left) * k;
    const y = (r.top - s.top) * k;
    const w = r.width * k;
    const h = r.height * k;
    return { x, y, w, h, cx: x + w / 2, cy: y + h / 2 };
  }

  // Box of the letters themselves (a line can be wider than its text).
  ink(el) {
    const node = [...el.childNodes].find((n) => n.nodeType === 3 && n.textContent.trim());
    if (!node) return this.box(el);
    const r = document.createRange();
    r.selectNodeContents(node);
    const s = this.screen.getBoundingClientRect();
    const q = r.getBoundingClientRect();
    const k = this.W / s.width;
    const x = (q.left - s.left) * k;
    const y = (q.top - s.top) * k;
    const w = q.width * k;
    const h = q.height * k;
    return { x, y, w, h, cx: x + w / 2, cy: y + h / 2 };
  }

  // st: the glass state (yaw, pitch, glass, yawVelocity). Returns true while it shows.
  update(st, now) {
    const { color, tint } = this.style();
    const o = this.light.origin;
    const resting = Math.abs(o.y - this.oy) < 0.5 && Math.abs(o.x - this.ox) < 0.5;
    const vis = resting ? this.light.visibility : 0;
    const glass = clamp(st.glass);
    // The face toward the viewer and where it looks (screen axes, y down).
    const th = st.yaw - PI * Math.round(st.yaw / PI);
    const ph = st.pitch || 0;
    const nx = Math.sin(th);
    const ny = Math.sin(ph) * Math.cos(th);
    const nl = Math.hypot(nx, ny);
    const psi = Math.acos(clamp(Math.cos(ph) * Math.cos(th), -1, 1));
    const spin = smooth(7, 20, Math.abs(st.yawVelocity || 0));
    const t = clamp(tint);
    // Clear glass has no colour to throw: nothing lights up.
    const strength = t < 0.02 ? 0 : (0.6 + 0.3 * t) * glass * vis * Math.min(1, t * 1.5);
    let I = strength * smooth(0.04, 0.22, psi) * (1 - 0.7 * spin);
    // The band over the letters: on as soon as the glass leaves flat, where the sweep has got to.
    const T = strength * smooth(0.025, 0.12, psi) * (1 - 0.7 * spin);
    const sweep = clamp(psi / SWEEP);
    const wash = strength * spin;
    const aura = strength * Math.max(0.6 * smooth(0.04, 0.35, psi), spin);
    if ((I < 0.004 && T < 0.004 && wash < 0.004 && aura < 0.004) || (nl < 1e-4 && wash < 0.004)) {
      this.rest();
      return false;
    }
    if (!this.active) this.wake();
    const dir = nl > 1e-4 ? [nx / nl, ny / nl] : [1, 0];
    const angle = Math.atan2(dir[1], dir[0]);

    // Where the light is: it leaves the avatar slowly, then runs out of the header
    // (offscreen by REACH, so the change of face at edge-on is never seen).
    const exitX = dir[0] > 1e-6 ? (this.W - this.ox) / dir[0] : dir[0] < -1e-6 ? -this.ox / dir[0] : Infinity;
    const exitY = dir[1] > 1e-6 ? (this.H - this.oy) / dir[1] : dir[1] < -1e-6 ? -this.oy / dir[1] : Infinity;
    const far = Math.min(exitX, exitY) + WIDTH * 1.6;
    const D = far * Math.pow(psi / REACH, 1.35);
    const bx = this.ox + dir[0] * D;
    const by = this.oy + dir[1] * D;
    // Fast enough to jump across in a frame: smear it (wider, dimmer) instead of strobing.
    let w = WIDTH;
    const face = Math.round(st.yaw / PI);
    if (this.prev && this.prev.face === face) {
      const jump = Math.hypot(bx - this.prev.x, by - this.prev.y);
      w = WIDTH + 0.5 * jump;
      I *= WIDTH / w;
    }
    this.prev = { x: bx, y: by, face };

    const hot = mix([1, 1, 1], lighten(color, 0.6), t);
    const body = mix([0.9, 0.95, 1], lighten(color, 0.22), t);
    const deep = mix([1, 1, 1], lighten(color, 0.08), t);
    const b = { x: bx, y: by, dir, angle, w, I, T, sweep, wash, aura, hot, body, deep, t };
    this.draw(b);
    this.shineTexts(b);
    this.lightButtons(b);
    return true;
  }

  wake() {
    this.active = true;
    this.canvas.style.display = '';
    for (const t of this.texts) {
      t.box ||= this.box(t.el);
      t.inkBox ||= this.ink(t.el);
    }
    for (const bt of this.buttons) {
      if (!bt.box) {
        bt.box = this.box(bt.el);
        const d = Math.hypot(this.ox - bt.box.cx, this.oy - bt.box.cy);
        bt.toAvatar = [(this.ox - bt.box.cx) / d, (this.oy - bt.box.cy) / d];
      }
    }
  }

  rest() {
    if (!this.active) return;
    this.active = false;
    this.prev = null;
    this.ctx.setTransform(1, 0, 0, 1, 0, 0);
    this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    this.canvas.style.display = 'none';
    for (const t of this.texts) {
      t.bg = 'none';
      t.shine.style.backgroundImage = 'none';
      t.op = '0';
      t.halo.style.opacity = '0';
    }
    for (const bt of this.buttons) {
      bt.clip.style.opacity = '0';
      bt.rim.style.opacity = '0';
    }
  }

  // The aura: a soft glow of the colour around the photo (it doesn't travel), stronger the
  // more the glass turns or spins.
  paint(ctx, b, k) {
    if (b.aura <= 0.004) return;
    const g = ctx.createRadialGradient(this.ox, this.oy, 44, this.ox, this.oy, 230);
    g.addColorStop(0, rgba(b.body, Math.min(1, 0.36 * b.aura * k)));
    g.addColorStop(0.45, rgba(b.body, Math.min(1, 0.14 * b.aura * k)));
    g.addColorStop(1, rgba(b.body, 0));
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, this.W, this.H);
  }

  draw(b) {
    const { ctx, scale } = this;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalCompositeOperation = 'source-over';
    ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    ctx.setTransform(scale, 0, 0, scale, 0, 0);
    this.paint(ctx, b, 1);

    // The emoji pattern glints where the light crosses it.
    const pr = this.cover?.patternRect;
    const mask = this.cover?.mask;
    if (!pr || !mask || !mask.width) return;
    const s = scale;
    const tmp = this.temp;
    const tw = Math.round(pr.w * s);
    const th = Math.round(pr.h * s);
    if (tmp.width !== tw || tmp.height !== th) { tmp.width = tw; tmp.height = th; }
    const tc = tmp.getContext('2d');
    tc.setTransform(1, 0, 0, 1, 0, 0);
    tc.globalCompositeOperation = 'source-over';
    tc.clearRect(0, 0, tw, th);
    tc.setTransform(s, 0, 0, s, -pr.x * s, -pr.y * s);
    this.paint(tc, { ...b, hot: lighten(b.hot, 0.4), body: lighten(b.body, 0.3) }, 2.6);
    tc.setTransform(1, 0, 0, 1, 0, 0);
    tc.globalCompositeOperation = 'destination-in';
    tc.drawImage(mask, 0, 0, tw, th);
    tc.globalCompositeOperation = 'source-over';
    ctx.drawImage(tmp, pr.x, pr.y, pr.w, pr.h);
  }

  // The letters are swept by the light: a band of the colour runs across them in the direction
  // the glass turns (a gradient clipped to the text), and they glow around it (the text's
  // shadow, masked to the band). A fast spin washes the whole line instead.
  shineTexts(b) {
    const A = Math.atan2(b.dir[0], -b.dir[1]);   // CSS gradient angle pointing along dir
    const deg = (A * 180 / PI).toFixed(1);
    const sA = Math.abs(Math.sin(A));
    const cA = Math.abs(Math.cos(A));
    for (const t of this.texts) {
      const bx = t.box;
      const ink = t.inkBox;
      // The band: its half-width, and where the sweep has taken it (from just before the first
      // letter to just past the last one, along the way the glass turns).
      const half = (ink.w * sA + ink.h * cA) / 2;
      const w = 16 + 0.42 * half;
      const c = (ink.cx - bx.cx) * b.dir[0] + (ink.cy - bx.cy) * b.dir[1] + (2 * b.sweep - 1) * (half + w);
      const a = clamp(b.T * t.strength * 1.25);
      const wa = clamp(b.wash * t.strength * 0.55);
      const L = bx.w * sA + bx.h * cA;
      const g = L / 2 + c;
      const layers = [];
      if (a > 0.01 && g + w > 0 && g - w < L) {
        const px = (k) => `${(g + k * w).toFixed(1)}px`;
        const stops = [
          `${rgba(b.body, 0)} ${px(-1)}`, `${rgba(b.body, 0.75 * a)} ${px(-0.5)}`, `${rgba(b.hot, a)} ${px(0)}`,
          `${rgba(b.body, 0.75 * a)} ${px(0.5)}`, `${rgba(b.body, 0)} ${px(1)}`,
        ];
        layers.push(`linear-gradient(${deg}deg, ${stops.join(', ')})`);
      }
      if (wa > 0.01) layers.push(`linear-gradient(${rgba(b.body, wa)}, ${rgba(b.body, wa)})`);
      const bg = layers.length ? layers.join(', ') : 'none';
      if (bg !== t.bg) {
        t.bg = bg;
        t.shine.style.backgroundImage = bg;
      }
      // The glow: the colour around the letters where the band is (all of them in a wash).
      const peak = Math.max(a, wa) * t.glow;
      const op = peak < 0.01 ? '0' : peak.toFixed(3);
      if (op !== t.op) {
        t.op = op;
        t.halo.style.opacity = op;
      }
      if (peak >= 0.01) {
        const key = b.body.map((v) => v.toFixed(2)).join();
        if (key !== t.key) {
          t.key = key;
          t.halo.style.textShadow = `0 0 4px ${rgba(b.hot, 0.9)}, 0 0 11px ${rgba(lighten(b.body, 0.1), 0.95)}, 0 0 24px ${rgba(b.body, 0.7)}, 0 0 42px ${rgba(b.body, 0.4)}`;
        }
        const P = GLOW_PAD;
        const L2 = (bx.w + 2 * P) * sA + (bx.h + 2 * P) * cA;
        const g2 = L2 / 2 + c;
        const floor = a > 0 ? clamp(wa / Math.max(a, wa)) : 1;
        const fl = floor.toFixed(3);
        const gw = w * 1.5;
        const mask = floor >= 0.999 ? 'none'
          : `linear-gradient(${deg}deg, rgba(0,0,0,${fl}) ${(g2 - gw).toFixed(1)}px, #000 ${g2.toFixed(1)}px, rgba(0,0,0,${fl}) ${(g2 + gw).toFixed(1)}px)`;
        if (mask !== t.mask) {
          t.mask = mask;
          t.halo.style.webkitMaskImage = mask;
          t.halo.style.maskImage = mask;
        }
      }
    }
  }

  // Glass buttons: a sheen crosses them with the light; the rim facing the avatar lights up.
  lightButtons(b) {
    const deg = (b.angle * 180 / PI).toFixed(1);
    const key = `${b.hot.map((v) => v.toFixed(2))}|${b.body.map((v) => v.toFixed(2))}`;
    for (const bt of this.buttons) {
      const bx = bt.box;
      const dist = (b.x - bx.cx) * b.dir[0] + (b.y - bx.cy) * b.dir[1];
      const along = Math.abs((b.x - bx.cx) * -b.dir[1] + (b.y - bx.cy) * b.dir[0]) / LENGTH;
      const lf = 1 - smooth(0.35, 1, along);
      if (bt.key !== key) {
        bt.key = key;
        bt.stripe.style.background = `linear-gradient(90deg, ${rgba(b.body, 0)} 0%, ${rgba(b.body, 0.32)} 28%, ${rgba(b.hot, 0.8)} 50%, ${rgba(b.body, 0.32)} 72%, ${rgba(b.body, 0)} 100%)`;
        const n = bt.toAvatar;
        bt.rim.style.boxShadow = `inset ${(-n[0] * 5).toFixed(2)}px ${(-n[1] * 5).toFixed(2)}px 11px -3px ${rgba(lighten(b.hot, 0.2), 1)}`;
      }
      const reach = b.w + Math.max(bx.w, bx.h) * 0.5;
      const sheen = clamp(b.I * lf * 1.2) * (Math.abs(dist) < reach + 20 ? 1 : 0);
      bt.stripe.style.transform = `translate(${(b.dir[0] * dist).toFixed(1)}px,${(b.dir[1] * dist).toFixed(1)}px) rotate(${deg}deg)`;
      const so = sheen < 0.01 ? '0' : sheen.toFixed(3);
      if (bt.clip.style.opacity !== so) bt.clip.style.opacity = so;
      const rim = clamp(b.I * lf * Math.exp(-Math.pow(dist / (b.w + 40), 2)) * 0.95 + b.wash * 0.6);
      const ro = rim < 0.01 ? '0' : rim.toFixed(3);
      if (bt.rim.style.opacity !== ro) bt.rim.style.opacity = ro;
    }
  }
}

// A copy of the line that only casts its glow (its letters are transparent), a little larger
// than the line so the glow isn't clipped by the mask.
function makeGlow(el, text) {
  if (getComputedStyle(el).position === 'static') el.style.position = 'relative';
  const s = document.createElement('span');
  s.className = 'turn-glow';
  s.style.cssText = `left:${-GLOW_PAD}px;top:${-GLOW_PAD}px;right:${-GLOW_PAD}px;bottom:${-GLOW_PAD}px;padding:${GLOW_PAD}px`;
  s.textContent = text;
  el.appendChild(s);
  return s;
}

function makeShine(el, text) {
  if (getComputedStyle(el).position === 'static') el.style.position = 'relative';
  const s = document.createElement('span');
  s.className = 'turn-shine';
  s.textContent = text;
  el.appendChild(s);
  return s;
}

function makeButton(el) {
  const w = el.offsetWidth;
  const h = el.offsetHeight;
  const layer = (css) => {
    const d = document.createElement('div');
    d.style.cssText = css;
    return d;
  };
  const rim = layer('position:absolute;inset:0;border-radius:inherit;pointer-events:none;opacity:0;will-change:opacity;z-index:3');
  const clip = layer('position:absolute;inset:0;border-radius:inherit;overflow:hidden;pointer-events:none;opacity:0;will-change:opacity;z-index:3');
  const SW = 34;
  const SL = Math.hypot(w, h) + 24;
  const stripe = layer(`position:absolute;left:${(w - SW) / 2}px;top:${(h - SL) / 2}px;width:${SW}px;height:${SL}px`);
  clip.appendChild(stripe);
  el.appendChild(rim);
  el.appendChild(clip);
  return { el, rim, clip, stripe, key: '' };
}
