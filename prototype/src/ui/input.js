// One input path for real touches and scripted demos (Demo injects the same events):
// the glass avatar, the list (scrolling, pull-to-expand, row taps) and sheets.
// Arbitration is Telegram's: the header sits above the list and a touch that starts on the
// avatar never reaches it (PeerInfoHeaderNode.hitTest), so a drag on the avatar is the
// avatar's in every direction (it lifts at once and tilts any way), while drags that start
// anywhere else scroll the list or pull the header down to expand the photo.

import { VelocityTracker } from '../core/velocity.js';

const SLOP = 10;         // pt (vertical) before a touch on the list or a sheet is a drag (UIKit's hysteresis)
const COIN_SLOP = 8;     // pt before a touch on the avatar turns it
const HIGHLIGHT_DELAY = 0.06;

export class InputRouter {
  constructor({ screen, device, clock, animator, coin, coinCenter, inertAvatar, scroll, rows, onRowTap, onAvatarTap, sheet, enabled }) {
    this.screen = screen;
    this.enabled = enabled || (() => true);   // the Settings tab is showing
    this.device = device;
    this.clock = clock;
    this.animator = animator;
    this.coin = coin;                 // CoinController
    this.coinCenter = coinCenter;     // () => {x, y} in screen pt, or null while the avatar can't be turned
    this.inertAvatar = inertAvatar;   // (p) => true where the photo takes the touch but does nothing with a drag (today)
    this.scroll = scroll;             // ScrollView (or null)
    this.rows = rows;                 // () => [{ id, x, y, w, h, highlight }] in list pt (screen pt at offset 0)
    this.onRowTap = onRowTap;
    this.onAvatarTap = onAvatarTap;
    this.sheet = sheet;               // () => the visible Sheet or null
    this.touch = null;
    this.tracker = new VelocityTracker(0.08);
  }

  attach() {
    const s = this.screen;
    const point = (e) => {
      const r = s.getBoundingClientRect();
      return [(e.clientX - r.left) * (this.device.width / r.width), (e.clientY - r.top) * (this.device.height / r.height)];
    };
    // A touch can end without its pointerup reaching the page (a system gesture, the host
    // app taking it over): left open, it would swallow every touch after it. A new first
    // finger ends it as cancelled, and so do losing the capture, the page and the focus.
    const abandon = () => {
      if (!this.touch) return;
      this.up(this.touch.last, this.clock.now(), true);
      this.pointerId = null;
    };
    s.addEventListener('pointerdown', (e) => {
      if (!this.touch && !this.enabled()) return;
      if (this.touch) {
        if (e.isPrimary && e.pointerId !== this.pointerId) abandon();
        else return;
      }
      e.preventDefault();
      try { s.setPointerCapture(e.pointerId); } catch (_) {}
      this.pointerId = e.pointerId;
      this.down(point(e), this.clock.now());
    });
    s.addEventListener('pointermove', (e) => {
      if (e.pointerId !== this.pointerId || !this.touch) return;
      const list = e.getCoalescedEvents ? e.getCoalescedEvents() : [];
      for (const ev of list.length ? list : [e]) this.move(point(ev), this.clock.now());
    });
    const end = (e) => {
      if (e.pointerId !== this.pointerId || !this.touch) return;
      this.up(point(e), this.clock.now(), e.type === 'pointercancel');
      this.pointerId = null;
    };
    s.addEventListener('pointerup', end);
    s.addEventListener('pointercancel', end);
    s.addEventListener('lostpointercapture', (e) => { if (e.pointerId === this.pointerId) abandon(); });
    window.addEventListener('blur', abandon);
    document.addEventListener('visibilitychange', () => { if (document.hidden) abandon(); });
  }

  inject(type, p, now) {
    if (type === 'down') this.down(p, now);
    else if (type === 'move') this.move(p, now);
    else this.up(p, now, false);
  }

  down(p, now) {
    this.tracker.reset();
    this.tracker.add(now, p[0], p[1]);
    const t = { start: p, last: p, t0: now, moved: false, target: null };
    this.touch = t;
    const sheet = this.sheet();
    if (sheet) {
      t.target = 'sheet';
      t.sheet = sheet;
      t.onPanel = sheet.hit(p[0], p[1]).kind !== 'outside';
      return;
    }
    const c = this.coinCenter();
    if (c && this.coin.physics.hitTest({ x: p[0] - c.x, y: p[1] - c.y })) {
      t.target = 'coin';
      t.center = c;
      this.coin.press(this.toCoin(p, c), now);
      return;
    }
    if (this.inertAvatar?.(p)) {
      t.target = 'avatar';
      return;
    }
    t.target = 'list';
    this.scroll?.begin(p[1], now);
    const row = this.rowAt(p);
    if (row) {
      t.row = row;
      t.highlightTimer = this.animator.after(HIGHLIGHT_DELAY, () => this.setHighlight(row, 1), now);
    }
  }

  move(p, now) {
    const t = this.touch;
    if (!t) return;
    this.tracker.add(now, p[0], p[1]);
    t.last = p;
    const dx = p[0] - t.start[0];
    const dy = p[1] - t.start[1];
    // A tap may wander a little (sideways more than up and down: the list and the sheets
    // only move vertically); past that it is a drag, starting from where it crossed.
    const crossed = t.target === 'coin' || t.target === 'avatar'
      ? Math.hypot(dx, dy) > COIN_SLOP
      : Math.abs(dy) > SLOP || Math.hypot(dx, dy) > 2 * SLOP;
    if (!t.moved && crossed) {
      t.moved = true;
      t.y0 = p[1];
      if (t.row) {
        t.highlightTimer?.cancel?.();
        this.setHighlight(t.row, 0, now);
        t.row = null;
      }
      if (t.target === 'list') this.scroll?.begin(p[1], now);
    }
    if (!t.moved) return;
    if (t.target === 'coin') this.coin.drag(this.toCoin(p, t.center), now);
    else if (t.target === 'list') this.scroll?.drag(p[1], now);
    else if (t.target === 'sheet' && t.onPanel) t.sheet.drag(p[1] - t.y0, now);
  }

  up(p, now, cancelled) {
    const t = this.touch;
    if (!t) return;
    this.touch = null;
    const v = this.tracker.velocity(now);
    if (t.target === 'sheet') {
      if (t.moved) {
        if (t.onPanel) t.sheet.endDrag(cancelled ? 0 : p[1] - t.y0, cancelled ? 0 : v.y, now);
        return;
      }
      if (cancelled) return;
      const hit = t.sheet.hit(p[0], p[1]);
      if (hit.kind === 'item') hit.item.onTap(now);
      else if (hit.kind === 'close' || hit.kind === 'outside') t.sheet.dismiss(now);
      return;
    }
    if (t.target === 'coin') {
      const r = this.coin.release(this.toCoin(p, t.center), now, cancelled);
      if (r.tap && !cancelled) this.onAvatarTap?.(now);
      return;
    }
    if (t.target === 'avatar') {
      if (!t.moved && !cancelled) this.onAvatarTap?.(now);
      return;
    }
    this.scroll?.end(cancelled || !t.moved ? 0 : v.y, now);
    if (t.row) {
      t.highlightTimer?.cancel?.();
      if (!cancelled && !t.moved) {
        this.setHighlight(t.row, 1);
        this.setHighlight(t.row, 0, now, 0.12);
        this.onRowTap?.(t.row.id, now);
      } else {
        this.setHighlight(t.row, 0, now);
      }
    }
  }

  toCoin(p, c) {
    return { x: p[0] - c.x, y: p[1] - c.y };
  }

  rowAt(p) {
    const off = this.scroll ? this.scroll.offset : 0;
    return this.rows().find((r) => p[0] >= r.x && p[0] <= r.x + r.w && p[1] >= r.y - off && p[1] <= r.y - off + r.h) || null;
  }

  // Telegram list rows: highlighted at once, fading out over 0.3 s.
  setHighlight(row, value, now, delay = 0) {
    row.fade?.cancel?.();
    if (value === 1 || now === undefined) {
      row.highlight.style.opacity = String(value);
      return;
    }
    const from = parseFloat(row.highlight.style.opacity || '0');
    row.fade = this.animator.tween({ from, to: 0, duration: 0.3, delay, apply: (o) => { row.highlight.style.opacity = o.toFixed(3); } }, now);
  }
}
