// PeerInfoCoverComponent, drawn into a 2D canvas.
//   backgroundView        : fill = secondary colour
//   backgroundGradientLayer: axial, bottom = main → top = secondary, `defaultHeight` tall,
//                           anchored to the bottom of the banner
//   avatarBackgroundGradientLayer: 300×300 radial white, alpha 0.4·(1 − i/5)²
//   pattern               : 5 rings × 6 glyphs (LokiRng seed 123 sizes), tinted black 0.8,
//                           masked into a radial black 0.6 → 0 layer, `overlayBlendMode`
// (PeerInfoCoverComponent.swift:242-252, 485-650)

// floor(26 · (0.7 + 0.3 · LokiRng(123,0,0).next())) for the 30 items, ring by ring.
const PATTERN_SIZES = [
  24, 18, 24, 19, 25, 22,
  20, 20, 20, 25, 19, 18,
  18, 18, 20, 18, 22, 18,
  22, 24, 21, 18, 22, 23,
  20, 18, 23, 20, 19, 22,
];

// patternScaleValueAt(fraction:t:reverse: false) — PeerInfoCoverComponent.swift:41-62,
// window function bezierPoint(0.6, 0, 0.4, 1) (Display/Source/Spring.swift:60).
function patternScaleValueAt(fraction, t) {
  const windowSize = 0.8;
  const windowPosition = (1 - fraction) * -windowSize + fraction * 1.0;
  const windowT = Math.max(0, Math.min(windowSize, t - windowPosition)) / windowSize;
  return 1 - bezierEase(windowT, 0.6, 0, 0.4, 1);
}

function bezierEase(x, x1, y1, x2, y2) {
  // Solve cubic-bezier(x1, y1, x2, y2) for y at x (Newton + bisection).
  const cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx;
  const cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by;
  const sx = (t) => ((ax * t + bx) * t + cx) * t;
  const sy = (t) => ((ay * t + by) * t + cy) * t;
  let t = x;
  for (let i = 0; i < 8; i++) {
    const err = sx(t) - x;
    const d = (3 * ax * t + 2 * bx) * t + cx;
    if (Math.abs(err) < 1e-6 || Math.abs(d) < 1e-6) break;
    t -= err / d;
  }
  t = Math.max(0, Math.min(1, t));
  return sy(t);
}

export function patternItems(avatarSize = 100, avatarTransitionFraction = 0) {
  const baseDistance = avatarSize / 2 + 22;
  const baseRowDistance = 28;
  const items = [];
  let k = 0;
  for (let row = 0; row < 5; row++) {
    const span = (Math.PI * 2) / 6;
    for (let i = 0; i < 6; i++) {
      const baseItemDistance = baseDistance + row * baseRowDistance;
      const itemDistanceFraction = Math.max(0, Math.min(1, baseItemDistance / (baseDistance * 2)));
      const s = patternScaleValueAt(avatarTransitionFraction * 1.6, itemDistanceFraction);
      const distance = baseItemDistance * (1 - s) + 20 * s;
      let angle = -Math.PI / 2 + i * span;
      if (row % 2 !== 0) angle += span / 2;
      items.push({ dx: Math.cos(angle) * distance, dy: Math.sin(angle) * distance, size: PATTERN_SIZES[k], alpha: 1 - s });
      k++;
    }
  }
  return items;
}

export class Cover {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.mask = document.createElement('canvas');
    this.mctx = this.mask.getContext('2d');
    this.glyph = null;
    this.version = 0;
  }

  // The pattern glyph is an SVG; drawing an SVG image rasterizes it on every call (30 per
  // frame while the header scrolls), so it is rasterized once at the largest size it is drawn.
  glyphBitmap(glyph, scale) {
    const px = Math.ceil(26 * 1.2 * scale);
    if (this.glyphSrc !== glyph || this.glyphPx !== px) {
      const c = document.createElement('canvas');
      c.width = px;
      c.height = px;
      const g = c.getContext('2d');
      g.imageSmoothingQuality = 'high';
      g.drawImage(glyph, 0, 0, px, px);
      this.glyphSrc = glyph;
      this.glyphPx = px;
      this.glyphCanvas = c;
    }
    return this.glyphCanvas;
  }

  // params: { width, height (banner), defaultHeight, avatarCenter{x,y}, main, secondary (Color),
  //           glyph (HTMLImageElement|null), dark, scale, avatarTransitionFraction, glow (bool),
  //           itemOffset(i, item) → {dx, dy, scale} optional live perturbation }
  draw(p) {
    const { width, height, scale } = p;
    // The canvas keeps a fixed size (canvasHeight, room for pulling the header down); the
    // banner fills its top `height` points and the rest stays clear.
    const canvasHeight = p.canvasHeight || height;
    const c = this.canvas;
    const pxW = Math.round(width * scale);
    const pxH = Math.round(canvasHeight * scale);
    if (c.width !== pxW || c.height !== pxH) {
      c.width = pxW;
      c.height = pxH;
    }
    const ctx = this.ctx;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, pxW, pxH);
    ctx.setTransform(scale, 0, 0, scale, 0, 0);
    ctx.globalCompositeOperation = 'source-over';
    ctx.globalAlpha = 1;
    ctx.save();
    ctx.beginPath();
    ctx.rect(0, 0, width, Math.min(height, canvasHeight));
    ctx.clip();

    // backgroundView
    ctx.fillStyle = p.secondary.css();
    ctx.fillRect(0, 0, width, height);

    // backgroundGradientLayer (anchored to the banner bottom)
    const gh = p.defaultHeight;
    const gy = height - gh;
    const g = ctx.createLinearGradient(0, gy + gh, 0, gy);
    g.addColorStop(0, p.main.css());
    g.addColorStop(1, p.secondary.css());
    ctx.fillStyle = g;
    ctx.fillRect(0, gy, width, gh);

    const ax = p.avatarCenter.x;
    const ay = p.avatarCenter.y;

    // avatarBackgroundGradientLayer
    if (p.glow !== false) {
      const glowAlpha = 1 - (p.avatarTransitionFraction || 0);
      if (glowAlpha > 0) {
        const rg = ctx.createRadialGradient(ax, ay, 0, ax, ay, 150);
        for (let i = 0; i < 6; i++) {
          const step = 1 - i / 5;
          rg.addColorStop(i / 5, `rgba(255,255,255,${(0.4 * step * step * glowAlpha).toFixed(4)})`);
        }
        ctx.fillStyle = rg;
        ctx.fillRect(ax - 150, ay - 150, 300, 300);
      }
    }

    // Pattern: glyphs → mask, × radial alpha (0.6 → 0 over the 380 × defaultHeight ellipse), overlay
    if (p.glyph) {
      const fw = 380;
      const fh = p.defaultHeight;
      const m = this.mask;
      const mw = Math.round(fw * scale);
      const mh = Math.round(fh * scale);
      if (m.width !== mw || m.height !== mh) {
        m.width = mw;
        m.height = mh;
      }
      const mctx = this.mctx;
      mctx.setTransform(1, 0, 0, 1, 0, 0);
      mctx.globalCompositeOperation = 'source-over';
      mctx.clearRect(0, 0, mw, mh);
      mctx.setTransform(scale, 0, 0, scale, 0, 0);
      const glyph = this.glyphBitmap(p.glyph, scale);
      mctx.imageSmoothingQuality = 'high';
      const items = patternItems(p.avatarSize || 100, p.avatarTransitionFraction || 0);
      const ps = p.patternScale || 1; // sublayerTransform.scale of the pattern (transition bounce)
      items.forEach((it, i) => {
        let { dx, dy, size } = it;
        dx *= ps;
        dy *= ps;
        size *= ps;
        let s = 1;
        let a = it.alpha;
        if (p.itemOffset) {
          const o = p.itemOffset(i, it);
          if (o) { dx += o.dx || 0; dy += o.dy || 0; s *= o.scale || 1; a *= o.alpha ?? 1; }
        }
        if (a <= 0) return;
        const sz = size * s;
        mctx.globalAlpha = 0.8 * a;
        mctx.drawImage(glyph, fw / 2 + dx - sz / 2, fh / 2 + dy - sz / 2, sz, sz);
      });
      mctx.globalAlpha = 1;
      // layerTintColor = UIColor(white: 0, alpha: 0.8): the glyphs become black (alpha kept)
      mctx.setTransform(1, 0, 0, 1, 0, 0);
      mctx.globalCompositeOperation = 'source-in';
      mctx.fillStyle = '#000';
      mctx.fillRect(0, 0, mw, mh);
      mctx.setTransform(scale, 0, 0, scale, 0, 0);
      // radial alpha: CAGradientLayer .radial from (0.5,0.5) to (1,1) → ellipse inscribed in the frame
      mctx.globalCompositeOperation = 'destination-in';
      mctx.save();
      mctx.translate(fw / 2, fh / 2);
      mctx.scale(1, fh / fw);
      const rg = mctx.createRadialGradient(0, 0, 0, 0, 0, fw / 2);
      rg.addColorStop(0, 'rgba(0,0,0,0.6)');
      rg.addColorStop(1, 'rgba(0,0,0,0)');
      mctx.fillStyle = rg;
      mctx.fillRect(-fw / 2, -fw / 2, fw, fw);
      mctx.restore();
      mctx.globalCompositeOperation = 'source-over';

      ctx.save();
      ctx.globalCompositeOperation = 'overlay';
      ctx.drawImage(m, ax - fw / 2, ay - fh / 2, fw, fh);
      ctx.restore();
      this.patternRect = { x: ax - fw / 2, y: ay - fh / 2, w: fw, h: fh }; // where the mask sits (cover pt)
    }
    ctx.restore();
    this.version++;
  }
}
