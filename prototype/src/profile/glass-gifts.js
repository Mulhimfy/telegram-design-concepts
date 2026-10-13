// Glass Gifts: what is new. The gift tiles on a profile are flat squares that do nothing until
// tapped. Here each one is a pane of glass with the gift floating inside it:
//   · touch a tile and it leans toward your finger, lifts a hair (×1.01) and a burst of light
//     fragments runs across the glass while sparkles catch at its corners;
//   · press, hold and slide over the grid: every tile you cross leans after the finger;
//   · tilt the phone and the light moves across all of them — a specular sheen, a faint prismatic
//     streak and the lit edge slide over the glass — with only a hint of lean (≤ 2.5°);
//   · nothing ever turns far: the lean is ≤ 9° yaw / 7° pitch and eases home when you let go.
// The motion is Telegram's own TON wallet card, the one glassy card in the app that tilts
// (WalletCardComponent: angles follow their targets with 1 − e^(−8 dt), scale with 1 − e^(−12 dt),
// targets decay e^(−4 dt) after release; device motion moves the light, not the card; m34 −1/650).

const clamp = (x, a = 0, b = 1) => Math.max(a, Math.min(b, x));

export const GiftLook = {
  maxYaw: 9,         // deg (the wallet card: 17.2 on a 361 pt card; a 120 pt tile wants less)
  maxPitch: 7,       // deg (wallet: 11.5)
  motionLean: 2.5,   // deg of lean from the phone's tilt
  held: 1.01,        // scale while touched (wallet)
  depth: { gift: 14, ribbon: 18, badge: 10 },   // pt above the glass
  perspective: 650,  // m34 = −1/650
};

export class GlassTile {
  // el: the tile; parts: { gift, ribbon, badges[], sheen, holo, rim, shadow, shards[], sparkles[] }
  constructor(el, parts) {
    this.el = el;
    this.parts = parts;
    this.yaw = 0;
    this.pitch = 0;
    this.scale = 1;
    this.target = { yaw: 0, pitch: 0, scale: 1 };
    this.touching = false;
    this.burstT0 = null;
    this.last = '';
  }

  // Finger at (u, v) in the tile, −1…1 each way (0, 0 = centre).
  aim(u, v) {
    this.touching = true;
    this.target = { yaw: clamp(u, -1, 1) * GiftLook.maxYaw, pitch: -clamp(v, -1, 1) * GiftLook.maxPitch, scale: GiftLook.held };
  }

  release() {
    this.touching = false;
    this.target.scale = 1;
  }

  burst(now) {
    this.burstT0 = now;
  }

  // dt: frame time; light: { x, y } the phone's tilt in degrees (shared). Returns true while moving.
  update(now, dt, light) {
    const T = this.target;
    if (!this.touching) {
      const k = Math.exp(-4 * dt);   // the pan offset decays after release
      T.yaw *= k;
      T.pitch *= k;
    }
    const a = 1 - Math.exp(-8 * dt);
    const b = 1 - Math.exp(-12 * dt);
    this.yaw += (T.yaw - this.yaw) * a;
    this.pitch += (T.pitch - this.pitch) * a;
    this.scale += (T.scale - this.scale) * b;
    const lx = light ? light.x : 0;
    const ly = light ? light.y : 0;
    const yaw = this.yaw + clamp(lx / 20, -1, 1) * GiftLook.motionLean;
    const pitch = this.pitch - clamp(ly / 20, -1, 1) * GiftLook.motionLean;
    const moving = Math.abs(T.yaw - this.yaw) > 0.01 || Math.abs(T.pitch - this.pitch) > 0.01 || Math.abs(T.scale - this.scale) > 1e-4
      || Math.abs(T.yaw) > 0.01 || Math.abs(T.pitch) > 0.01;
    const P = this.parts;
    // The wallet's transform: a small translate with the angles, scale, X / Y rotation and a
    // touch of Z (yaw · 0.05).
    const t = `perspective(${GiftLook.perspective}px) translate(${(-yaw * 0.06).toFixed(2)}px,${(pitch * 0.05).toFixed(2)}px) scale(${this.scale.toFixed(4)}) rotateX(${pitch.toFixed(2)}deg) rotateY(${yaw.toFixed(2)}deg) rotateZ(${(yaw * 0.05).toFixed(3)}deg)`;
    if (t !== this.last) {
      this.last = t;
      this.el.style.transform = t;
      // Light: the tile's lean plus the phone's tilt (×0.9 for the surface), in degrees.
      const sx = yaw + lx * 0.9;
      const sy = pitch - ly * 0.9;
      const tilt = Math.min(1, Math.hypot(sx, sy) / 12);
      if (P.sheen) {
        P.sheen.style.transform = `translate(${clamp(sx * 2.2, -40, 40).toFixed(1)}%, ${clamp(-sy * 2.2, -40, 40).toFixed(1)}%)`;
        P.sheen.style.opacity = (0.3 + 0.7 * tilt).toFixed(3);
      }
      if (P.holo) {
        P.holo.style.backgroundPosition = `${(50 + sx * 5).toFixed(1)}% ${(50 - sy * 5).toFixed(1)}%`;
        P.holo.style.opacity = (0.06 + 0.3 * tilt).toFixed(3);
      }
      if (P.rim) P.rim.style.setProperty('--rim-angle', `${(135 + sx * 6 - sy * 6).toFixed(1)}deg`);
      const D = GiftLook.depth;
      if (P.gift) P.gift.style.transform = `translateZ(${D.gift}px) translate(${(yaw * 0.22).toFixed(2)}px, ${(-pitch * 0.22).toFixed(2)}px)`;
      if (P.ribbon) P.ribbon.style.transform = `translateZ(${D.ribbon}px)`;
      for (const bd of P.badges || []) bd.style.transform = `translateZ(${D.badge}px)`;
      if (P.shadow) {
        P.shadow.style.transform = `translate(${(-yaw * 0.45).toFixed(2)}px, ${(pitch * 0.45 + 2).toFixed(2)}px) scale(${(0.96 + (this.scale - 1) * 2).toFixed(3)})`;
        P.shadow.style.opacity = (0.32 + 0.4 * Math.min(1, Math.hypot(yaw, pitch) / 9)).toFixed(3);
      }
    }
    // Light fragments: shards across the glass, sparkles at its corners.
    let bursting = false;
    if (this.burstT0 != null && P.shards) {
      const u = (now - this.burstT0) / 0.55;
      P.shards.forEach((sh, i) => {
        const v = clamp(u * 1.25 - i * 0.12);
        sh.style.opacity = (v > 0 && v < 1 ? Math.sin(Math.PI * v) * 0.8 : 0).toFixed(3);
        sh.style.transform = `translateX(${(-130 + 260 * v).toFixed(1)}%) rotate(${(-28 + i * 7)}deg)`;
      });
      P.sparkles?.forEach((sp, i) => {
        const v = clamp(u * 1.4 - 0.15 - i * 0.08);
        const k = v > 0 && v < 1 ? Math.sin(Math.PI * v) : 0;
        sp.style.opacity = k.toFixed(3);
        sp.style.transform = `scale(${(0.3 + k).toFixed(3)}) rotate(${(v * 120).toFixed(0)}deg)`;
      });
      if (u >= 1.3) this.burstT0 = null;
      bursting = true;
    }
    return moving || bursting;
  }
}

// Phone tilt, as the wallet card reads it: the first reading is the reference, smoothed over 0.1 s,
// slowly re-centred so a held pose turns neutral. Telegram's Mini App DeviceOrientation where there
// is one (no prompt), else the browser's (iOS asks on a tap). In degrees, ±20 → full effect.
export class MotionSource {
  constructor(tg) {
    this.tg = tg;
    this.value = { x: 0, y: 0 };
    this.base = null;
    this.abs = null;
    this.started = false;
  }

  start() {
    if (this.started) return;
    const feed = (beta, gamma) => {
      if (beta == null || gamma == null) return;
      this.abs = { beta, gamma };
      if (!this.base) this.base = { beta, gamma };
    };
    const DO = this.tg?.DeviceOrientation;
    if (DO && this.tg.isVersionAtLeast?.('8.0')) {
      try {
        this.started = true;
        this.tg.onEvent('deviceOrientationChanged', () => feed(DO.beta * (180 / Math.PI), DO.gamma * (180 / Math.PI)));
        DO.start({ refresh_rate: 30 });
        return;
      } catch (_) {}
    }
    const listen = () => {
      if (this.listening) return;
      this.listening = true;
      window.addEventListener('deviceorientation', (e) => feed(e.beta, e.gamma));
    };
    if (typeof DeviceOrientationEvent !== 'undefined' && typeof DeviceOrientationEvent.requestPermission === 'function') {
      DeviceOrientationEvent.requestPermission().then((s) => { this.started = true; if (s === 'granted') listen(); }).catch(() => {});
    } else {
      this.started = true;
      listen();
    }
  }

  stop() {
    try { this.tg?.DeviceOrientation?.stop?.(); } catch (_) {}
  }

  // Scripted tilt (demo videos): { x, y } in degrees, or null to go back to the sensors.
  set(value) {
    this.override = value ? { x: value.x, y: value.y } : null;
  }

  update(dt) {
    if (this.override) return this.override;
    if (!this.abs || !this.base) return null;
    const d = 1 - Math.exp(-dt / 4);   // re-centre over ~4 s
    this.base.beta += (this.abs.beta - this.base.beta) * d;
    this.base.gamma += (this.abs.gamma - this.base.gamma) * d;
    const k = 1 - Math.exp(-dt / 0.1);
    this.value.x += (clamp(this.abs.gamma - this.base.gamma, -20, 20) - this.value.x) * k;
    this.value.y += (clamp(this.abs.beta - this.base.beta, -20, 20) - this.value.y) * k;
    return this.value;
  }
}
