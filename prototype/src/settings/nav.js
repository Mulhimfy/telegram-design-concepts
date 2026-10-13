// Navigation for the prototype's pushed pages (a Settings row's page, a profile), as Telegram iOS 26
// does it (research/telegram-ios/settings-icons-and-gifts.md §A5, NavigationTransitionCoordinator):
//   · push / back-button pop: 0.5 s on the iOS 26 spring (m 1, k 555.027, c 47.118, critically
//     damped: x(t) = 1 − (1 + 23.559 t)·e^(−23.559 t));
//   · the page under it (the whole tab-bar screen, as in Telegram) drifts left by 0.3 W and dims to
//     15 % black; the moving page has the screen's corner radius (41.5 on an iPhone 11) and a soft
//     shadow that shows through its corners;
//   · swipe back from anywhere on the page, horizontally: p = dx / W; it completes past 20 % or
//     above 1000 pt/s (in clamp((1 − p)·W / v, 0.05, 0.2) s, ease-in-out) or snaps back in 0.1 s.

import { Haptics } from '../core/haptics.js';

export const NavLook = { duration: 0.5, parallax: 0.3, dim: 0.15, dimUnder: 62 };

// iOS 26 `.spring` at 0.5 s.
export function navCurve(t) {
  if (t >= NavLook.duration) return 1;
  const s = Math.max(0, t) * 23.559;
  return 1 - (1 + s) * Math.exp(-s);
}
const easeInOut = (u) => (u < 0.5 ? 2 * u * u : 1 - Math.pow(-2 * u + 2, 2) / 2);

function el(tag, cls, style, parent, html) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (style) e.style.cssText = style;
  if (html !== undefined) e.innerHTML = html;
  if (parent) parent.appendChild(e);
  return e;
}

// NavigationBarImpl's back arrow: a 2 pt chevron (24.6, 14) → (17, 22) → (24.6, 30) in 44 × 44.
export const chevronLeft = '<svg viewBox="0 0 44 44" width="44" height="44"><path d="M24.6 14 17 22l7.6 8" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';

export class NavStack {
  // screen: the device screen; root: the tab-bar screen under everything pushed.
  constructor({ screen, root, device, clock }) {
    this.screen = screen;
    this.root = root;
    this.device = device;
    this.clock = clock;
    this.W = device.width;
    this.corner = device.corner || 41.5;
    this.stack = [];
    this.anim = null;           // { kind, t0, from, to, duration, curve, swipe }
    this.progress = 0;          // 0: root showing, 1: top page fully in
    this.dim = el('div', 'nav-dim', `left:0;top:0;width:${this.W}px;height:${device.height}px;opacity:0;display:none`, screen);
    this.shadow = el('div', 'nav-shadow', `left:0;top:0;width:16px;height:${device.height}px;opacity:0;display:none`, screen);
    this.touch = null;
  }

  get top() { return this.stack[this.stack.length - 1] || null; }
  get busy() { return !!this.anim || !!this.touch; }

  // page: { el (built, not yet attached), onShown?, onReturning?, onPopped?, down/move/up/update? }
  push(page, now) {
    if (this.anim || this.top) return;
    page.el.classList.add('nav-page');
    this.screen.appendChild(page.el);
    this.dim.style.display = '';
    this.shadow.style.display = '';
    this.stack.push(page);
    this.anim = { kind: 'push', t0: now, from: 0, to: 1, duration: NavLook.duration, curve: navCurve };
    this.layout(0);
    this.onChange?.(page);
  }

  // A back-button pop (the push in reverse), or the end of a swipe (its own duration and curve).
  pop(now, { from = this.progress, duration = NavLook.duration, curve = navCurve, swipe = false } = {}) {
    if (!this.top || (this.anim && this.anim.kind === 'pop')) return;
    this.anim = { kind: 'pop', t0: now, from, to: 0, duration, curve, swipe };
  }

  layout(p) {
    this.progress = p;
    const top = this.top;
    const x = Math.floor((1 - p) * this.W);
    const moving = p > 0 && p < 1;
    if (top) {
      top.el.style.transform = p >= 1 ? '' : `translate3d(${x}px,0,0)`;
      const r = moving ? `${this.corner}px` : '0px';
      if (top.el.style.borderRadius !== r) top.el.style.borderRadius = r;
    }
    this.root.style.transform = p <= 0 ? '' : `translate3d(${(-NavLook.parallax * this.W * p).toFixed(2)}px,0,0)`;
    // The dim runs 62 pt under the moving page, so its rounded corners show dimmed content.
    this.dim.style.width = `${Math.min(this.W, x + NavLook.dimUnder)}px`;
    this.dim.style.opacity = (NavLook.dim * p).toFixed(3);
    this.shadow.style.transform = `translate3d(${x + 46}px,0,0)`;
    this.shadow.style.opacity = moving ? (0.9 * p).toFixed(3) : '0';
  }

  update(now) {
    const pageBusy = this.top?.update ? this.top.update(now) : false;
    return this.step(now) || pageBusy;
  }

  step(now) {
    const a = this.anim;
    if (!a) return !!this.touch;
    const t = now - a.t0;
    const u = a.curve === navCurve ? navCurve(t) : a.curve(Math.min(1, t / a.duration));
    this.layout(a.from + (a.to - a.from) * u);
    if (a.kind === 'pop' && !a.announced && !a.swipe && t >= 0.2) {
      // A button pop: ~0.2 s in, the page has nearly landed (the spring is at 95 %).
      a.announced = true;
      this.top?.onReturning?.(now);
    }
    if (t >= a.duration) {
      this.anim = null;
      if (a.kind === 'pop') {
        const page = this.stack.pop();
        page.el.remove();
        this.dim.style.display = 'none';
        this.shadow.style.display = 'none';
        this.root.style.transform = '';
        if (a.swipe) page.onReturning?.(now);   // a swipe back: when its completion ends
        page.onPopped?.(now);
        this.onChange?.(this.top);
      } else {
        this.layout(a.to);
        if (a.to >= 1) this.top?.onShown?.(now);
      }
    }
    return true;
  }

  // ---------------------------------------------------------------- input (screen pt)

  down(p, now) {
    const top = this.top;
    if (!top || this.anim) return false;
    const back = top.backButton?.getBoundingClientRect();
    const sr = this.screen.getBoundingClientRect();
    const k = this.W / sr.width;
    if (back) {
      const x = (back.left - sr.left) * k;
      const y = (back.top - sr.top) * k;
      if (p[0] >= x - 4 && p[0] <= x + back.width * k + 4 && p[1] >= y - 4 && p[1] <= y + back.height * k + 4) {
        this.touch = { kind: 'back', start: p, last: p };
        top.backButton.classList.add('pressed');
        return true;
      }
    }
    // The page gets the touch; a horizontal drag to the right takes it over as a swipe back.
    this.touch = { kind: 'page', start: p, last: p, samples: [[now, p[0]]] };
    top.down?.(p, now);
    return true;
  }

  move(p, now) {
    const t = this.touch;
    if (!t) return;
    t.last = p;
    if (t.samples) {
      t.samples.push([now, p[0]]);
      while (t.samples.length > 2 && t.samples[0][0] < now - 0.08) t.samples.shift();
    }
    const dx = p[0] - t.start[0];
    const dy = p[1] - t.start[1];
    if (t.kind === 'page') {
      const claimed = this.top?.claimsHorizontal?.() || false;
      if (!claimed && !t.decided) {
        if (Math.abs(dy) > 4 && Math.abs(dy) > 2.5 * Math.abs(dx)) t.decided = 'page';
        else if (dx > 4 && Math.abs(dy) * 2.5 < dx) {
          t.decided = 'swipe';
          t.kind = 'swipe';
          t.x0 = p[0];
          this.top?.up?.(p, now, true);     // the page's own touch is cancelled
          this.dim.style.display = '';
          this.shadow.style.display = '';
        }
      }
      if (t.kind === 'page') this.top?.move?.(p, now);
    }
    if (t.kind === 'swipe') this.layout(1 - Math.max(0, Math.min(1, (p[0] - t.x0) / this.W)));
  }

  up(p, now, cancelled) {
    const t = this.touch;
    if (!t) return;
    this.touch = null;
    if (t.kind === 'back') {
      this.top?.backButton?.classList.remove('pressed');
      if (!cancelled) {
        Haptics.tap();
        this.pop(now);
      }
      return;
    }
    if (t.kind === 'swipe') {
      const s = t.samples;
      const v = s.length > 1 ? (s[s.length - 1][1] - s[0][1]) / Math.max(1e-3, s[s.length - 1][0] - s[0][0]) : 0;
      const p0 = 1 - this.progress;     // how far it has been dragged
      if (!cancelled && (v > 1000 || p0 > 0.2)) {
        const d = Math.max(0.05, Math.min(0.2, Math.abs(((1 - p0) * this.W) / Math.max(1, v))));
        this.pop(now, { from: this.progress, duration: d, curve: easeInOut, swipe: true });
      } else {
        this.anim = { kind: 'push', t0: now, from: this.progress, to: 1, duration: 0.1, curve: easeInOut };
      }
      return;
    }
    this.top?.up?.(p, now, cancelled);
  }
}
