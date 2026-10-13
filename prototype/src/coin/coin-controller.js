// Wires input → GlassCoin physics → CoinRenderer, plus haptics.
// Gesture arbitration (ui/input.js) mirrors the native recognizer: the avatar lifts on
// touch, keeps sideways drags and hands vertical ones to the list; a tap is forwarded
// so the header can expand the avatar as today.

import { Haptics } from '../core/haptics.js';

export class CoinController {
  constructor({ canvas, renderer, physics, getFrame, onTap, sizePt }) {
    this.canvas = canvas;
    this.renderer = renderer;
    this.physics = physics;
    this.getFrame = getFrame;
    this.onTap = onTap || (() => {});
    this.sizePt = sizePt;
    this.activePointer = null;
    this.needsFrame = true;
    physics.onTick = (kind) => {
      if (kind === 'catch') Haptics.impact('rigid');
      else Haptics.impact('light');
    };
    physics.onLand = (changed) => {
      if (changed) Haptics.impact('medium');
      this.onLand?.(changed);
    };
  }

  // Client px → pt relative to the coin centre (screen axes, y down).
  toCoin(clientX, clientY) {
    const r = this.canvas.getBoundingClientRect();
    const k = this.sizePt / r.width;
    return { x: (clientX - (r.left + r.width / 2)) * k, y: (clientY - (r.top + r.height / 2)) * k };
  }

  // Input arrives through the page's InputRouter (ui/input.js), real touches and
  // scripted demos alike; points are in pt relative to the avatar centre.
  press(p, now) {
    Haptics.prepare();
    Haptics.impact('soft'); // the avatar lifts into glass
    this.physics.pointerDown(p, now);
    this.needsFrame = true;
  }

  drag(p, now) {
    this.physics.pointerMove(p, now);
    this.needsFrame = true;
  }

  release(p, now, cancelled = false) {
    this.needsFrame = true;
    if (cancelled) {
      this.physics.cancel(now);
      return { tap: false };
    }
    const r = this.physics.pointerUp(p, now);
    if (r.tap) this.onTap();
    return r;
  }

  cancel(now) {
    this.physics.cancel(now);
    this.needsFrame = true;
  }

  // Synthetic input for recorded demos (same code path as real touches).
  inject(type, p, now) {
    if (type === 'down') this.physics.pointerDown(p, now);
    else if (type === 'move') this.physics.pointerMove(p, now);
    else if (type === 'up') {
      const r = this.physics.pointerUp(p, now);
      if (r.tap) this.onTap();
    }
    this.needsFrame = true;
  }

  frame(now) {
    const state = this.physics.state(now);
    this.renderer.render(state, this.getFrame(state));
    const animating = this.physics.isAnimating;
    this.needsFrame = animating;
    return state;
  }
}
