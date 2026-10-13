// UIColor helpers ported 1:1 from Telegram-iOS submodules/Display/Source/UIKitUtils.swift
// (withMultiplied:246, mixedWith:308, blitOver:352, blendOver:378) so header colours
// are derived exactly the way PeerInfoHeaderNode derives them.

export class Color {
  constructor(r, g, b, a = 1) {
    this.r = r; this.g = g; this.b = b; this.a = a;
  }

  static rgb(hex, alpha = 1) {
    return new Color(((hex >> 16) & 255) / 255, ((hex >> 8) & 255) / 255, (hex & 255) / 255, alpha);
  }

  static hex(str, alpha = 1) {
    return Color.rgb(parseInt(str.replace('#', ''), 16), alpha);
  }

  static white(w, alpha = 1) { return new Color(w, w, w, alpha); }

  // UIColor(hue:saturation:brightness:alpha:)
  static hsb(h, s, v, a = 1) {
    const i = Math.floor(h * 6);
    const f = h * 6 - i;
    const p = v * (1 - s);
    const q = v * (1 - f * s);
    const t = v * (1 - (1 - f) * s);
    const m = ((i % 6) + 6) % 6;
    const [r, g, b] = [[v, t, p], [q, v, p], [p, v, t], [p, q, v], [t, p, v], [v, p, q]][m];
    return new Color(r, g, b, a);
  }

  // UIColor.getHue(_:saturation:brightness:alpha:)
  hsb() {
    const { r, g, b } = this;
    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);
    const d = max - min;
    let h = 0;
    if (d > 0) {
      if (max === r) h = ((g - b) / d) % 6;
      else if (max === g) h = (b - r) / d + 2;
      else h = (r - g) / d + 4;
      h /= 6;
      if (h < 0) h += 1;
    }
    const s = max === 0 ? 0 : d / max;
    return { h, s, v: max, a: this.a };
  }

  withMultiplied(hue, saturation, brightness) {
    const c = this.hsb();
    const clamp = (x) => Math.max(0, Math.min(1, x));
    return Color.hsb(clamp(c.h * hue), clamp(c.s * saturation), clamp(c.v * brightness), c.a);
  }

  mixedWith(other, alpha) {
    const a = Math.min(1, Math.max(0, alpha));
    const o = 1 - a;
    return new Color(this.r * o + other.r * a, this.g * o + other.g * a, this.b * o + other.b * a, this.a * o + other.a * a);
  }

  blitOver(other, alpha) {
    const a = Math.min(1, Math.max(0, alpha));
    const ra = Math.max(0, Math.min(1, a * this.a));
    const o = 1 - ra;
    return new Color(this.r * ra + other.r * o, this.g * ra + other.g * o, this.b * ra + other.b * o, 1);
  }

  blendOver(background) {
    const ch = (base, blend) => (base < 0.5 ? 2 * base * blend : 1 - 2 * (1 - base) * (1 - blend));
    const clamp = (x) => Math.max(0, Math.min(1, x));
    const blended = new Color(clamp(ch(background.r, this.r)), clamp(ch(background.g, this.g)), clamp(ch(background.b, this.b)), this.a);
    return blended.blitOver(background, 1);
  }

  withAlpha(a) { return new Color(this.r, this.g, this.b, a); }
  withMultipliedAlpha(a) { return new Color(this.r, this.g, this.b, this.a * a); }

  css() {
    const c = (x) => Math.round(Math.max(0, Math.min(1, x)) * 255);
    return this.a >= 1 ? `rgb(${c(this.r)}, ${c(this.g)}, ${c(this.b)})` : `rgba(${c(this.r)}, ${c(this.g)}, ${c(this.b)}, ${+this.a.toFixed(4)})`;
  }

  hex() {
    const c = (x) => Math.round(Math.max(0, Math.min(1, x)) * 255).toString(16).padStart(2, '0');
    return `#${c(this.r)}${c(this.g)}${c(this.b)}`;
  }

  vec3() { return [this.r, this.g, this.b]; }
}
