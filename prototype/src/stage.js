// Video composition, matching the Telegram designer demo (research/video/analysis.md §5):
// 1080×1080 canvas, phone screen 402 pt wide at 1.727 px/pt (x 193–886, top y 97),
// bottom of the phone cropped, backdrop = darkened huge blur of the screen colours,
// camera zooms 1.0 → 1.64× with ease-in-out over ~1 s, touch indicator Ø 32 pt.

const BASE_PX_PER_PT = 1.727;

export class Stage {
  constructor(stageEl, deviceEl, screenEl, device, { width = 1080, height = 1080 } = {}) {
    this.stageEl = stageEl;
    this.deviceEl = deviceEl;
    this.screenEl = screenEl;
    this.device = device;
    this.width = width;
    this.height = height;
    stageEl.style.cssText = `position:fixed;left:0;top:0;width:${width}px;height:${height}px;overflow:hidden;display:block;background:#000`;
    document.body.classList.add('recording');

    this.backdrop = document.createElement('canvas');
    this.backdrop.width = 64;
    this.backdrop.height = 64;
    // A 24×24 copy scaled to the whole stage is already a huge, smooth blur; brightness and
    // saturation are baked into its pixels (CSS filters here cost seconds per frame in software).
    this.backdrop.width = 24;
    this.backdrop.height = 24;
    this.backdrop.style.cssText = `position:absolute;left:-12%;top:-12%;width:124%;height:124%;image-rendering:auto`;
    stageEl.insertBefore(this.backdrop, deviceEl);
    this.vignette = document.createElement('div');
    this.vignette.style.cssText = 'position:absolute;inset:0;background:radial-gradient(ellipse at 50% 38%, rgba(0,0,0,0) 35%, rgba(0,0,0,0.38) 100%)';
    stageEl.insertBefore(this.vignette, deviceEl);

    deviceEl.style.position = 'absolute';
    deviceEl.style.left = '0';
    deviceEl.style.top = '0';
    deviceEl.style.transformOrigin = '0 0';
    this.frame = buildDeviceFrame(device);
    deviceEl.appendChild(this.frame);
    screenEl.style.borderRadius = `${device.corner}px`;

    this.touch = document.createElement('div');
    this.touch.className = 'touch-indicator';
    screenEl.appendChild(this.touch);

    this.camera = { zoom: 1, focus: [device.width / 2, 0], anchor: [width / 2, 97] };
    this.anim = null;

    // Captions under the phone and the slow-motion badge (demo videos; video time).
    this.captions = [];
    this.slow = document.createElement('div');
    this.slow.className = 'stage-slow';
    this.slow.style.opacity = '0';
    stageEl.appendChild(this.slow);
    this.slowState = { to: 1, t0: -1, from: 0 };
    // The corner label of a demo: "Before · Telegram today" / "After · <design>".
    this.tag = document.createElement('div');
    this.tag.className = 'stage-tag';
    this.tag.style.opacity = '0';
    stageEl.appendChild(this.tag);
    this.tagT0 = null;
    this.apply();
  }

  setTag(html, vt) {
    this.tag.innerHTML = html || '';
    this.tag.classList.toggle('before', /before/i.test(html || ''));
    this.tagT0 = html ? vt : null;
  }

  // A caption (null: none). The old one fades out as the new one fades in (0.3 s).
  setCaption(text, vt) {
    for (const c of this.captions) if (!c.out) { c.out = vt; }
    if (text) {
      const el = document.createElement('div');
      el.className = 'stage-caption';
      el.innerHTML = `<span>${text}</span>`;
      el.style.opacity = '0';
      this.stageEl.appendChild(el);
      this.captions.push({ el, t0: vt, out: null });
    }
  }

  // The badge while the page runs slower than the video: "0.25× slow motion".
  setSlow(rate, vt) {
    const S = this.slowState;
    const on = rate < 0.99;
    if (on !== (S.to < 0.99) || (on && Math.abs(rate - S.to) > 1e-6)) {
      S.from = parseFloat(this.slow.style.opacity || '0');
      S.t0 = vt;
      if (on) this.slow.innerHTML = `<span class="stage-slow-dot"></span>${+rate.toFixed(2)}× slow motion`;
    }
    S.to = rate;
  }

  updateOverlays(vt) {
    const fade = 0.3;
    this.captions = this.captions.filter((c) => {
      const a = Math.min(1, (vt - c.t0) / fade) * (c.out == null ? 1 : Math.max(0, 1 - (vt - c.out) / fade));
      const e = a * a * (3 - 2 * a);
      c.el.style.opacity = e.toFixed(3);
      c.el.style.transform = `translate(-50%, ${((1 - e) * (c.out == null ? 10 : -6)).toFixed(1)}px)`;
      if (c.out != null && vt - c.out >= fade) { c.el.remove(); return false; }
      return true;
    });
    if (this.tagT0 != null) this.tag.style.opacity = Math.min(1, (vt - this.tagT0) / 0.4).toFixed(3);
    const S = this.slowState;
    const target = S.to < 0.99 ? 1 : 0;
    const u = S.t0 < 0 ? 1 : Math.min(1, (vt - S.t0) / 0.25);
    this.slow.style.opacity = (S.from + (target - S.from) * u).toFixed(3);
  }

  // Backdrop colours from any canvas (the profile cover): a tiny copy, blurred by CSS.
  setBackdropSource(canvas) {
    const n = 24;
    const ctx = this.backdrop.getContext('2d', { willReadFrequently: true });
    ctx.drawImage(canvas, 0, 0, n, n);
    // Box blur ×3 (≈ Gaussian), then darken (×0.62) and saturate (×1.15) like the designer's backdrop.
    let img = ctx.getImageData(0, 0, n, n);
    const blur = (src) => {
      const out = new Uint8ClampedArray(src.length);
      for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) {
        let r = 0, g = 0, b = 0, c = 0;
        for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) {
          const xx = Math.min(n - 1, Math.max(0, x + dx));
          const yy = Math.min(n - 1, Math.max(0, y + dy));
          const i = (yy * n + xx) * 4;
          r += src[i]; g += src[i + 1]; b += src[i + 2]; c++;
        }
        const o = (y * n + x) * 4;
        out[o] = r / c; out[o + 1] = g / c; out[o + 2] = b / c; out[o + 3] = 255;
      }
      return out;
    };
    let d = img.data;
    for (let k = 0; k < 3; k++) d = blur(d);
    for (let i = 0; i < d.length; i += 4) {
      const l = 0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2];
      for (let ch = 0; ch < 3; ch++) d[i + ch] = Math.max(0, Math.min(255, (l + (d[i + ch] - l) * 1.15) * 0.62));
    }
    img.data.set(d);
    ctx.putImageData(img, 0, 0);
  }

  cameraTo(target, now, duration = 1.0) {
    this.anim = { from: { ...this.current(now) }, to: { ...this.camera, ...target }, t0: now, duration };
  }

  current(now) {
    if (!this.anim) return this.camera;
    const { from, to, t0, duration } = this.anim;
    const u = Math.max(0, Math.min(1, (now - t0) / duration));
    const e = u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2; // ease-in-out cubic
    const lerp = (a, b) => a + (b - a) * e;
    const ft = from.tilt || [0, 0];
    const tt = to.tilt || [0, 0];
    const cam = {
      zoom: lerp(from.zoom, to.zoom),
      focus: [lerp(from.focus[0], to.focus[0]), lerp(from.focus[1], to.focus[1])],
      anchor: [lerp(from.anchor[0], to.anchor[0]), lerp(from.anchor[1], to.anchor[1])],
      tilt: [lerp(ft[0], tt[0]), lerp(ft[1], tt[1])],
    };
    if (u >= 1) {
      this.camera = { ...to };
      this.anim = null;
    }
    return cam;
  }

  get pxPerPt() { return BASE_PX_PER_PT * this.currentCam.zoom; }

  // now: video time (camera moves and captions keep the video's pace in slow motion).
  apply(now = 0) {
    this.updateOverlays(now);
    const cam = this.current(now);
    this.currentCam = cam;
    const s = BASE_PX_PER_PT * cam.zoom;
    const tx = cam.anchor[0] - cam.focus[0] * s;
    const ty = cam.anchor[1] - cam.focus[1] * s;
    // The phone itself can tilt (a demo of the gyroscope): about the point in focus.
    const [rx, ry] = cam.tilt || [0, 0];
    const tilt = Math.abs(rx) + Math.abs(ry) > 1e-3
      ? ` translate(${cam.focus[0]}px, ${cam.focus[1]}px) perspective(1600px) rotateX(${rx.toFixed(3)}deg) rotateY(${ry.toFixed(3)}deg) translate(${-cam.focus[0]}px, ${-cam.focus[1]}px)`
      : '';
    this.deviceEl.style.transform = `translate(${tx}px, ${ty}px) scale(${s})${tilt}`;
  }

  showTouch(p, visible, pressed) {
    const t = this.touch;
    if (p) {
      t.style.left = `${p[0]}px`;
      t.style.top = `${p[1]}px`;
    }
    t.style.opacity = visible ? '1' : '0';
    t.style.transform = `scale(${pressed ? 1 : 0.86})`;
  }
}

export function buildDeviceFrame(device) {
  // A titanium iPhone 16 Pro-like bezel drawn in CSS around the screen (pt units).
  const bezel = 7.6;          // 13 px at 1.727 px/pt (black glass border)
  const frame = 4.6;          // titanium band (8 px)
  const r = device.corner + bezel;
  const el = document.createElement('div');
  el.className = 'device-frame';
  el.style.cssText = `left:${-bezel - frame}px;top:${-bezel - frame}px;width:${device.width + 2 * (bezel + frame)}px;height:${device.height + 2 * (bezel + frame)}px;border-radius:${r + frame}px;`
    + `background:linear-gradient(160deg,#e9eaee 0%,#a9abb1 16%,#d6d8dc 34%,#8d9096 58%,#c5c7cc 80%,#7d8086 100%);`
    + `box-shadow:0 18px 40px rgba(0,0,0,0.45), inset 0 0 0 0.7px rgba(255,255,255,0.55), inset 0 0 1.5px 1.2px rgba(0,0,0,0.25);`;
  const inner = document.createElement('div');
  inner.style.cssText = `position:absolute;left:${frame}px;top:${frame}px;right:${frame}px;bottom:${frame}px;border-radius:${r}px;background:#050505;box-shadow:inset 0 0 0 1px rgba(255,255,255,0.06)`;
  el.appendChild(inner);
  // side buttons
  const btn = (side, top, h) => {
    const b = document.createElement('div');
    b.style.cssText = `position:absolute;${side}:-2.2px;top:${top}px;width:3.2px;height:${h}px;border-radius:2px;background:linear-gradient(90deg,#8f9298,#d9dbdf,#8a8d93)`;
    el.appendChild(b);
  };
  btn('left', 118, 30);    // action button
  btn('left', 170, 58);    // volume up
  btn('left', 240, 58);    // volume down
  btn('right', 200, 92);   // side button
  btn('right', 360, 44);   // camera control
  // The frame sits behind the screen: z-index below the screen element.
  el.style.zIndex = '-1';
  if (device.island) {
    const island = document.createElement('div');
    island.className = 'dynamic-island';
    island.style.cssText = `position:absolute;left:${bezel + frame + (device.width - 126) / 2}px;top:${bezel + frame + 11}px;width:126px;height:37.33px;border-radius:19px;background:#000;z-index:60`;
    el.appendChild(island);
    // The island must draw above the screen content: move it to a sibling later.
    el._island = island;
  }
  return el;
}

export function easeInOutCubic(u) {
  return u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2;
}
