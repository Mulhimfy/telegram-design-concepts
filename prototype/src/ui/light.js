// The light of the glass colour (designer video 35–65 s: as the profile colour cycles,
// nearby glass rims pick up the light on the side facing it). Picking a glass colour
// sends a ring of that light from the avatar across the whole screen: the emoji pattern
// glints as it passes, the glass buttons light up on the side facing the avatar, and a
// soft glow of the colour stays around the avatar (brighter while the photo is held).
// The ring is drawn in one screen-blended canvas above the page (below the tab bar and
// sheets) that exists only while it runs; the glow and the rim lights are layers whose
// opacity and position change per frame, so scrolling and holding cost no repaint.

const WAVE = 1.1; // s: ~0.35 s across the header, the rest of the screen by the end
const GLOW = 180; // pt: radius of the glow layer

export function rgba(c, a) {
  return `rgba(${Math.round(c[0] * 255)},${Math.round(c[1] * 255)},${Math.round(c[2] * 255)},${Math.max(0, a).toFixed(4)})`;
}

export const lighten = (c, k) => c.map((v) => v + (1 - v) * k);

export class LightLayer {
  constructor(screen, { device, scale, origin, radius = 50, cover, glassEls = [], dark = true, under = null }) {
    this.W = device.width;
    this.H = device.height;
    this.scale = scale;
    this.origin = { ...origin };
    this.radius = radius;
    this.cover = cover;
    this.glassEls = glassEls;
    this.dark = dark;
    const c = document.createElement('canvas');
    c.className = 'abs';
    // Dark: light adds (screen). Light theme: screen would vanish on white, so the light is a
    // soft coloured band instead.
    c.style.cssText = `left:0;top:0;width:${this.W}px;height:${this.H}px;z-index:25;pointer-events:none;mix-blend-mode:${dark ? 'screen' : 'normal'};display:none`;
    this.strength = dark ? 1 : 0.42;
    c.width = Math.round(this.W * scale);
    c.height = Math.round(this.H * scale);
    screen.appendChild(c);
    this.canvas = c;
    this.ctx = c.getContext('2d');
    this.temp = document.createElement('canvas');
    this.shown = false;
    // The glow around the avatar: two layers under it (the colour and the one it replaces).
    this.glows = [0, 1].map(() => {
      const g = document.createElement('div');
      g.className = 'abs';
      g.style.cssText = `left:${-GLOW}px;top:${-GLOW}px;width:${GLOW * 2}px;height:${GLOW * 2}px;z-index:2;pointer-events:none;opacity:0;will-change:transform,opacity;mix-blend-mode:${dark ? 'screen' : 'normal'}`;
      if (under) screen.insertBefore(g, under);
      else screen.appendChild(g);
      return g;
    });
    this.front = 0;
    this.color = [1, 1, 1];
    this.tint = 0;
    this.from = { color: [1, 1, 1], tint: 0 };
    this.wave = null;
    this.visibility = 1; // the header can fade it (scrolling)
    this.lift = 0;       // the glass while the photo is held: the glow brightens
    this.dirty = true;
    this.spillLayers = new Map();
    this.geo = new WeakMap();
    this.paintGlow(this.glows[0], this.color);
  }

  // Sets the colour without the wave (restoring a saved choice).
  set(color) {
    this.color = color || [1, 1, 1];
    this.tint = color ? 1 : 0;
    this.from = { color: this.color, tint: 0 };
    this.wave = null;
    this.paintGlow(this.glows[this.front], this.color);
    this.dirty = true;
  }

  // A new glass colour (rgb 0…1, or null for clear glass).
  change(color, now) {
    this.from = { color: this.color, tint: this.tint };
    this.color = color || [1, 1, 1];
    this.tint = color ? 1 : 0;
    this.front = 1 - this.front;           // the old glow stays on the other layer and fades
    this.paintGlow(this.glows[this.front], this.color);
    this.wave = { t0: now, color: lighten(this.color, color ? 0.18 : 0.6), strength: color ? 1 : 0.55 };
    this.dirty = true;
  }

  setOrigin(x, y, visibility = 1) {
    if (x === this.origin.x && y === this.origin.y && visibility === this.visibility) return;
    this.origin = { x, y };
    this.visibility = visibility;
    this.dirty = true;
  }

  setLift(lift) {
    const v = Math.max(0, Math.min(1, lift));
    if (Math.abs(v - this.lift) < 0.004 && (v > 0 || this.lift === 0)) return;
    this.lift = v;
    this.dirty = true;
  }

  // Wave progress → (radius, width, intensity) in screen pt.
  ring(u) {
    const o = this.origin;
    const far = Math.max(
      Math.hypot(o.x, o.y), Math.hypot(this.W - o.x, o.y),
      Math.hypot(o.x, this.H - o.y), Math.hypot(this.W - o.x, this.H - o.y));
    const travel = 0.62 * u + 0.38 * u * u;   // steady, gathering pace once past the header
    const r = this.radius + (far + 80 - this.radius) * travel;
    const w = 30 + 100 * u;
    const intensity = Math.min(1, u / 0.06) * Math.pow(1 - u, 1.5);
    return { r, w, intensity };
  }

  update(now) {
    const waving = this.wave && now - this.wave.t0 < WAVE;
    if (this.wave && !waving) {
      this.wave = null;      // one last draw without the ring
      this.dirty = true;
    }
    if (!waving && !this.dirty) return false;
    this.dirty = false;
    let k = 1;
    let wave = null;
    if (this.wave) {
      const u = Math.min(1, (now - this.wave.t0) / WAVE);
      k = Math.min(1, u / 0.35);
      k = k * k * (3 - 2 * k);
      wave = { u, ...this.ring(u) };
    }
    this.placeGlow(k);
    this.drawWave(wave);
    this.spill(wave);
    return !!waving;
  }

  // Ambient glow of the glass colour (cross-fades from the previous colour as the wave
  // leaves the avatar; brighter while the photo is held).
  paintGlow(el, color) {
    const a = (this.dark ? 0.2 : 0.1) * 1.8;   // at full lift; opacity scales it down
    el.style.background = `radial-gradient(circle closest-side, ${rgba(color, a)} 17%, ${rgba(color, a * 0.55)} 45%, ${rgba(color, 0)} 97%)`;
  }

  placeGlow(k) {
    const o = this.origin;
    const boost = (1 + 0.8 * this.lift) / 1.8;
    const t = `translate3d(${o.x.toFixed(2)}px,${o.y.toFixed(2)}px,0)`;
    const set = (el, amount) => {
      const op = Math.max(0, Math.min(1, amount * this.visibility * boost));
      const s = op < 0.003 ? '0' : op.toFixed(3);
      if (el.style.opacity !== s) el.style.opacity = s;
      if (el.style.transform !== t) el.style.transform = t;
    };
    set(this.glows[this.front], this.tint * k);
    set(this.glows[1 - this.front], this.from.tint * (1 - k));
  }

  drawWave(wave) {
    if (!wave || wave.intensity <= 0) {
      if (this.shown) {
        this.ctx.setTransform(1, 0, 0, 1, 0, 0);
        this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
        this.canvas.style.display = 'none';
        this.shown = false;
      }
      return;
    }
    if (!this.shown) {
      this.canvas.style.display = '';
      this.shown = true;
    }
    const { ctx, scale } = this;
    const o = this.origin;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalCompositeOperation = 'source-over';
    ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
    ctx.setTransform(scale, 0, 0, scale, 0, 0);
    const vis = this.visibility;
    const { r, w, intensity } = wave;
    const c = this.wave.color;
    const a = 0.7 * intensity * this.wave.strength * vis * this.strength;
    ctx.fillStyle = this.ringGradient(ctx, c, a, r, w);
    // Only the annulus the ring covers is filled.
    const outer = r + w * 0.7;
    ctx.fillRect(Math.max(0, o.x - outer), Math.max(0, o.y - outer), Math.min(this.W, o.x + outer) - Math.max(0, o.x - outer), Math.min(this.H, o.y + outer) - Math.max(0, o.y - outer));
    // The flash where it starts.
    const f = Math.max(0, 1 - wave.u / 0.22);
    if (f > 0) {
      const fg = ctx.createRadialGradient(o.x, o.y, this.radius * 0.8, o.x, o.y, this.radius + 70);
      fg.addColorStop(0, rgba(c, 0.5 * f * f * this.wave.strength * vis));
      fg.addColorStop(1, rgba(c, 0));
      ctx.fillStyle = fg;
      ctx.fillRect(o.x - 130, o.y - 130, 260, 260);
    }
    // The emoji pattern glints as the light passes it.
    this.glint(c, Math.min(1, a * 2.2), r, w);

    // Keep the avatar itself clear: its own glass carries the light.
    ctx.globalCompositeOperation = 'destination-out';
    ctx.beginPath();
    ctx.arc(o.x, o.y, this.radius - 0.5, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalCompositeOperation = 'source-over';
  }

  ringGradient(ctx, c, a, r, w) {
    const o = this.origin;
    const outer = r + w * 0.7;
    const g = ctx.createRadialGradient(o.x, o.y, 0, o.x, o.y, outer);
    const at = (x) => Math.max(0, Math.min(1, x / outer));
    const core = lighten(c, 0.5);
    g.addColorStop(at(r - w), rgba(c, 0));
    g.addColorStop(at(r - w * 0.4), rgba(c, a * 0.3));
    g.addColorStop(at(r), rgba(core, a));
    g.addColorStop(at(r + w * 0.25), rgba(c, a * 0.35));
    g.addColorStop(1, rgba(c, 0));
    return g;
  }

  glint(c, a, r, w) {
    const pr = this.cover?.patternRect;
    const mask = this.cover?.mask;
    if (!pr || !mask || !mask.width) return;
    // Nothing to light once the ring has passed the pattern.
    const o = this.origin;
    const near = Math.hypot(Math.max(Math.abs(pr.x - o.x), Math.abs(pr.x + pr.w - o.x)), Math.max(Math.abs(pr.y - o.y), Math.abs(pr.y + pr.h - o.y)));
    if (r - w > near) return;
    const s = this.scale;
    const t = this.temp;
    const tw = Math.round(pr.w * s);
    const th = Math.round(pr.h * s);
    if (t.width !== tw || t.height !== th) { t.width = tw; t.height = th; }
    const tc = t.getContext('2d');
    tc.setTransform(1, 0, 0, 1, 0, 0);
    tc.globalCompositeOperation = 'source-over';
    tc.clearRect(0, 0, tw, th);
    tc.setTransform(s, 0, 0, s, -pr.x * s, -pr.y * s);
    tc.fillStyle = this.ringGradient(tc, lighten(c, 0.5), a, r, w * 0.8);
    tc.fillRect(pr.x, pr.y, pr.w, pr.h);
    tc.setTransform(1, 0, 0, 1, 0, 0);
    tc.globalCompositeOperation = 'destination-in';
    tc.drawImage(mask, 0, 0, tw, th);
    tc.globalCompositeOperation = 'source-over';
    this.ctx.drawImage(t, pr.x, pr.y, pr.w, pr.h);
  }

  // Glass rims facing the avatar take its light: a faint constant spill from the glow, and a
  // bright pass when the wave crosses them. Each glass element gets a rim-light layer whose
  // colour is set once per colour change; per frame only its opacity changes (compositor
  // only — repainting the blurred glass itself every frame stutters on phones).
  spillLayer(el) {
    let layer = this.spillLayers.get(el);
    if (!layer) {
      layer = document.createElement('div');
      layer.style.cssText = 'position:absolute;inset:0;border-radius:inherit;pointer-events:none;opacity:0;will-change:opacity;z-index:3';
      el.appendChild(layer);
      this.spillLayers.set(el, layer);
    }
    return layer;
  }

  spill(wave) {
    const o = this.origin;
    for (const el of this.glassEls) {
      if (!el.isConnected) continue;
      // Glass elements don't move (sheets slide with a transform): measured once.
      let geo = this.geo.get(el);
      if (!geo) {
        geo = { cx: el.offsetLeft + el.offsetWidth / 2, cy: el.offsetTop + el.offsetHeight / 2, size: Math.max(el.offsetWidth, el.offsetHeight) };
        this.geo.set(el, geo);
      }
      const { cx, cy } = geo;
      const d = Math.hypot(cx - o.x, cy - o.y);
      const nx = (o.x - cx) / Math.max(1, d);
      const ny = (o.y - cy) / Math.max(1, d);
      const rest = this.tint * (0.55 + 0.35 * this.lift) * Math.exp(-Math.pow(Math.max(0, d - 60) / 150, 2));
      let pass = 0;
      let color = this.color;
      if (wave && wave.intensity > 0) {
        const edge = d - geo.size * 0.3;
        pass = wave.intensity * Math.exp(-Math.pow((edge - wave.r) / (wave.w * 0.6), 2)) * this.wave.strength;
        color = this.wave.color;
      }
      const a = Math.min(0.95, (rest + pass * 1.2) * this.visibility);
      const layer = this.spillLayer(el);
      const key = `${color.map((v) => v.toFixed(3)).join(',')}|${nx.toFixed(2)},${ny.toFixed(2)}`;
      if (layer.dataset.key !== key) {
        layer.dataset.key = key;
        layer.style.boxShadow = `inset ${(-nx * 5).toFixed(2)}px ${(-ny * 5).toFixed(2)}px 10px -3px ${rgba(lighten(color, 0.25), 1)}`;
      }
      const opacity = a < 0.01 ? '0' : a.toFixed(3);
      if (layer.style.opacity !== opacity) layer.style.opacity = opacity;
    }
  }
}
