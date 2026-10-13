// The swipe actions of a chat row, ported from Telegram iOS
// (submodules/ItemListUI/Sources/ItemListRevealOptionsNode.swift, f1dd7a2, iOS 26 design):
// 50 pt circles in 60 pt slots, 10 pt apart and 10 pt from the edge, a Font.regular(11) title
// 4 pt below; each circle grows from 0.3 and fades in over the 20 pt where it leaves the row's
// edge (revealProgressCurve, response 2.7) and plays its icon once 30 % revealed; pulled past
// the full width the outermost ("primary") circle stretches into a capsule, and 100 pt further
// it "expands" (haptic, title out, icon to the inner end): letting go runs that action.
//
// layout() is the Swift updateNodesLayout() as a pure function of the reveal distance; the
// row interpolates two layouts for animated transitions, as Core Animation does.

import { LottieIcon } from './lottie-icon.js';

const SPACING = 10;
const EDGE_INSET = 10;
const TITLE_SPACING = 4;
const TITLE_LINE = 13;                 // floor(Font.regular(11).lineHeight = 13.13), line spacing 0
const EXPANDED_ACTIVATION = 50 * (3 - 1);
const EXPANDED_TRANSITION = 16;
const ICON_RESPONSE = 18;              // 1/s, the primary icon gliding to its expanded place
const TRIGGER = 0.3;                   // animationTriggerProgress
const RESET = 0.1;                     // interactiveAnimationResetProgress

export const RevealSettings = {      // ItemListRevealOptionsAnimationSettings.defaultSettings
  revealStartOverlap: 10,
  revealEndDistance: 10,
  revealProgressResponse: 2.7,
  minimumContentScale: 0.3,
  visualRevealSpring: 420,
  visualRevealDamping: 40,
  visualRevealSnapDistance: 0.25,
  visualRevealSnapVelocity: 12,
};

const METRICS = { shape: 50, slot: 60, iconMaxSide: 40, radius: 25, expandedIconInset: 20 };

const clamp01 = (v) => Math.max(0, Math.min(1, v));
const curve = (v, response) => 1 - Math.pow(1 - clamp01(v), Math.max(0.01, response));
const lerp = (a, b, t) => a + (b - a) * t;
const css = (c) => `rgb(${Math.round(c[0] * 255)},${Math.round(c[1] * 255)},${Math.round(c[2] * 255)})`;

function el(cls, style, parent, html) {
  const e = document.createElement('div');
  if (cls) e.className = cls;
  if (style) e.style.cssText = style;
  if (html !== undefined) e.innerHTML = html;
  if (parent) parent.appendChild(e);
  return e;
}

export class RevealOptions {
  // options: [{ key, title, color [r,g,b], iconColor, textColor, icon: { name, scale, offset, replaceColors, flip } }]
  constructor(parent, { options, isLeft, height, haptic }) {
    this.options = options;
    this.isLeft = isLeft;
    this.height = height;
    this.haptic = haptic || (() => {});
    this.count = options.length;
    this.width = EDGE_INSET * 2 + METRICS.shape * this.count + SPACING * (this.count - 1);
    this.root = el('reveal', `position:absolute;top:0;width:${this.width}px;height:${height}px;pointer-events:none`, parent);
    this.clip = el('', 'position:absolute;top:0;overflow:hidden', this.root);
    this.container = el('', 'position:absolute;top:0', this.clip);
    this.nodes = options.map((o) => this.buildNode(o));
    // Swift adds the left side's nodes in reverse; z-order only matters while they overlap.
    this.visual = { d: 0, v: 0, target: 0 };
    this.expanded = options.map(() => false);
    this.triggered = options.map(() => false);
    this.iconPos = options.map(() => null);   // manual glide of the primary icon (x)
    this.laidOut = false;
  }

  buildNode(o) {
    const node = el('reveal-node', 'position:absolute;top:0', this.container);
    const content = el('', 'position:absolute;left:0;top:0;transform-origin:50% 50%', node);
    const bg = el('', `position:absolute;background:${css(o.color)}`, content);
    const hi = el('', `position:absolute;background:${css(o.color.map((v) => v * 0.9))};opacity:0`, content);
    const icon = el('', 'position:absolute', content);
    const title = el('reveal-title', `position:absolute;white-space:nowrap;text-align:center;color:${css(o.textColor)}`, content, o.title);
    const lottie = o.icon ? new LottieIcon(icon, { name: o.icon.name, replaceColors: o.icon.replaceColors, color: o.color, flip: o.icon.flip, startFrame: o.icon.startFrame || 0 }) : null;
    return { o, node, content, bg, hi, icon, title, lottie, titleW: null };
  }

  titleWidth(n) {
    if (n.titleW === null) n.titleW = Math.ceil(n.title.getBoundingClientRect().width || n.o.title.length * 6);
    return n.titleW;
  }

  // Visual reveal distance: a spring that follows the finger outward (420 / 40 per unit
  // mass) and snaps inward at once.
  stepVisual(target, dt, animated) {
    const S = RevealSettings;
    const v = this.visual;
    v.target = Math.max(0, target);
    if (animated) { v.d = v.target; v.v = 0; return false; }
    if (v.d > v.target) { v.d = v.target; v.v = 0; }
    if (Math.abs(v.d - v.target) <= S.visualRevealSnapDistance && Math.abs(v.v) <= S.visualRevealSnapVelocity) {
      v.d = v.target; v.v = 0;
      return false;
    }
    const h = Math.min(0.05, Math.max(0, dt));
    // Integrated in 1/240 s steps: identical on a 60 Hz recording and a 120 Hz phone.
    const steps = Math.max(1, Math.ceil(h * 240));
    for (let i = 0; i < steps; i++) {
      const s = h / steps;
      const a = (v.target - v.d) * S.visualRevealSpring - v.v * S.visualRevealDamping;
      v.v += a * s;
      let d = v.d + v.v * s;
      if (d > v.target) { d = v.target; v.v = 0; } else if (d < 0) { d = 0; v.v = 0; }
      v.d = d;
    }
    if (Math.abs(v.d - v.target) <= S.visualRevealSnapDistance && Math.abs(v.v) <= S.visualRevealSnapVelocity) {
      v.d = v.target; v.v = 0;
    }
    return v.d !== v.target;
  }

  // updateNodesLayout() for a reveal distance (pt, ≥ 0) → plain numbers per option.
  layout(revealed, visualRevealed) {
    const S = RevealSettings;
    const M = METRICS;
    const size = { w: this.width, h: this.height };
    const bounded = Math.min(revealed, size.w);
    const boundedVisual = Math.min(visualRevealed, revealed, size.w);
    const over = Math.max(0, revealed - size.w);
    const overProgress = clamp01(over / EXPANDED_TRANSITION);
    const primaryIndex = this.isLeft ? 0 : this.count - 1;
    const stride = M.shape + SPACING;
    const clipX = this.isLeft ? Math.max(0, size.w - revealed) : 0;
    const out = { clip: { x: clipX, w: revealed }, containerX: -clipX, containerW: Math.max(size.w, revealed), nodes: [] };
    const prog = (edge) => curve((edge + S.revealStartOverlap) / Math.max(1, S.revealStartOverlap + S.revealEndDistance), S.revealProgressResponse);
    for (let i = 0; i < this.count; i++) {
      const isPrimary = i === primaryIndex;
      const isStretched = isPrimary && over > 1e-6;
      const isExpanded = isPrimary && over > EXPANDED_ACTIVATION;
      let nodeX, nodeW, revealProgress, animationProgress;
      if (this.isLeft) {
        const baseLeft = size.w - bounded + EDGE_INSET + i * stride;
        const visualLeft = size.w - boundedVisual + EDGE_INSET + i * stride;
        revealProgress = prog(size.w - (visualLeft + M.shape));
        animationProgress = prog(size.w - (baseLeft + M.shape));
        if (isStretched) {
          const primaryLeft = size.w - bounded + EDGE_INSET;
          const primaryRight = this.count > 1
            ? Math.max(primaryLeft + M.shape, primaryLeft + stride + over - SPACING)
            : primaryLeft + M.shape + over;
          nodeX = Math.floor(primaryLeft);
          nodeW = Math.max(M.shape, primaryRight - primaryLeft);
        } else {
          const circleLeft = baseLeft + (isPrimary ? 0 : over);
          nodeX = Math.floor(circleLeft - (M.slot - M.shape) / 2);
          nodeW = M.slot;
        }
      } else {
        const baseRight = revealed - EDGE_INSET - (this.count - 1 - i) * stride;
        const visualRight = boundedVisual - EDGE_INSET - (this.count - 1 - i) * stride;
        const animRight = bounded - EDGE_INSET - (this.count - 1 - i) * stride;
        revealProgress = prog(visualRight - M.shape);
        animationProgress = prog(animRight - M.shape);
        if (isStretched) {
          const primaryRight = revealed - EDGE_INSET;
          const primaryLeft = this.count > 1
            ? Math.min(primaryRight - M.shape, primaryRight - stride - over + SPACING)
            : primaryRight - M.shape - over;
          nodeX = Math.floor(primaryLeft);
          nodeW = Math.max(M.shape, primaryRight - primaryLeft);
        } else {
          const circleLeft = baseRight - M.shape - (isPrimary ? 0 : over);
          nodeX = Math.floor(circleLeft - (M.slot - M.shape) / 2);
          nodeW = M.slot;
        }
      }
      out.nodes.push(this.optionLayout(i, { isPrimary, isStretched, isExpanded, nodeX, nodeW, revealProgress, animationProgress, overProgress }));
    }
    return out;
  }

  // ItemListRevealOptionNode.updateLayout as numbers (node-local coordinates).
  optionLayout(i, p) {
    const M = METRICS;
    const n = this.nodes[i];
    const h = this.height;
    const contentH = M.shape + TITLE_SPACING + TITLE_LINE;
    const shapeY = Math.floor((h - contentH) * 2) / 4;    // floor to the 2× pixel: 4.5 on a 76 pt row
    const shapeX = p.isStretched ? (this.isLeft ? 0 : p.nodeW - M.shape) : Math.floor((M.slot - M.shape) / 2);
    const shape = { x: shapeX, y: shapeY, w: M.shape, h: M.shape };
    const bg = p.isStretched ? { x: 0, y: shapeY, w: p.nodeW, h: M.shape } : shape;
    const alpha = p.isPrimary ? p.revealProgress : p.revealProgress * (1 - 0.3 * p.overProgress);
    const scale = RevealSettings.minimumContentScale + (1 - RevealSettings.minimumContentScale) * p.revealProgress;
    const expandedProgress = p.isExpanded ? 1 : 0;
    const titleAlpha = p.isPrimary ? 1 - expandedProgress : 1;
    const centered = p.isPrimary ? bg.x + bg.w / 2 : shape.x + shape.w / 2;
    let iconX = centered;
    if (p.isPrimary && expandedProgress > 0) {
      const target = this.isLeft ? bg.x + bg.w - M.expandedIconInset : bg.x + M.expandedIconInset;
      iconX = centered + (target - centered) * expandedProgress;
    }
    const scaleIcon = n.o.icon?.scale ?? 1;
    let iconSize = 66 * scaleIcon;
    if (iconSize > M.iconMaxSide) iconSize = Math.floor(iconSize * (M.iconMaxSide / iconSize) * 1.5);
    const iconY = Math.floor(bg.y + bg.h / 2 - iconSize / 2) + (6 + (n.o.icon?.offset || 0)) * (iconSize / 56);
    const titleW = this.titleWidth(n);
    const titleCX = p.isPrimary ? bg.x + bg.w / 2 : shape.x + shape.w / 2;
    return {
      ...p, nodeW: p.nodeW, bg, alpha, scale, titleAlpha,
      icon: { cx: iconX, y: iconY, size: iconSize },
      title: { x: Math.floor(titleCX - titleW / 2), y: shape.y + shape.h + TITLE_SPACING, w: titleW },
    };
  }

  // Blend of two layouts (an animated transition), t = curve progress 0…1.
  static mix(a, b, t) {
    if (!a) return b;
    const m = (x, y) => lerp(x, y, t);
    return {
      clip: { x: m(a.clip.x, b.clip.x), w: m(a.clip.w, b.clip.w) },
      containerX: m(a.containerX, b.containerX),
      containerW: m(a.containerW, b.containerW),
      nodes: b.nodes.map((nb, i) => {
        const na = a.nodes[i];
        return {
          ...nb,
          nodeX: m(na.nodeX, nb.nodeX), nodeW: m(na.nodeW, nb.nodeW),
          bg: { x: m(na.bg.x, nb.bg.x), y: nb.bg.y, w: m(na.bg.w, nb.bg.w), h: nb.bg.h },
          alpha: m(na.alpha, nb.alpha), scale: m(na.scale, nb.scale), titleAlpha: m(na.titleAlpha, nb.titleAlpha),
          icon: { cx: m(na.icon.cx, nb.icon.cx), y: nb.icon.y, size: nb.icon.size },
          title: { x: m(na.title.x, nb.title.x), y: nb.title.y, w: nb.title.w },
        };
      }),
    };
  }

  // Applies a layout. `interactive`: the finger drives it (haptics, icon triggers and resets
  // follow it); otherwise it is a frame of an animated transition toward `final`.
  apply(L, now, dt, { interactive, final = L }) {
    const set = (e, k, v) => { if (e.style[k] !== v) e.style[k] = v; };
    set(this.clip, 'left', `${L.clip.x.toFixed(2)}px`);
    set(this.clip, 'width', `${Math.max(0, L.clip.w).toFixed(2)}px`);
    set(this.clip, 'height', `${this.height}px`);
    set(this.container, 'left', `${L.containerX.toFixed(2)}px`);
    set(this.container, 'width', `${L.containerW.toFixed(2)}px`);
    set(this.container, 'height', `${this.height}px`);
    let busy = false;
    L.nodes.forEach((p, i) => {
      const n = this.nodes[i];
      const f = final.nodes[i];
      // Expanding / collapsing the primary: a haptic, and its icon glides (1 − e^(−18 t)).
      if (this.laidOut && f.isExpanded !== this.expanded[i] && interactive) this.haptic(f.isExpanded);
      const glide = this.laidOut && f.isExpanded !== this.expanded[i] && f.revealProgress > 1e-6;
      this.expanded[i] = f.isExpanded;
      let iconCX = p.icon.cx;
      if (p.isPrimary) {
        const cur = this.iconPos[i];
        if (glide || (cur !== null && cur.gliding)) {
          const from = cur ? cur.x : iconCX;
          const k = 1 - Math.exp(-Math.min(0.05, dt) * ICON_RESPONSE);
          const x = from + (iconCX - from) * k;
          const done = Math.abs(x - iconCX) <= 0.5;
          this.iconPos[i] = { x: done ? iconCX : x, gliding: !done };
          iconCX = this.iconPos[i].x;
          busy = busy || !done;
        } else {
          this.iconPos[i] = { x: iconCX, gliding: false };
        }
      }
      set(n.node, 'left', `${p.nodeX.toFixed(2)}px`);
      set(n.node, 'width', `${p.nodeW.toFixed(2)}px`);
      set(n.node, 'height', `${this.height}px`);
      set(n.content, 'width', `${p.nodeW.toFixed(2)}px`);
      set(n.content, 'height', `${this.height}px`);
      set(n.content, 'opacity', p.alpha.toFixed(3));
      set(n.content, 'transform', `scale(${p.scale.toFixed(4)})`);
      for (const b of [n.bg, n.hi]) {
        set(b, 'left', `${p.bg.x.toFixed(2)}px`);
        set(b, 'top', `${p.bg.y}px`);
        set(b, 'width', `${p.bg.w.toFixed(2)}px`);
        set(b, 'height', `${p.bg.h}px`);
        set(b, 'borderRadius', `${METRICS.radius}px`);
      }
      set(n.icon, 'left', `${(iconCX - p.icon.size / 2).toFixed(2)}px`);
      set(n.icon, 'top', `${p.icon.y.toFixed(2)}px`);
      set(n.icon, 'width', `${p.icon.size}px`);
      set(n.icon, 'height', `${p.icon.size}px`);
      set(n.title, 'left', `${p.title.x.toFixed(2)}px`);
      set(n.title, 'top', `${p.title.y}px`);
      set(n.title, 'opacity', p.titleAlpha.toFixed(3));
      // Icon: plays once the circle is 30 % out; an interactive close below 10 % rewinds it.
      if (n.lottie) {
        if (f.animationProgress >= TRIGGER) {
          if (!this.triggered[i]) { this.triggered[i] = true; n.lottie.play(now); }
        } else if (interactive && p.revealProgress <= RESET && this.triggered[i]) {
          this.triggered[i] = false;
          n.lottie.reset();
        }
        if (n.lottie.update(now)) busy = true;
      }
    });
    this.laidOut = true;
    return busy;
  }

  // The row closed completely: every icon back to its first frame.
  resetAnimations() {
    this.nodes.forEach((n, i) => { this.triggered[i] = false; n.lottie?.reset(); });
    this.iconPos = this.nodes.map(() => null);
    this.expanded = this.nodes.map(() => false);
    this.visual = { d: 0, v: 0, target: 0 };
  }

  get displaysExtendedAction() {
    return this.expanded.some(Boolean);
  }

  // Which option a point (node-local x, y) hits.
  hit(x, y) {
    for (let i = 0; i < this.count; i++) {
      const n = this.nodes[i];
      const l = parseFloat(n.node.style.left) + parseFloat(this.container.style.left || '0') + parseFloat(this.clip.style.left || '0');
      const w = parseFloat(n.node.style.width);
      if (x >= l && x <= l + w && y >= 0 && y <= this.height) return i;
    }
    return -1;
  }

  setHighlighted(i, on) {
    const n = this.nodes[i];
    if (n) n.hi.style.opacity = on ? '1' : '0';
  }
}
