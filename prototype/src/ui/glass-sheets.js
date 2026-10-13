// The two new sheets: the glass colour (a row of glass beads, like Telegram's colour
// pickers) and the back photo (a photo grid, like Telegram's media picker).

import { Sheet } from './sheet.js';

function el(tag, cls, style, parent, html) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (style) e.style.cssText = style;
  if (html !== undefined) e.innerHTML = html;
  if (parent) parent.appendChild(e);
  return e;
}

export const GLASS_COLORS = [
  { name: 'Clear', hex: null },
  { name: 'Gold', hex: '#f5b03c' },
  { name: 'Rose', hex: '#f0549c' },
  { name: 'Violet', hex: '#7d62f4' },
  { name: 'Blue', hex: '#3e8bff' },
  { name: 'Aqua', hex: '#2fd3c4' },
  { name: 'Green', hex: '#48d16a' },
  { name: 'Ember', hex: '#ff6a3d' },
];

export const hexToRgb = (hex) => (hex ? [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255) : null);

function beadBackground(hex) {
  if (!hex) {
    return 'radial-gradient(circle at 34% 28%, rgba(255,255,255,0.75) 0, rgba(255,255,255,0) 34%),'
      + 'radial-gradient(circle at 50% 62%, rgba(255,255,255,0.06) 0, rgba(255,255,255,0.16) 100%)';
  }
  return 'radial-gradient(circle at 34% 28%, rgba(255,255,255,0.8) 0, rgba(255,255,255,0) 32%),'
    + `radial-gradient(circle at 50% 58%, ${hex} 0, ${hex} 48%, color-mix(in srgb, ${hex} 70%, #000) 100%)`;
}

export function glassColorSheet(screen, { device, current = 0, onPick }) {
  let selected = current;
  const swatches = [];
  const sheet = new Sheet(screen, {
    device,
    title: 'Glass Color',
    subtitle: 'Glows when your photo turns to glass.',
    height: 196,
    dim: false,
    build: (body, { width }) => {
      const n = GLASS_COLORS.length;
      const size = 38;
      const pad = 18;
      const gap = (width - pad * 2 - n * size) / (n - 1);
      return GLASS_COLORS.map((c, i) => {
        const x = pad + i * (size + gap);
        const y = 16;
        const sw = el('div', 'swatch', `left:${x}px;top:${y}px;width:${size}px;height:${size}px`, body);
        const ring = el('div', 'ring', `--swatch-ring:${c.hex || 'rgba(255,255,255,0.85)'}`, sw);
        el('div', 'bead', `background:${beadBackground(c.hex)};box-shadow:inset 0 0 0 0.8px rgba(255,255,255,${c.hex ? 0.35 : 0.5}),inset 0 -5px 9px rgba(0,0,0,${c.hex ? 0.22 : 0.08}),0 2px 6px rgba(0,0,0,0.18)`, sw);
        el('div', 'swatch-label', `left:${x - 10}px;top:${y + size + 9}px;width:${size + 20}px`, body, c.name);
        swatches.push(ring);
        return {
          x: x - 6, y: y - 6, w: size + 12, h: size + 30,
          onTap: (now) => {
            if (i === selected) return;
            selected = i;
            swatches.forEach((r, j) => { r.style.opacity = j === i ? '1' : '0'; });
            onPick?.(i, now);
          },
        };
      });
    },
  });
  swatches.forEach((r, j) => { r.style.opacity = j === selected ? '1' : '0'; });
  return sheet;
}

export function backPhotoSheet(screen, { device, photos, onPick }) {
  // Cell 0 is "None": no separate back, the photo itself on both sides (the default).
  const checks = [];
  const pad = 8;
  const gap = 2;
  const width = device.width - 16;
  const cell = (width - pad * 2 - gap * 2) / 3;
  const count = photos.length + 1;
  const rows = Math.ceil(count / 3);
  const gridH = rows * cell + (rows - 1) * gap;
  const noneIcon = '<svg viewBox="0 0 40 40" width="40" height="40"><circle cx="20" cy="20" r="14" fill="none" stroke="currentColor" stroke-width="2.4"/>'
    + '<path d="M10.5 29.5 L29.5 10.5" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"/></svg>';
  const sheet = new Sheet(screen, {
    device,
    title: 'Back Photo',
    subtitle: 'Shown when your photo is turned over.',
    height: 76 + gridH + pad + 2,
    build: (body) => {
      const grid = el('div', 'abs', `left:${pad}px;top:0;width:${width - pad * 2}px;height:${gridH}px;border-radius:30px;overflow:hidden`, body);
      const items = [];
      for (let i = 0; i < count; i++) {
        const x = (i % 3) * (cell + gap);
        const y = Math.floor(i / 3) * (cell + gap);
        const pick = el('div', 'pick', `left:${x}px;top:${y}px;width:${cell}px;height:${cell}px`, grid);
        if (i === 0) {
          pick.classList.add('none');
          el('div', 'none-icon', '', pick, noneIcon);
          el('div', 'none-label', '', pick, 'None');
        } else {
          const img = el('img', '', '', pick);
          img.src = photos[i - 1];
          img.draggable = false;
        }
        checks.push(el('div', 'check', '', pick));
        items.push({
          x: pad + x, y, w: cell, h: cell,
          onTap: (now) => {
            sheet.select(i);
            onPick?.(i, now);
          },
        });
      }
      return items;
    },
  });
  sheet.select = (i) => checks.forEach((c, j) => c.classList.toggle('on', j === i));
  return sheet;
}
