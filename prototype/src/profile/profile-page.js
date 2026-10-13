// Another user's profile (pushed from the chat list) on iOS 26: the coloured cover with its pattern,
// the photo, name and last seen, the glass action buttons, the info card, the glass tab capsule —
// and the Gifts grid (research/telegram-ios/settings-icons-and-gifts.md §B), where the new glass
// tiles live (profile/glass-gifts.js).
//
// The grid as Telegram draws it: 3 columns, gap 10, inset 16, square tiles (W − 52)/3 with corner
// 16; regular gifts on the card colour with the sender's 20 pt avatar at (5, 5); collectibles on a
// radial backdrop with their symbol in rings; the 58 pt corner ribbon ("1 of 10K", "#1234"); the
// sticker floor(88·h/116) pt, played once as the tile comes into view (again when scrolled back).
//
// Touch: a touch leans the glass toward the finger and runs light across it (a tap does nothing
// more); a vertical drag scrolls; press, hold (0.12 s, Telegram's context-gesture threshold) and
// slide, and the tiles under the finger lean after it; a mouse just hovers. The phone's tilt
// moves the light.

import { Cover } from '../ui/cover.js';
import { Color } from '../core/color.js';
import { svgDataURL, loadImage } from '../ui/glyphs.js';
import { Scroller } from '../core/scroller.js';
import { VelocityTracker } from '../core/velocity.js';
import { Haptics } from '../core/haptics.js';
import { chevronLeft } from '../settings/nav.js';
import { GlassTile, MotionSource } from './glass-gifts.js';
import { LottieIcon } from '../chats/lottie-icon.js';
import { AVATAR_GRADIENTS, initials } from '../chats/chat-data.js';

function el(tag, cls, style, parent, html) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (style) e.style.cssText = style;
  if (html !== undefined) e.innerHTML = html;
  if (parent) parent.appendChild(e);
  return e;
}

const giftURL = (name) => new URL(`../../assets/gifts/${name}.json`, import.meta.url).href;
const sparkleGlyph = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><path fill="#fff" d="M32 4c2.6 13.6 14.4 25.4 28 28-13.6 2.6-25.4 14.4-28 28-2.6-13.6-14.4-25.4-28-28C17.6 29.4 29.4 17.6 32 4z"/></svg>';
const SYMBOL = {
  star: 'M12 2.5l2.9 6.1 6.6.8-4.9 4.5 1.3 6.6L12 17.2l-5.9 3.3 1.3-6.6-4.9-4.5 6.6-.8z',
  diamond: 'M6.5 4h11l4 5.5L12 21 2.5 9.5z',
  sparkle: 'M12 2c1 5 4.9 9 10 10-5.1 1-9 5-10 10-1-5-4.9-9-10-10 5.1-1 9-5 10-10z',
};

const ICON = {
  message: '<svg viewBox="0 0 28 28" width="28" height="28"><path d="M14 5c5.5 0 9.5 3.6 9.5 8s-4 8-9.5 8c-1.2 0-2.3-.2-3.4-.5-1.3 1-3 1.8-5.1 2 .9-1 1.4-2.1 1.6-3.3C5.6 17.7 4.5 15.6 4.5 13c0-4.4 4-8 9.5-8z" fill="currentColor"/></svg>',
  mute: '<svg viewBox="0 0 28 28" width="28" height="28"><path d="M14 4.5c3.6 0 6.2 2.7 6.2 6.3v3.4c0 1 .4 2 1.1 2.8l.8.9c.6.7.1 1.8-.8 1.8H6.7c-.9 0-1.4-1.1-.8-1.8l.8-.9c.7-.8 1.1-1.8 1.1-2.8v-3.4c0-3.6 2.6-6.3 6.2-6.3zM11.4 21.2h5.2a2.6 2.6 0 0 1-5.2 0z" fill="currentColor"/></svg>',
  call: '<svg viewBox="0 0 28 28" width="28" height="28"><path d="M9.7 5.6c.6-.1 1.2.2 1.5.7l1.6 2.7c.4.7.3 1.6-.2 2.2l-1.1 1.3c.8 1.8 2.2 3.3 4 4.1l1.3-1.1c.6-.5 1.5-.6 2.2-.2l2.7 1.6c.5.3.8.9.7 1.5-.4 2.2-2.3 3.8-4.6 3.5C11.3 21.3 6.7 16.7 6.2 10.2c-.2-2.3 1.3-4.2 3.5-4.6z" fill="currentColor"/></svg>',
  gift: '<svg viewBox="0 0 28 28" width="28" height="28"><path d="M5.2 10.6h17.6v3.6H5.2zM6.4 15.6h6.8v7.6H7.9c-.8 0-1.5-.7-1.5-1.5zM14.8 15.6h6.8v6.1c0 .8-.7 1.5-1.5 1.5h-5.3z" fill="currentColor"/><path d="M14 10.2c-1.2-3.4-5.6-4.6-5.6-1.8 0 1.6 2.8 1.8 5.6 1.8zm0 0c1.2-3.4 5.6-4.6 5.6-1.8 0 1.6-2.8 1.8-5.6 1.8z" fill="none" stroke="currentColor" stroke-width="1.6"/></svg>',
  star: '<svg viewBox="0 0 14 14" width="11" height="11"><path d="M7 1l1.7 3.6 3.9.5-2.9 2.7.8 3.9L7 9.8 3.5 11.7l.8-3.9L1.4 5.1l3.9-.5z" fill="#ffc83d"/></svg>',
};

// The gifts on this profile: Telegram's own gift animations (assets/gifts, GPL), a few limited
// ones with their "1 of N" ribbon, and collectibles on their backdrops.
export const GIFTS = [
  { art: 'Cake', sender: 'Mark', avatar: 0 },
  { art: 'Diamond', unique: { outer: '#123f80', inner: '#3d9df5', symbol: 'diamond' }, number: 1205 },
  { art: 'Celebrate', limited: '10K', sender: 'Omar', avatar: 3 },
  { art: 'StarsBuy', sender: 'Ryan', avatar: 1 },
  { art: 'premium_gift', unique: { outer: '#3c2190', inner: '#9a6bff', symbol: 'star' }, number: 88 },
  { art: 'GramDiamond', limited: '3K', sender: 'Daniel', avatar: 5 },
  { art: 'SparklesEmoji', sender: 'Jonas', avatar: 6 },
  { art: 'star_reaction_activate', unique: { outer: '#8a4a0c', inner: '#f5b03c', symbol: 'star' }, number: 4321, resale: '1,250' },
  { art: 'anim_gift', tint: [1, 0.36, 0.42], sender: 'Sam', avatar: 2 },
  { art: 'Cake', unique: { outer: '#7e1733', inner: '#ff5c8a', symbol: 'sparkle' }, number: 77 },
  { art: 'Celebrate', sender: 'Leo', avatar: 4 },
  { art: 'star_reaction_appear', limited: '500', ribbon: 'red', sender: 'Alex', avatar: 5 },
];

// GiftItemComponent ribbon gradients (bottom-right end → top-left end), Day / Night.
const RIBBONS = {
  blue: { day: ['#34a4fc', '#6fd3ff'], night: ['#142e42', '#354f5b'] },
  red: { day: ['#ed1c26', '#ff5c55'], night: ['#522124', '#653634'] },
};

// Collectible ribbon: both ends from the backdrop's outer colour (withMultiplied hue, sat, bri).
function uniqueRibbon(outer) {
  const c = Color.hex(outer);
  return [c.withMultiplied(0.97, 1.45, 0.89).hex(), c.withMultiplied(1.01, 1.22, 1.04).hex()];
}

let ribbonId = 0;
function ribbonSVG(colors, text, mono) {
  const id = `rb${ribbonId++}`;
  // A 45° band between y = x − 28 and y = x in the 58 pt image; the text centred on it at (36, 22).
  return `<svg viewBox="0 0 58 58" width="58" height="58"><defs><linearGradient id="${id}" x1="58" y1="58" x2="0" y2="0" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="${colors[0]}"/><stop offset="1" stop-color="${colors[1]}"/></linearGradient></defs>`
    + `<path d="M0 0h28l30 30v28z" fill="url(#${id})"/>`
    + `<text x="36" y="22" transform="rotate(45 36 22)" text-anchor="middle" dominant-baseline="central" fill="#fff" font-size="${mono ? 10 : 9}" font-weight="600" font-family="${mono ? 'ui-monospace, SFMono-Regular, Menlo, monospace' : 'var(--font-text)'}">${text}</text></svg>`;
}

// Collectible backdrop: radial inner → outer over the tile, the symbol in profile-cover rings.
function backdrop(body, u, h) {
  body.style.background = `radial-gradient(circle at 50% 50%, ${u.inner} 0, ${u.outer} ${(h / 2).toFixed(1)}px)`;
  const sizes = [17, 15, 19, 16, 20, 18, 15, 21, 17, 16, 19, 18, 16, 20, 15, 18];
  let k = 0;
  for (let row = 0; row < 3; row++) {
    const r = (50 + 22) * 0.6 + 16.8 * row;
    for (let i = 0; i < 6; i++) {
      let a = -Math.PI / 2 + (i * Math.PI) / 3;
      if (row % 2) a += Math.PI / 6;
      const dx = Math.cos(a) * r;
      const dy = Math.sin(a) * r;
      if (Math.abs(dx) > h / 2 + 4 || Math.abs(dy) > h / 2 + 4) continue;
      const alpha = 0.48 * Math.max(0, 1 - Math.hypot(dx / 190, dy / (h / 2)));
      if (alpha < 0.02) continue;
      const s = sizes[k++ % sizes.length];
      el('div', 'gift-symbol', `left:${(h / 2 + dx - s / 2).toFixed(1)}px;top:${(h / 2 + dy - s / 2).toFixed(1)}px;width:${s}px;height:${s}px;opacity:${alpha.toFixed(3)}`, body,
        `<svg viewBox="0 0 24 24" width="${s}" height="${s}"><path d="${SYMBOL[u.symbol] || SYMBOL.sparkle}" fill="#000"/></svg>`);
    }
  }
}

export function buildProfilePage({ device, dark, chat, photoURL, tg, scale }) {
  const W = device.width;
  const H = device.height;
  const S = device.statusBar;
  const page = el('div', 'sub-page profile-page', `left:0;top:0;width:${W}px;height:${H}px`);
  const content = el('div', 'abs', `left:0;top:0;width:${W}px;will-change:transform`, page);

  // --- cover: the profile colour, its pattern, the photo, name and status
  const palette = { main: Color.hex('#2b5fa8'), secondary: Color.hex('#4c8de0') };
  const avatarCenter = { x: W / 2, y: S + 72 };
  const coverH = S + 72 + 50 + 9 + 34 + 1 + 21 + 14 + 58 + 18;
  const coverCanvas = el('canvas', 'abs', `left:0;top:0;width:${W}px;height:${coverH}px`, content);
  const cover = new Cover(coverCanvas);
  loadImage(svgDataURL(sparkleGlyph)).then((glyph) => {
    cover.draw({ width: W, height: coverH, canvasHeight: coverH, defaultHeight: coverH, avatarCenter, main: palette.main, secondary: palette.secondary, glyph, dark, scale: scale || 2, avatarTransitionFraction: 0 });
  });
  const av = el('div', 'profile-avatar', `left:${W / 2 - 50}px;top:${S + 22}px;width:100px;height:100px`, content);
  if (chat.photo) {
    const img = el('img', '', 'width:100%;height:100%;object-fit:cover;display:block;border-radius:50%', av);
    img.src = photoURL(chat.photo);
  } else {
    const g = AVATAR_GRADIENTS[(chat.avatar ?? 0) % AVATAR_GRADIENTS.length];
    av.style.background = `linear-gradient(180deg, ${g[1]}, ${g[0]})`;
    el('span', 'avatar-initials', 'font-size:40px', av, initials(chat.title));
  }
  const nameY = S + 22 + 100 + 9;
  el('div', 'profile-name t28 w500', `left:0;width:${W}px;top:${nameY}px;height:34px`, content, chat.title);
  el('div', 'profile-status t17 w400', `left:0;width:${W}px;top:${nameY + 35}px;height:21px`, content, chat.kind === 'channel' ? '12 400 subscribers' : chat.kind === 'group' ? '28 members, 4 online' : 'last seen recently');
  const btnY = nameY + 35 + 21 + 14;
  const labels = [['message', 'Message'], ['mute', 'Mute'], ['call', 'Call'], ['gift', 'Gift']];
  const bw = (W - 32 - 8 * (labels.length - 1)) / labels.length;
  labels.forEach(([icon, label], i) => {
    const b = el('div', 'glass profile-action', `left:${16 + i * (bw + 8)}px;top:${btnY}px;width:${bw}px;height:58px;border-radius:16px;--glass-tint:rgba(255,255,255,0.12)`, content);
    el('div', 'profile-action-icon', '', b, ICON[icon]);
    el('div', 'profile-action-label', '', b, label);
  });

  // --- info card
  let y = coverH + 16;
  const handle = chat.title.toLowerCase().replace(/[^a-z]/g, '');
  const info = [['username', `@${handle}`], ['bio', 'Product designer. Coffee, mountains, good type.']];   // no phone number shown
  const card = el('div', 'section', `left:16px;width:${W - 32}px;top:${y}px;height:${info.length * 62}px`, content);
  info.forEach(([k, v], i) => {
    const r = el('div', 'profile-info', `top:${i * 62}px`, card);
    el('div', 'profile-info-key', '', r, k);
    el('div', 'profile-info-value', '', r, v);
    if (i < info.length - 1) el('div', 'sep', 'left:16px', r);
  });
  y += info.length * 62 + 16;

  // --- pane: the glass tab capsule (h 40 at y 10, sized to fit) and the grid 66 pt below its top
  const paneTop = y;
  const tabNames = ['Gifts', 'Media', 'Files', 'Links', 'Voice'];
  const tabBar = el('div', 'glass profile-tabs', `top:${paneTop + 10}px;height:40px;border-radius:20px`, content);
  const pill = el('div', 'profile-tab-pill', 'top:3px;height:34px', tabBar);
  const tabEls = tabNames.map((t, i) => {
    const e = el('div', `profile-tab${i === 0 ? ' selected' : ''}`, '', tabBar, `<span>${t}</span>`);
    if (i === 0) {
      // "Gifts" followed by the first three gifts as 18 pt stickers (each plays once, scaling in).
      const minis = el('span', 'profile-tab-minis', '', e);
      GIFTS.slice(0, 3).forEach((g) => {
        const m = el('span', 'profile-tab-mini', '', minis);
        const icon = new LottieIcon(m, { name: giftURL(g.art), maxFps: 30, tint: g.tint || null, onReady: (l) => { if (l.t0 == null) l.seekToEnd(); } });
        e.minis = (e.minis || []).concat(icon);
      });
    }
    return e;
  });
  y = paneTop + 66;

  // --- the gifts grid
  const cols = 3;
  const gap = 10;
  const side = (W - 32 - gap * (cols - 1)) / cols;
  const sticker = Math.floor((88 * side) / 116);
  const tiles = [];
  GIFTS.forEach((g, i) => {
    const x = 16 + (i % cols) * (side + gap);
    const ty = y + Math.floor(i / cols) * (side + gap);
    const slot = el('div', 'gift-slot', `left:${x}px;top:${ty}px;width:${side}px;height:${side}px`, content);
    const shadow = el('div', 'gift-shadow', '', slot);
    const tile = el('div', 'gift-tile', '', slot);
    // The glass pane (clipped: backdrop, prismatic streak, sheen, light fragments) …
    const body = el('div', `gift-body${g.unique ? ' unique' : ''}`, '', tile);
    if (g.unique) backdrop(body, g.unique, side);
    const holo = el('div', 'gift-holo', '', body);
    const sheen = el('div', 'gift-sheen', '', body);
    const shards = [0, 1, 2].map((k) => el('div', 'gift-shard', `top:${-60 + k * 28}%`, body));
    // … its lit edge, and what floats above it in 3D: the gift, the ribbon, the badges.
    const rim = el('div', 'gift-rim', '', tile);
    const art = el('div', 'gift-art', `left:${(side - sticker) / 2}px;top:${(side - sticker) / 2}px;width:${sticker}px;height:${sticker}px`, tile);
    // At rest every gift shows its finished frame (some animations start from nothing).
    const lottie = new LottieIcon(art, { name: giftURL(g.art), maxFps: 30, tint: g.tint || null, onReady: (l) => { if (!l.t0 && l.t0 !== 0) l.seekToEnd(); } });
    let ribbon = null;
    if (g.limited || g.unique) {
      const colors = g.unique ? uniqueRibbon(g.unique.outer) : RIBBONS[g.ribbon || 'blue'][dark ? 'night' : 'day'];
      ribbon = el('div', 'gift-ribbon', `left:${side - 56}px;top:-2px`, tile, ribbonSVG(colors, g.unique ? `#${g.number}` : `1 of ${g.limited}`, !!g.unique));
    }
    const badges = [];
    if (!g.unique && g.sender) {
      const grad = AVATAR_GRADIENTS[g.avatar % AVATAR_GRADIENTS.length];
      badges.push(el('div', 'gift-sender', `background:linear-gradient(180deg, ${grad[1]}, ${grad[0]})`, tile, g.sender[0]));
    }
    if (g.resale) badges.push(el('div', 'gift-resale', `top:${side - 20 - 9}px`, tile, `${ICON.star}<span>${g.resale}</span>`));
    const sparkles = [[8, 8], [side - 18, 10], [10, side - 20], [side - 16, side - 18]].map(([sx, sy]) => el('div', 'gift-sparkle', `left:${sx}px;top:${sy}px`, tile));
    const t = new GlassTile(tile, { gift: art, ribbon, badges, sheen, holo, rim, shadow, shards, sparkles });
    t.slot = { x, y: ty, w: side, h: side };
    t.lottie = lottie;
    t.seen = false;
    tiles.push(t);
  });
  const contentH = y + Math.ceil(GIFTS.length / cols) * (side + gap) + 120;
  content.style.height = `${contentH}px`;

  // --- nav (over the content): a fade appears behind it once the cover has scrolled away
  const fadeH = S + 64 + 30;
  const stops = [[1, 0], [0.92, 0.23], [0.74, 0.38], [0.51, 0.49], [0.25, 0.62], [0.11, 0.73], [0, 1]];
  const band = 40;
  const mask = stops.map(([a, u]) => `rgba(0,0,0,${a}) ${(fadeH - band + u * band).toFixed(1)}px`).join(',');
  const fade = el('div', 'chats-fade', `left:0;top:0;width:${W}px;height:${fadeH}px;opacity:0;-webkit-mask-image:linear-gradient(180deg,#000 0,#000 ${fadeH - band}px,${mask});mask-image:linear-gradient(180deg,#000 0,#000 ${fadeH - band}px,${mask})`, page);
  const back = el('div', 'glass sub-back', `left:16px;top:${S + 10}px;width:44px;height:44px;--glass-tint:rgba(255,255,255,0.12);color:#fff`, page, chevronLeft);

  // The tab capsule fits its content: lay it out once it is in the page.
  const layoutTabs = () => {
    let x = 4;
    const widths = tabEls.map((e) => Math.ceil(e.getBoundingClientRect().width / (page.getBoundingClientRect().width / W)) + 28);
    tabEls.forEach((e, i) => { e.style.left = `${x}px`; e.style.width = `${widths[i]}px`; x += widths[i]; });
    const total = x + 4;
    tabBar.style.width = `${Math.min(W - 32, total)}px`;
    tabBar.style.left = `${(W - Math.min(W - 32, total)) / 2}px`;
    pill.style.left = '4px';
    pill.style.width = `${widths[0]}px`;
  };

  // --- behaviour
  const scroller = new Scroller({ viewport: H, content: contentH });
  const motion = new MotionSource(tg);
  const tracker = new VelocityTracker(0.08);
  let touch = null;
  let laid = null;
  let lastNow = null;
  let held = null;           // the tile being inspected (press, hold, slide)
  let shown = false;
  const tileAt = (p) => {
    const cy = p[1] + scroller.offset;
    return tiles.find((t) => p[0] >= t.slot.x && p[0] <= t.slot.x + t.slot.w && cy >= t.slot.y && cy <= t.slot.y + t.slot.h) || null;
  };
  const aimAt = (t, p) => {
    const cy = p[1] + scroller.offset;
    t.aim(((p[0] - t.slot.x) / t.slot.w) * 2 - 1, ((cy - t.slot.y) / t.slot.h) * 2 - 1);
  };
  const play = (t, now) => { t.lottie.play(now); t.playing = true; };

  const api = {
    el: page,
    backButton: back,
    headerColor: palette.secondary.hex(),
    onShown(now) {
      shown = true;
      layoutTabs();
      tabEls[0].minis?.forEach((m, i) => { m.el.style.animation = `gift-mini-in 0.2s ${(i * 0.05).toFixed(2)}s both`; m.play(now); });
      motion.start();
    },
    onPopped() { motion.stop(); },
    // While a tile is being inspected, horizontal slides are the tiles' (not a swipe back).
    claimsHorizontal() { return !!held || touch?.kind === 'inspect'; },
    down(p, now) {
      motion.start();
      tracker.reset();
      tracker.add(now, p[0], p[1]);
      if (scroller.moving) { scroller.stop(); touch = { start: p, last: p, caught: true, t0: now }; return; }
      const t = tileAt(p);
      touch = { start: p, last: p, tile: t, t0: now, kind: 'pending' };
      if (t) {
        aimAt(t, p);
        t.burst(now);
      }
    },
    move(p, now) {
      if (!touch) return;
      tracker.add(now, p[0], p[1]);
      touch.last = p;
      const dx = p[0] - touch.start[0];
      const dy = p[1] - touch.start[1];
      if (touch.kind === 'pending') {
        if (touch.tile && now - touch.t0 > 0.12 && Math.hypot(dx, dy) < 10) {
          touch.kind = 'inspect';
          held = touch.tile;
          Haptics.tap();
        } else if (Math.hypot(dx, dy) > 8) {
          touch.kind = 'scroll';
          touch.tile?.release();
          scroller.begin(p[1]);
        }
      }
      if (touch.kind === 'scroll') scroller.drag(p[1]);
      else if (touch.kind === 'inspect') {
        const t = tileAt(p);
        if (t !== held) {
          held?.release();
          if (t) { t.burst(now); Haptics.tap(); }
          held = t;
        }
        if (held) aimAt(held, p);
      } else if (touch.tile) aimAt(touch.tile, p);
    },
    up(p, now, cancelled) {
      motion.start();   // Safari grants motion access on a completed tap
      if (!touch) return;
      const t0 = touch;
      touch = null;
      const v = tracker.velocity(now);
      if (t0.kind === 'scroll') { scroller.end(cancelled ? 0 : v.y, now); return; }
      if (t0.kind === 'inspect') { held?.release(); held = null; return; }
      // A tap opens nothing here (Telegram's gift info sheet isn't part of the concept): the
      // glass just eases back.
      t0.tile?.release();
    },
    // A mouse over the grid (no button pressed): the tile under it leans toward the pointer.
    hover(p) {
      const t = p ? tileAt(p) : null;
      if (t !== held) { held?.release(); held = t; }
      if (t) aimAt(t, p);
      if (!t) held = null;
    },
    update(now) {
      const dt = lastNow == null ? 1 / 60 : Math.max(0, Math.min(0.05, now - lastNow));
      lastNow = now;
      let busy = scroller.update(now);
      if (scroller.offset !== laid) {
        laid = scroller.offset;
        content.style.transform = `translate3d(0,${(-laid).toFixed(2)}px,0)`;
        const f = Math.max(0, Math.min(1, (laid - (coverH - S - 80)) / 40));
        fade.style.opacity = f.toFixed(3);
        back.style.color = f > 0.5 ? 'var(--tg-text)' : '#fff';
      }
      // Stickers play once as their tile comes into view (again after scrolling back to it), a
      // few at a time.
      if (shown) {
        let playing = tiles.filter((t) => t.playing).length;
        for (const t of tiles) {
          const top = t.slot.y - laid;
          const visible = top < H - 40 && top + t.slot.h > 60;
          if (!visible) t.seen = false;
          else if (!t.seen && playing < 6 && t.lottie.anim && (api.nextPlay == null || now >= api.nextPlay)) {
            t.seen = true;
            play(t, now);
            playing++;
            api.nextPlay = now + 0.08;    // staggered, a few at a time
          }
        }
      }
      const light = motion.update(dt);
      for (const t of tiles) {
        if (t.update(now, dt, light)) busy = true;
        if (t.playing && !t.lottie.update(now)) t.playing = false;
        if (t.playing) busy = true;
      }
      for (const m of tabEls[0].minis || []) if (m.update(now)) busy = true;
      return busy || !!light || !!touch;
    },
    tiles,
    scroller,
    motion,
  };
  return api;
}
