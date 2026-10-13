// Telegram's animated action icons (submodules/TelegramUI/Resources/Animations/anim_*.json),
// played like SimpleAnimationNode(playOnce: true): reset to the start frame, play once to the
// end, hold the last frame. Colours listed in `replaceColors` are recoloured to the option's
// fill (ItemListRevealOptionNode: the "cut" strokes of mute / unpin take the circle's colour).
// Rendered by lottie-web (prototype/vendor/lottie_light.min.js, SVG renderer).

const cache = new Map();

function loadScript(src) {
  return new Promise((resolve, reject) => {
    if (window.lottie) { resolve(window.lottie); return; }
    const s = document.createElement('script');
    s.src = src;
    s.onload = () => resolve(window.lottie);
    s.onerror = reject;
    document.head.appendChild(s);
  });
}

let lottieReady = null;
export function lottie() {
  lottieReady ||= loadScript(new URL('../../vendor/lottie_light.min.js', import.meta.url).href);
  return lottieReady;
}

// name: one of assets/lottie/*.json, or a full URL (gift stickers live in assets/gifts).
export function loadAnimation(name) {
  if (!cache.has(name)) {
    const url = /^(https?:|blob:|\/)/.test(name) ? name : new URL(`../../assets/lottie/${name}.json`, import.meta.url).href;
    cache.set(name, fetch(url).then((r) => r.json()));
  }
  return cache.get(name);
}

// Every fill / stroke recoloured (single-colour artwork, e.g. the gift box glyph).
function tintAll(data, to) {
  const walk = (o) => {
    if (Array.isArray(o)) { o.forEach(walk); return; }
    if (!o || typeof o !== 'object') return;
    if ((o.ty === 'fl' || o.ty === 'st') && o.c && Array.isArray(o.c.k) && typeof o.c.k[0] === 'number') o.c.k = [to[0], to[1], to[2], 1];
    for (const v of Object.values(o)) if (v && typeof v === 'object') walk(v);
  };
  walk(data);
  return data;
}

const toKey = (c) => ((Math.round(c[0] * 255) << 16) | (Math.round(c[1] * 255) << 8) | Math.round(c[2] * 255)) >>> 0;

// Deep copy with fills / strokes of the listed colours (0xRRGGBB) set to `to` (rgb 0…1).
function recolor(data, replace, to) {
  const copy = JSON.parse(JSON.stringify(data));
  if (!replace || !replace.length) return copy;
  const keys = new Set(replace);
  const walk = (o) => {
    if (Array.isArray(o)) { o.forEach(walk); return; }
    if (!o || typeof o !== 'object') return;
    if ((o.ty === 'fl' || o.ty === 'st') && o.c && Array.isArray(o.c.k) && typeof o.c.k[0] === 'number') {
      if (keys.has(toKey(o.c.k))) o.c.k = [to[0], to[1], to[2], 1];
    }
    for (const v of Object.values(o)) if (v && typeof v === 'object') walk(v);
  };
  walk(copy);
  return copy;
}

export class LottieIcon {
  // el: container (sized by the caller). opts: { name, replaceColors, color (rgb 0…1), flip, startFrame }
  // Driven by the page clock (update(now) each frame while playing), so a recording on the
  // virtual clock shows the same frames as a phone.
  // maxFps: draws at most this often while playing (heavy artwork on a phone); tint: recolour all.
  constructor(el, { name, replaceColors = null, color = [1, 1, 1], flip = false, startFrame = 0, maxFps = 60, tint = null, onReady = null }) {
    this.el = el;
    this.startFrame = startFrame;
    this.anim = null;
    this.t0 = null;          // clock time play() was called; null = held
    this.frame = startFrame;
    this.step = 60 / Math.max(1, maxFps);
    if (flip) el.style.transform = 'scaleY(-1)';
    Promise.all([lottie(), loadAnimation(name)]).then(([L, data]) => {
      this.fr = data.fr || 60;
      let d = recolor(data, replaceColors, color);
      if (tint) d = tintAll(d, tint);
      this.anim = L.loadAnimation({
        container: el,
        renderer: 'svg',
        loop: false,
        autoplay: false,
        animationData: d,
        rendererSettings: { preserveAspectRatio: 'xMidYMid meet', progressiveLoad: false },
      });
      this.total = this.anim.totalFrames;
      this.shown = undefined;
      this.show(this.frame);
      onReady?.(this);
    }).catch(() => {});
  }

  show(frame) {
    const last = (this.total || 1e9) - 1;
    const f = frame >= last ? last : Math.min(Math.floor(frame / this.step) * this.step, last);
    if (this.anim && f === this.shown) return;
    this.frame = frame;
    this.shown = f;
    if (this.anim) this.anim.goToAndStop(f, true);
  }

  get playing() { return this.t0 !== null; }

  play(now) {
    this.t0 = now;
    this.show(this.startFrame);
  }

  reset() {
    this.t0 = null;
    this.show(this.startFrame);
  }

  seekToEnd() {
    this.t0 = null;
    if (!this.total) return;
    this.shown = undefined;
    this.show(this.total - 1);
  }

  // Advances a playing icon; returns true while it still has frames to show.
  update(now) {
    if (this.t0 === null || !this.anim) return this.t0 !== null;
    const f = this.startFrame + (now - this.t0) * this.fr;
    if (f >= this.total - 1) {
      this.t0 = null;
      this.show(this.total - 1);
      return false;
    }
    this.show(f);
    return true;
  }

  destroy() {
    this.anim?.destroy();
  }
}
