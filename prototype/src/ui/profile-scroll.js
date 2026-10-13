// The own-profile header under scrolling, as Telegram does it (PeerInfoHeaderNode /
// PeerInfoScreen; spec with line references in research/telegram-ios/header-scroll.md):
//   · scrolling up collapses the header: f = clamp(offset / T), T ≈ 123.5; the avatar
//     scales 1 → 0.55 and scrolls away, the title shrinks to 0.6 and locks in the
//     navigation bar at S + 31, the subtitle fades, the emoji pattern slides into the
//     avatar; past S + 70 the banner fades out (0.2 s) over the navigation background;
//   · pulling down past 32 pt while dragging expands the photo to the full width
//     (W × (W + 60), 0.35 s cubic-bezier(0.38, 0.7, 0.125, 1)); scrolling up collapses it;
//   · the list scrolls with UIScrollView physics: rubber band, deceleration 0.998, bounce,
//     and releases between 0 and 140 snap to 0 or 140.

import { SpringParams, SpringValue, rubberBand } from '../core/spring.js';
import { Haptics } from '../core/haptics.js';
import { Color } from '../core/color.js';

const DECELERATION = 0.998;                          // UIScrollView .normal (per ms)
const PROJECTION = -1 / (1000 * Math.log(DECELERATION));
const EXPAND_TRIGGER = -32;
const clamp = (x, a = 0, b = 1) => Math.max(a, Math.min(b, x));
const lerp = (a, b, t) => a + (b - a) * t;

function cubicBezier(x1, y1, x2, y2) {
  const cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx;
  const cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by;
  return (x) => {
    let t = x;
    for (let i = 0; i < 8; i++) {
      const err = ((ax * t + bx) * t + cx) * t - x;
      const d = (3 * ax * t + 2 * bx) * t + cx;
      if (Math.abs(err) < 1e-6 || Math.abs(d) < 1e-6) break;
      t -= err / d;
    }
    t = clamp(t);
    return ((ay * t + by) * t + cy) * t;
  };
}
const expandCurve = cubicBezier(0.38, 0.7, 0.125, 1.0);   // ContainedViewLayoutTransition .spring, 0.35 s
const easeInOut = (u) => (u < 0.5 ? 2 * u * u : 1 - Math.pow(-2 * u + 2, 2) / 2);

function el(tag, cls, style, parent, html) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (style) e.style.cssText = style;
  if (html !== undefined) e.innerHTML = html;
  if (parent) parent.appendChild(e);
  return e;
}

function parseRgba(css) {
  const m = css.match(/rgba?\(([^)]+)\)/);
  if (!m) return [0, 0, 0, 0];
  const p = m[1].split(',').map((x) => parseFloat(x));
  return [p[0], p[1], p[2], p[3] ?? 1];
}
const mixRgba = (a, b, t) => `rgba(${a.map((v, i) => (i < 3 ? Math.round(lerp(v, b[i], t)) : lerp(v, b[i], t).toFixed(3))).join(',')})`;

export class ProfileScroll {
  constructor({ screen, ui, device, dark, avatarImage, light, cover, coverParams, onRest, onTopChange }) {
    const G = ui.geometry;
    this.ui = ui;
    this.device = device;
    this.dark = dark;
    this.light = light;
    this.cover = cover;
    this.coverParams = coverParams;
    this.onRest = onRest;
    this.onTopChange = onTopChange;   // the colour at the very top changes (banner ↔ bar / photo)
    this.topState = 'banner';
    this.W = G.W;
    this.H = device.height;
    this.S = G.S;
    this.N = G.navigationHeight;
    this.avatarY0 = G.avatarCenter.y;                   // S + 72
    this.titleC0 = G.titleY + G.titleH / 2;
    this.subtitleC0 = G.subtitleY + 21 / 2;
    this.T = this.titleC0 - this.S - 24;               // titleCollapseFraction distance
    this.He = Math.min(this.W, this.H - 61) + 60;      // expanded header height
    this.listShift = this.He + 15 - (this.N + 171);
    this.contentEnd = ui.listBottom + 24 + 62 + 20 + (device.bottomInset || 0);

    this.offset = 0;
    this.mode = 'idle';                                // idle | drag | decel | spring
    this.tracking = false;
    this.spring = new SpringValue(0, SpringParams.fromResponse(0.45, 1.0));
    this.spring.epsilon = 0.05;
    this.expanded = false;
    this.e = 0;
    this.expandAnim = null;
    this.banner = { value: 1, target: 1, anim: null };
    this.step = { value: 0, target: 0, anim: null };
    this.restTint = ui.qr.style.getPropertyValue('--glass-tint') || 'rgba(255,255,255,0.1)';
    this.tints = {
      rest: parseRgba(this.restTint),
      panel: dark ? [44, 44, 46, 0.72] : [255, 255, 255, 0.72],
      expanded: [0, 0, 0, 0.5],
    };
    this.titleGroupWidth = ui.titleText.offsetWidth + 30;
    this.buildExpanded(screen, avatarImage);
    this.last = {};
    this.layout(true);
  }

  // ---------------------------------------------------------------- expanded photo

  buildExpanded(screen, image) {
    const W = this.W;
    const He = this.He;
    this.exp = el('div', 'abs', 'left:0;top:0;overflow:hidden;z-index:2;display:none;pointer-events:none;will-change:transform', screen);
    this.expContent = el('div', 'abs', `left:0;top:0;width:${W}px;height:${He}px;transform-origin:0 0`, this.exp);
    const img = el('img', 'abs', `left:0;top:0;width:${W}px;height:${W}px;object-fit:cover`, this.expContent);
    img.src = image.src;
    // The 60 pt under the square: the photo's bottom ~20 pt, mirrored and stretched ×3
    // (CAReplicatorLayer in PeerInfoAvatarListNode).
    const band = el('canvas', 'abs', `left:0;top:${W - 0.5}px;width:${W}px;height:60.5px`, this.expContent);
    const s = 2;
    band.width = W * s;
    band.height = 61 * s;
    const bc = band.getContext('2d');
    const ih = image.naturalHeight || image.height;
    const iw = image.naturalWidth || image.width;
    const srcH = (20 / W) * ih;
    bc.setTransform(1, 0, 0, -1, 0, band.height);
    bc.drawImage(image, 0, ih - srcH, iw, srcH, 0, 0, band.width, band.height);
    // Bottom shadow: progressive blur + black 0 → 0.4 (×0.8) over the last 88 pt.
    const shade = 'linear-gradient(180deg, rgba(0,0,0,0) 0%, rgba(0,0,0,0.32) 100%)';
    const blurMask = 'linear-gradient(180deg, rgba(0,0,0,0) 0%, #000 55%)';
    el('div', 'abs', `left:0;top:${He - 88}px;width:${W}px;height:88px;background:${shade};`
      + `-webkit-backdrop-filter:blur(15px);backdrop-filter:blur(15px);-webkit-mask-image:${blurMask};mask-image:${blurMask}`, this.expContent);
    el('div', 'abs', `left:0;top:${He - 88}px;width:${W}px;height:88px;background:${shade}`, this.expContent);
    // Top shadow under the navigation buttons (black 0.4 → 0 over N + 20).
    this.expTop = el('div', 'abs', `left:0;top:0;width:${W}px;height:${this.N + 20}px;z-index:3;pointer-events:none;opacity:0;`
      + 'background:linear-gradient(180deg, rgba(0,0,0,0.4), rgba(0,0,0,0))', screen);
    // Expanded subtitle (16 pt regular, white, left 16).
    this.expSub = el('div', 'abs', 'left:16px;height:20px;z-index:3;pointer-events:none;opacity:0;color:#fff;white-space:nowrap;'
      + 'font-family:var(--font-text);font-size:16px;line-height:20px;letter-spacing:-0.3px', screen, this.ui.subtitle.textContent);
  }

  // ---------------------------------------------------------------- scrolling

  get maxOffset() {
    return Math.max(140, this.contentEnd + this.listShift * this.e - this.H);
  }

  get avatarInteractive() {
    return !this.expanded && this.e === 0 && Math.abs(this.offset) < 0.5 && this.mode === 'idle';
  }

  // Rubber-banded offset ↔ the finger's raw offset.
  fromRaw(raw) {
    const max = this.maxOffset;
    if (raw < 0) return -rubberBand(-raw, this.H);
    if (raw > max) return max + rubberBand(raw - max, this.H);
    return raw;
  }

  toRaw(o) {
    const max = this.maxOffset;
    const inv = (y) => (this.H / 0.55) * (1 / (1 - Math.min(0.999, y / this.H)) - 1);
    if (o < 0) return -inv(-o);
    if (o > max) return max + inv(o - max);
    return o;
  }

  begin(y, now) {
    this.tracking = true;
    this.mode = 'drag';
    this.dragY = y;
    this.dragRaw = this.toRaw(this.offset);
  }

  drag(y, now) {
    if (!this.tracking) return;
    this.offset = this.fromRaw(this.dragRaw + (this.dragY - y));
    this.checkExpansion(now);
  }

  end(vy, now) {
    if (!this.tracking) return;
    this.tracking = false;
    const v = -vy;
    const max = this.maxOffset;
    if (this.offset < 0 || this.offset > max) {
      this.springTo(clamp(this.offset, 0, max), v, now);
      return;
    }
    // scrollViewWillEndDragging: a target between 0 and 140 snaps to 0 or 140.
    const target = this.offset + v * PROJECTION;
    if (target > 0 && target < 140) {
      this.springTo(target < 70 ? 0 : 140, v, now, 0.5);
      return;
    }
    if (Math.abs(v) < 20) {
      this.mode = 'idle';
      return;
    }
    this.mode = 'decel';
    this.decel = { t0: now, o0: this.offset, v0: v };
  }

  springTo(target, velocity, now, response = 0.45) {
    this.mode = 'spring';
    this.spring.set(this.offset, now);
    this.spring.animate(target, now, { params: SpringParams.fromResponse(response, 1.0), velocity });
  }

  checkExpansion(now) {
    if (!this.expanded && this.tracking && this.offset <= EXPAND_TRIGGER) {
      this.setExpanded(true, now);
      Haptics.impact('medium');
    } else if (this.expanded && this.offset >= 1) {
      this.setExpanded(false, now);
      Haptics.tap();
    }
  }

  // Tap on the avatar: the same animation, no haptic, no scroll change.
  expand(now) {
    if (this.avatarInteractive) this.setExpanded(true, now);
  }

  setExpanded(on, now) {
    if (this.expanded === on) return;
    this.expanded = on;
    this.expandAnim = { t0: now, from: this.e, to: on ? 1 : 0 };
  }

  tween(state, target, now) {
    if (state.target === target) return;
    state.target = target;
    state.anim = { t0: now, from: state.value };
  }

  stepTween(state, now, duration = 0.2) {
    if (!state.anim) return false;
    const u = clamp((now - state.anim.t0) / duration);
    state.value = lerp(state.anim.from, state.target, easeInOut(u));
    if (u >= 1) state.anim = null;
    return true;
  }

  update(now) {
    if (this.mode === 'decel') {
      const d = this.decel;
      const k = Math.pow(DECELERATION, 1000 * (now - d.t0));
      const o = d.o0 + d.v0 * (k - 1) / (1000 * Math.log(DECELERATION));
      const v = d.v0 * k;
      const max = this.maxOffset;
      if (o < 0 || o > max) {
        // Hit an edge: bounce on a spring with the incoming velocity.
        this.offset = clamp(o, 0, max);
        this.springTo(this.offset, v, now);
      } else {
        this.offset = o;
        if (Math.abs(v) < 8) this.mode = 'idle';
      }
    } else if (this.mode === 'spring') {
      this.offset = this.spring.update(now);
      if (this.spring.settled) this.mode = 'idle';
    }
    this.checkExpansion(now);

    let animating = this.mode === 'decel' || this.mode === 'spring';
    if (this.expandAnim) {
      const u = clamp((now - this.expandAnim.t0) / 0.35);
      this.e = lerp(this.expandAnim.from, this.expandAnim.to, expandCurve(u));
      if (u >= 1) {
        this.e = this.expandAnim.to;
        this.expandAnim = null;
      }
      animating = true;
    }
    // Past S + 70 the banner fades out and the colours step to the collapsed set.
    const collapsed = this.offset > this.S + 70 ? 1 : 0;
    this.tween(this.banner, 1 - collapsed, now);
    this.tween(this.step, collapsed, now);
    if (this.stepTween(this.banner, now)) animating = true;
    if (this.stepTween(this.step, now)) animating = true;

    const top = this.expanded ? 'photo' : collapsed ? 'bar' : 'banner';
    if (top !== this.topState) {
      this.topState = top;
      this.onTopChange?.(top);
    }
    // Compared with what was last laid out: a finger drag moves the offset between frames.
    const L = this.laid;
    const changed = !L || L.o !== this.offset || L.e !== this.e || L.b !== this.banner.value || L.s !== this.step.value;
    if (changed) this.layout();
    if (!animating && this.mode === 'idle' && !this.tracking && this.offset === 0 && changed) this.onRest?.();
    return animating || this.tracking;
  }

  // ---------------------------------------------------------------- layout

  layout(force = false) {
    const { W, S, N, T, He, ui } = this;
    const co = this.offset;
    this.laid = { o: co, e: this.e, b: this.banner.value, s: this.step.value };
    const f = clamp(co / T);
    const e = this.e;
    const pull = Math.max(0, -co);

    // Avatar (the glass canvas): scale 1 − 0.45 f, centre S + 72 − co + 17 f.
    const avatarK = 1 - 0.45 * f;
    const avatarDy = -co + 17 * f;
    let avatarAlpha = e > 0.001 ? 0 : 1;
    if (this.device.island && co > 0) avatarAlpha *= 1 - clamp((co / 120 - 0.35) / 0.65);
    ui.coin.style.transform = `translate3d(0,${avatarDy.toFixed(2)}px,0) scale(${avatarK.toFixed(4)})`;
    ui.coin.style.opacity = String(avatarAlpha);

    // Title: centre titleMidY − min(co, T) + 7 f, scale 1 − 0.4 f; expanded: 0.8 at the bottom left.
    const tcC = this.titleC0 - Math.min(co, T) + 7 * f;
    const tkC = 1 - 0.4 * f;
    const tcE = He - 59 + 34 * 0.8 / 2 + pull;
    const txE = 16 + 0.4 * this.titleGroupWidth - W / 2;
    const tc = lerp(tcC, tcE, e);
    const tk = lerp(tkC, 0.8, e);
    ui.title.style.transform = `translate3d(${(txE * e).toFixed(2)}px,${(tc - this.titleC0).toFixed(2)}px,0) scale(${tk.toFixed(4)})`;
    const titleColor = !this.dark && this.step.value > 0.5 && e < 0.5 ? '#000' : '#fff';
    if (ui.titleText.style.color !== titleColor) ui.titleText.style.color = titleColor;

    // Subtitle: centre − min(co, T) − 2 f, scale 1 − 0.2 f, alpha 1 − f; crossfades to the
    // expanded 16 pt line.
    const scC = this.subtitleC0 - Math.min(co, T) - 2 * f;
    ui.subtitle.style.transform = `translate3d(0,${(scC - this.subtitleC0).toFixed(2)}px,0) scale(${(1 - 0.2 * f).toFixed(4)})`;
    ui.subtitle.style.opacity = String(((1 - f) * (1 - e)).toFixed(3));
    this.expSub.style.top = `${(He - 59 + 34 * 0.8 + 2 + pull).toFixed(2)}px`;
    this.expSub.style.opacity = String(e.toFixed(3));
    this.expTop.style.opacity = String(e.toFixed(3));

    // Banner: from the top to N + max(0, 155 − co) (grows when pulled); the pattern follows
    // the avatar and slides into it; fades out past S + 70.
    const bannerH = co >= 0 ? N + Math.max(0, 155 - co) : N + 155 - co;
    const cp = this.coverParams;
    const avatarCy = this.avatarY0 - co + 17 * f;
    const key = `${bannerH.toFixed(2)}|${avatarCy.toFixed(2)}|${f.toFixed(4)}`;
    if (force || key !== this.last.cover) {
      this.last.cover = key;
      cp.height = Math.min(bannerH, cp.canvasHeight);
      cp.avatarCenter = { x: cp.avatarCenter.x, y: avatarCy };
      cp.avatarTransitionFraction = f;
      this.cover.draw(cp);
    }
    ui.cover.style.opacity = String(this.banner.value.toFixed(3));

    // List under the header.
    ui.list.style.transform = `translate3d(0,${(-co + this.listShift * e).toFixed(2)}px,0)`;

    // Navigation buttons: header colour → panel glass when collapsed → dark glass on the photo.
    let tint = mixRgba(this.tints.rest, this.tints.panel, this.step.value);
    if (e > 0) tint = mixRgba(parseRgba(tint), this.tints.expanded, e);
    ui.qr.style.setProperty('--glass-tint', tint);
    ui.cap.style.setProperty('--glass-tint', tint);
    if (!this.dark) {
      const glyph = this.step.value > 0.5 && e < 0.5 ? '#000' : '#fff';
      ui.statusBar?.setColor?.(glyph);
      for (const g of ui.qr.querySelectorAll('.mask-icon')) g.style.color = glyph;
      for (const g of ui.cap.querySelectorAll('.mask-icon, .abs')) g.style.color = glyph;
    }

    // Expanded photo: morphs from the avatar circle to W × He (bottom glued when pulled).
    if (e > 0.001) {
      this.exp.style.display = '';
      const s = 1 + pull / W;
      const topE = co < 0 ? He + pull - He * s : -co / 2;
      const a = { x: W / 2 - 50 * avatarK, y: avatarCy - 50 * avatarK, w: 100 * avatarK, h: 100 * avatarK };
      const b = { x: W / 2 - (W * s) / 2, y: topE, w: W * s, h: He * s };
      const x = lerp(a.x, b.x, e);
      const y = lerp(a.y, b.y, e);
      const w = lerp(a.w, b.w, e);
      const h = lerp(a.h, b.h, e);
      const side = lerp(a.w, W * s, e);
      Object.assign(this.exp.style, {
        left: `${x.toFixed(2)}px`, top: `${y.toFixed(2)}px`, width: `${w.toFixed(2)}px`, height: `${h.toFixed(2)}px`,
        borderRadius: `${(50 * avatarK * (1 - e)).toFixed(2)}px`,
      });
      this.expContent.style.transform = `scale(${(side / W).toFixed(5)})`;
    } else if (this.exp.style.display !== 'none') {
      this.exp.style.display = 'none';
    }

    // The light of the glass colour follows the avatar and leaves with it.
    this.light?.setOrigin(W / 2, avatarCy, this.banner.value * (1 - e) * (1 - f));
  }
}
