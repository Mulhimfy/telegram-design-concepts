// Faces. Photos are square images; the reverse of a profile without a back photo is the
// "emblem": the profile colour and its background emoji, drawn like the profile cover.

import { patternItems } from '../ui/cover.js';

export function emblemCanvas({ size = 600, main, secondary, glyph, dark = true }) {
  const c = document.createElement('canvas');
  c.width = size;
  c.height = size;
  const ctx = c.getContext('2d');
  const r = size / 2;
  // Disc: the cover gradient, brighter in the middle (same glow recipe as the cover).
  const g = ctx.createLinearGradient(0, size, 0, 0);
  g.addColorStop(0, main.css());
  g.addColorStop(1, secondary.css());
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, size, size);
  const glow = ctx.createRadialGradient(r, r * 0.92, 0, r, r * 0.92, r * 1.05);
  for (let i = 0; i < 6; i++) {
    const s = 1 - i / 5;
    glow.addColorStop(i / 5, `rgba(255,255,255,${(0.42 * s * s).toFixed(3)})`);
  }
  ctx.fillStyle = glow;
  ctx.fillRect(0, 0, size, size);

  if (glyph) {
    // Mini pattern: the profile's emoji in two rings, overlay-darkened like the cover.
    const k = size / 100; // 1pt of a 100pt avatar
    const mask = document.createElement('canvas');
    mask.width = size;
    mask.height = size;
    const m = mask.getContext('2d');
    patternItems(100, 0).slice(0, 12).forEach((it) => {
      const s = it.size * 0.52 * k;
      const dx = it.dx * 0.6 * k;
      const dy = it.dy * 0.6 * k;
      m.globalAlpha = 0.8;
      m.drawImage(glyph, r + dx - s / 2, r + dy - s / 2, s, s);
    });
    m.globalAlpha = 1;
    m.globalCompositeOperation = 'source-in';
    m.fillStyle = 'rgba(0,0,0,0.42)';
    m.fillRect(0, 0, size, size);
    ctx.save();
    ctx.globalCompositeOperation = 'overlay';
    ctx.drawImage(mask, 0, 0);
    ctx.restore();

    // The emoji itself, flat white like the cover's (no ring, no emboss: a profile
    // picture, not a coin).
    const g2 = size * 0.46;
    ctx.globalAlpha = 0.96;
    ctx.drawImage(glyph, r - g2 / 2, r - g2 / 2, g2, g2);
    ctx.globalAlpha = 1;
  }
  return c;
}
