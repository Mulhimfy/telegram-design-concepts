// iOS 26 floating sheet, as Telegram presents its compact sheets on iOS 26: a glass
// panel inset 8 pt from the screen edges with 38 pt corners, a round glass close
// button top-left and the title centred. It rises on the iOS 26 spring and leaves on a
// critically damped one; a tap above it or on the close button dismisses it, and so does a
// drag down past a third of its height or a flick (it follows the finger, rubber-banded upward).

import { SpringParams, SpringValue, rubberBand } from '../core/spring.js';

function el(tag, cls, style, parent, html) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (style) e.style.cssText = style;
  if (html !== undefined) e.innerHTML = html;
  if (parent) parent.appendChild(e);
  return e;
}

const closeIcon = '<svg viewBox="0 0 44 44" width="44" height="44"><path d="M16 16 L28 28 M28 16 L16 28" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/></svg>';

export class Sheet {
  // build(body, { width }) fills the sheet and returns its tappable items:
  // [{ x, y, w, h, onTap(now), onPress?(down, now) }] in sheet-body points.
  constructor(screen, { device, title, subtitle, height, build, onClose, dim = true }) {
    this.device = device;
    this.dims = dim;   // a picker with a live preview leaves the screen undimmed
    this.height = height;
    this.onClose = onClose;
    this.inset = 8;
    this.width = device.width - this.inset * 2;
    this.top = device.height - this.inset - height;
    this.dim = el('div', 'sheet-dim', 'display:none', screen);
    // Corners concentric with the screen's (iOS 26 floating sheets).
    const radius = Math.max(32, (device.corner || 46) - this.inset);
    this.panel = el('div', 'sheet', `left:${this.inset}px;top:${this.top}px;width:${this.width}px;height:${height}px;border-radius:${radius}px;display:none`, screen);
    this.close = el('div', 'glass', 'left:12px;top:12px;width:44px;height:44px;color:var(--tg-text);z-index:2', this.panel, closeIcon);
    el('div', 'sheet-title', '', this.panel, title);
    if (subtitle) el('div', 'sheet-subtitle', '', this.panel, subtitle);
    this.bodyTop = subtitle ? 76 : 64;
    this.body = el('div', 'abs', `left:0;top:${this.bodyTop}px;width:${this.width}px;height:${height - this.bodyTop}px`, this.panel);
    this.items = build(this.body, { width: this.width, height: height - this.bodyTop }) || [];
    this.progress = new SpringValue(0, SpringParams.fromResponse(0.44, 0.86));
    this.progress.epsilon = 1e-3;
    this.isOpen = false;
    this.apply(0);
  }

  get visible() {
    return this.isOpen || !this.progress.settled;
  }

  open(now) {
    this.isOpen = true;
    this.dim.style.display = '';
    this.panel.style.display = '';
    this.progress.animate(1, now, { params: SpringParams.fromResponse(0.44, 0.86) });
  }

  dismiss(now) {
    if (!this.isOpen) return;
    this.isOpen = false;
    this.progress.animate(0, now, { params: SpringParams.fromResponse(0.34, 1.0) });
    this.onClose?.(now);
  }

  apply(p) {
    const travel = this.height + this.inset + 24;
    this.panel.style.transform = `translateY(${((1 - p) * travel).toFixed(2)}px)`;
    this.dim.style.opacity = this.dims ? String(Math.max(0, Math.min(1, p))) : '0';
  }

  update(now) {
    const p = this.progress.update(now);
    this.apply(p);
    if (!this.isOpen && this.progress.settled) {
      this.dim.style.display = 'none';
      this.panel.style.display = 'none';
    }
    return !this.progress.settled;
  }

  get travel() {
    return this.height + this.inset + 24;
  }

  // Finger travel since the drag began (pt, down = positive).
  drag(dy, now) {
    const p = dy >= 0 ? 1 - dy / this.travel : 1 + rubberBand(-dy, 120) / this.travel;
    this.progress.set(p, now);
    this.apply(p);
  }

  endDrag(dy, vy, now) {
    const velocity = -vy / this.travel;
    if (dy > this.height * 0.3 || vy > 700) {
      this.isOpen = false;
      this.progress.animate(0, now, { params: SpringParams.fromResponse(0.34, 1.0), velocity });
      this.onClose?.(now);
    } else {
      this.progress.animate(1, now, { params: SpringParams.fromResponse(0.38, 0.9), velocity });
    }
  }

  // Screen point → what it hits while the sheet is up (where it is now: it may still be rising).
  hit(x, y) {
    const lx = x - this.inset;
    const ly = y - this.top - (1 - this.progress.value) * this.travel;
    if (ly < 0) return { kind: 'outside' };
    if (lx >= 12 && lx <= 56 && ly >= 12 && ly <= 56) return { kind: 'close' };
    const bx = lx;
    const by = ly - this.bodyTop;
    for (const it of this.items) {
      if (bx >= it.x && bx <= it.x + it.w && by >= it.y && by <= it.y + it.h) return { kind: 'item', item: it };
    }
    return { kind: 'panel' };
  }

  // Centre of an item in screen points (for scripted taps).
  itemCenter(index) {
    const it = this.items[index];
    return [this.inset + it.x + it.w / 2, this.top + this.bodyTop + it.y + it.h / 2];
  }
}
