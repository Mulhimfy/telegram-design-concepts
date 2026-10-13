// Telegram iOS 13.0 Settings tab (own profile header + menu), laid out with the
// exact PeerInfoHeaderNode / PeerInfoScreen formulas (research/telegram-ios).

import { Color } from '../core/color.js';
import { buildStatusBar } from './statusbar.js';

const ICONS = '../prototype/assets/icons/';

export function iconURL(name) {
  return new URL(`../../assets/icons/${name}.svg`, import.meta.url).href;
}

function el(tag, cls, style, parent, html) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (style) e.style.cssText = style;
  if (html !== undefined) e.innerHTML = html;
  if (parent) parent.appendChild(e);
  return e;
}

function maskIcon(name, style, parent, color) {
  const e = el('span', 'mask-icon abs', style, parent);
  const url = iconURL(name);
  e.style.webkitMaskImage = `url("${url}")`;
  e.style.maskImage = `url("${url}")`;
  if (color) e.style.color = color;
  return e;
}

// renderSettingsIcon(name:backgroundColors:) — PresentationResourcesSettings.swift — or, with `stops`,
// one of the tiles it draws itself (SettingsTiles).
function settingsIcon(name, colors, style, parent, stops) {
  const wrap = el('div', 'settings-icon', style, parent);
  wrap.style.setProperty('--c0', colors[0]);
  if (colors[1]) wrap.style.setProperty('--c1', colors[1]);
  wrap.style.background = tileBackground(colors, stops);
  el('div', 'sheen', '', wrap);
  el('div', 'backdrop', '', wrap);
  maskIcon(name, 'inset:0;width:30px;height:30px', wrap, '#fff');
  return wrap;
}

// PresentationResourcesSettings.swift:109-117
export const SettingsColors = {
  red: '#FF453A', green: '#34C759', blue: '#0079ff', lightBlue: '#32ADE6', teal: '#00c7be',
  orange: '#FF9F0A', purple: '#AF52DE', gray: '#8E8E93', violet: '#5E5CE6',
};

// The tiles PresentationResourcesSettings draws itself (`premium`, `stars`, `premiumGift`): the same
// sheen and backdrop on a gradient of their own.
export const SettingsTiles = {
  premium: { colors: ['#6b93ff', '#6b93ff', '#8d77ff', '#b56eec', '#b56eec'], stops: [0, 0.15, 0.5, 0.85, 1] },
  stars: { colors: ['#fec80f', '#dd6f12'], stops: [0, 1] },
  premiumGift: { colors: ['#3ba1f2', '#3ba1f2', '#39b3b4', '#34c27d', '#34c27d'], stops: [0, 0.15, 0.5, 0.85, 1] },
};

// Telegram draws its tiles in a y-up context: renderSettingsIcon's gradient runs from (w, h) — the
// top-right corner, first colour — to (0, 0), the bottom-left; the tiles it draws itself run the other
// way, from the bottom-left (first stop) to the top-right.
function tileBackground(colors, stops) {
  if (stops) return `linear-gradient(45deg, ${colors.map((c, i) => `${c} ${+(stops[i] * 100).toFixed(2)}%`).join(', ')})`;
  return colors.length > 1 ? `linear-gradient(225deg, ${colors.join(', ')})` : colors[0];
}

export function headerColors(palette, dark) {
  // PeerInfoHeaderNode.swift:647-702 (profile colour branch)
  const main = palette.main;
  const secondary = palette.secondary || palette.main;
  const navSecondary = Color.white(1, 0.6).blitOver(main.withMultiplied(1, 2.2, 1.5), 1);
  const base = dark ? Color.white(0, 0.25) : Color.white(1, 0.25);
  const contentButtonBg = base.blendOver(main);
  const headerButtonBg = base.blendOver(secondary.mixedWith(main, 0.1));
  return { main, secondary, navSecondary, contentButtonBg, headerButtonBg };
}

export function buildSettingsScreen(screen, { device, persona, palette, dark = true }) {
  const W = device.width;
  const S = device.statusBar;
  const colors = headerColors(palette, dark);

  // --- header geometry (PeerInfoHeaderNode, isSettings, not expanded, contentOffset 0)
  const avatarSize = 100;
  const avatarFrame = { x: Math.floor((W - avatarSize) / 2), y: S + 22, w: avatarSize, h: avatarSize };
  const avatarCenter = { x: avatarFrame.x + 50, y: avatarFrame.y + 50 };
  const navigationHeight = S + 60;
  const panelWithAvatarHeight = 35 + avatarSize;
  const backgroundHeight = navigationHeight + panelWithAvatarHeight + 20; // expandablePart += 20 (settings)
  const resolvedHeight = panelWithAvatarHeight + navigationHeight;
  const titleY = avatarFrame.y + avatarFrame.h + 9;
  const titleH = 34;
  const subtitleY = titleY + titleH + 1;

  // --- layers
  // Navigation-bar background under the header (headerEdgeEffectView: plain background at
  // 0.75, opaque to N − 42 then fading over 60 pt; PeerInfoScreen / EdgeEffect.swift).
  const edgeStops = [1, 0.98, 0.94, 0.85, 0.69, 0.48, 0.29, 0.14, 0.05, 0.03, 0];
  const edgeH = navigationHeight + 18 + 50;
  const edgeMask = edgeStops.map((a, i) => `rgba(0,0,0,${a}) ${(navigationHeight - 42 + 50 + i * 6).toFixed(1)}px`).join(',');
  const edge = el('div', 'abs', `left:0;top:-50px;width:${W}px;height:${edgeH}px;z-index:1;pointer-events:none;`
    + `background:${dark ? 'rgba(0,0,0,0.75)' : 'rgba(255,255,255,0.75)'};`
    + `-webkit-mask-image:linear-gradient(180deg,${edgeMask});mask-image:linear-gradient(180deg,${edgeMask})`, screen);
  const coverCanvasHeight = backgroundHeight + 300;
  const cover = el('canvas', 'abs', `left:0;top:0;width:${W}px;height:${coverCanvasHeight}px;z-index:1`, screen);
  const coinSize = 220;
  const coin = el('canvas', 'abs', `left:${avatarCenter.x - coinSize / 2}px;top:${avatarCenter.y - coinSize / 2}px;width:${coinSize}px;height:${coinSize}px;z-index:2;touch-action:none`, screen);

  const title = el('div', 'abs', `left:0;width:${W}px;top:${titleY}px;height:${titleH}px;display:flex;justify-content:center;align-items:center;z-index:3;pointer-events:none`, screen);
  const titleText = el('span', 't28 w500', 'color:#fff;white-space:nowrap', title, persona.name);
  const status = el('span', '', 'width:26px;height:26px;margin-left:4px;flex:none;display:flex;align-items:center;justify-content:center', title);
  if (persona.statusImage) {
    el('img', '', 'width:26px;height:26px;object-fit:contain;image-rendering:auto', status).src = persona.statusImage;
  }
  const subtitle = el('div', 'abs t17 w400', `left:0;width:${W}px;top:${subtitleY}px;height:21px;text-align:center;z-index:3;pointer-events:none;color:${colors.navSecondary.css()};white-space:nowrap`, screen, persona.subtitle);

  // --- navigation buttons: QR (left), Search + Edit capsule (right) — 44pt glass, inset 16, y = S + 10
  const navY = S + 10;
  const glassTint = colors.headerButtonBg.withAlpha(0.82).css();
  const qr = el('div', 'glass', `left:16px;top:${navY}px;width:44px;height:44px;z-index:4;--glass-tint:${glassTint}`, screen);
  maskIcon('nav-qr30', 'left:7px;top:7px;width:30px;height:30px', qr, '#fff');
  const editW = 31; // "Edit" in SF Pro Text Medium 17
  const capW = 44 + editW + 24;
  const cap = el('div', 'glass', `left:${W - 16 - capW}px;top:${navY}px;width:${capW}px;height:44px;z-index:4;--glass-tint:${glassTint}`, screen);
  maskIcon('nav-search', 'left:9px;top:7px;width:30px;height:30px', cap, '#fff');
  el('div', 'abs t17 w500', `left:56px;top:11px;width:${editW + 12}px;height:22px;color:#fff;text-align:left`, cap, 'Edit');

  // --- status bar
  const statusBar = buildStatusBar(screen, device, { time: persona.time || '9:41' });

  // --- menu sections (PeerInfoScreen settings items), first gap 24 + 12
  const list = el('div', 'abs', `left:0;top:0;width:${W}px;height:${device.height}px;z-index:0`, screen);
  const inset = Math.max(16, Math.floor((W - 674) / 2));
  const rowH = 52.33;
  let y = resolvedHeight + 36;
  const listTop = y;
  const sections = persona.sections || defaultSettingsSections();
  const rows = [];
  for (const section of sections) {
    const sec = el('div', 'section', `left:${inset}px;width:${W - inset * 2}px;top:${y}px;height:${section.length * rowH}px`, list);
    section.forEach((item, i) => {
      const row = el('div', `row${item.accent ? ' accent' : ''}`, `top:${i * rowH}px`, sec);
      const highlight = el('div', 'highlight', '', row);
      const entry = { id: item.id || item.title, el: row, highlight, title: null, x: inset, y: y + i * rowH, w: W - inset * 2, h: rowH, icon: item.glyph || item.icon || null, glyph: null, tile: null, tileColor: null };
      rows.push(entry);
      if (item.glyph) {
        entry.glyph = maskIcon(item.glyph, `left:16px;top:${(rowH - 30) / 2}px;width:30px;height:30px`, row, 'var(--tg-accent)');
      } else if (item.icon) {
        entry.tile = settingsIcon(item.icon, item.colors, `left:16px;top:${(rowH - 30) / 2}px`, row, item.stops);
        entry.glyph = entry.tile.querySelector('.mask-icon');
        entry.tileColor = item.colors[0];
      } else if (item.custom) {
        entry.glyph = el('div', 'abs', `left:16px;top:${(rowH - 30) / 2}px;width:30px;height:30px`, row, item.custom);
        entry.icon = 'money';
      }
      const t = el('div', 'title t17 w400', `left:61px`, row);
      t.textContent = item.title;
      rows[rows.length - 1].title = t;
      if (item.newBadge) el('span', 'new-badge', '', t, 'NEW');
      if (item.value) el('div', 'value t17 w400', '', row, item.value);
      if (item.badge) el('div', 'badge', `right:34px;top:${(rowH - 20) / 2}px`, row, item.badge);
      maskIcon('ic-disclosure', `right:7px;top:${(rowH - 24) / 2}px;width:24px;height:24px`, row, 'var(--tg-disclosure)');
      if (i < section.length - 1) el('div', 'sep', '', row);
    });
    y += section.length * rowH + 24;
  }
  const listBottom = y - 24;

  // --- tab bar (iOS 26 glass capsule)
  const tab = buildTabBar(screen, device);

  return {
    cover, edge, coin, title, titleText, subtitle, qr, cap, list, tab, statusBar, rows, listTop, listBottom, status,
    geometry: {
      W, S, avatarFrame, avatarCenter, backgroundHeight, coverCanvasHeight, coinSize, defaultHeight: 254,
      navigationHeight, titleY, titleH, subtitleY,
    },
    colors,
  };
}

export function defaultSettingsSections() {
  const c = SettingsColors;
  return [
    [
      { glyph: 'set-emoji-status', title: 'Change Emoji Status', accent: true },
      { glyph: 'set-covercolor', title: 'Change Profile Color', accent: true },
      { glyph: 'set-avatar', title: 'Change Profile Photo', accent: true },
      { id: 'backPhoto', glyph: 'set-backphoto', title: 'Add Back Photo', accent: true, newBadge: true },
      { id: 'glassColor', glyph: 'set-glass', title: 'Change Glass Color', accent: true, newBadge: true },
    ],
    [{ icon: 'ic-profile', colors: [c.red], title: 'My Profile' }],
    [{ custom: moneyIcon(), title: 'Money', newBadge: true, value: '<span style="font-size:17px">0.</span><span style="font-size:13px">09</span>' }],
    [{ icon: 'ic-proxy', colors: [c.green], title: 'Proxy', value: 'Disabled' }],
    [
      { icon: 'ic-saved', colors: [c.blue], title: 'Saved Messages' },
      { icon: 'ic-phone', colors: [c.green], title: 'Recent Calls' },
      { icon: 'ic-devices', colors: [c.orange], title: 'Devices', value: '10' },
      { icon: 'ic-folder', colors: [c.lightBlue], title: 'Chat Folders' },
    ],
    [
      { icon: 'ic-bell', colors: [c.red], title: 'Notifications and Sounds', badge: '!' },
      { icon: 'ic-lock', colors: [c.gray], title: 'Privacy and Security' },
      { icon: 'ic-data', colors: [c.green], title: 'Data and Storage' },
      { icon: 'ic-appearance', colors: [c.lightBlue], title: 'Appearance' },
      { icon: 'ic-power', colors: [c.orange], title: 'Power Saving', value: 'Off' },
      { icon: 'ic-language', colors: [c.purple], title: 'Language', value: 'English' },
    ],
    [
      { icon: 'ic-premium', ...SettingsTiles.premium, title: 'Telegram Premium' },
      { icon: 'ic-stars', ...SettingsTiles.stars, title: 'My Stars' },
      { icon: 'ic-business', colors: ['#A95CE3', '#F16B80'], title: 'Telegram Business', newBadge: true },
      { icon: 'ic-gift', ...SettingsTiles.premiumGift, title: 'Send a Gift' },
    ],
    [
      { icon: 'ic-ask', colors: [c.orange], title: 'Ask a Question' },
      { icon: 'ic-faq', colors: [c.lightBlue], title: 'Telegram FAQ' },
      { icon: 'ic-features', colors: ['#ffcc02'], title: 'Telegram Features' },
    ],
  ];
}

// Money's icon is Telegram's bitmap "Settings/Gram" (PresentationResourcesSettings.money: 29 × 24.33 pt,
// no tile), placed as the row places it (x 0, centred vertically). It is drawn as the gem and the
// sparkle in it (tools/telegram-money.mjs splits the bitmap as the native module does) so the sparkle
// can turn on its own: living-icons.js turns `[data-inner]` about (15, 13.4), which the wrapper moves
// onto the sparkle's centre.
const MONEY = { y: 2.8333, w: 29, h: 24.3333, sparkle: [18.1418, 11.0582] };
function moneyIcon() {
  const src = (name) => new URL(`../../assets/icons/${name}`, import.meta.url).href;
  const dx = +(MONEY.sparkle[0] - 15).toFixed(4);
  const dy = +(MONEY.sparkle[1] - 13.4).toFixed(4);
  return `<svg viewBox="0 0 30 30" width="30" height="30" style="overflow:visible">`
    + `<image href="${src('money-gem@3x.png')}" x="0" y="${MONEY.y}" width="${MONEY.w}" height="${MONEY.h}"/>`
    + `<g transform="translate(${dx} ${dy})"><g data-inner><image href="${src('money-sparkle@3x.png')}" x="${-dx}" y="${+(MONEY.y - dy).toFixed(4)}" width="${MONEY.w}" height="${MONEY.h}"/></g></g></svg>`;
}

export function buildTabBar(screen, device, { selected = 3, badges = { 2: '289', 3: '!' } } = {}) {
  const W = device.width;
  const h = 62;
  const sideInset = 21;
  const bottom = device.island ? 21 : 20;
  const top = device.height - bottom - h;
  const bar = el('div', 'glass tabbar', `left:${sideInset}px;top:${top}px;width:${W - sideInset * 2}px;height:${h}px;z-index:30;--glass-blur:8px`, screen);
  const items = [
    { icon: 'tab-contacts', label: 'Contacts' },
    { icon: 'tab-calls', label: 'Calls' },
    { icon: 'tab-chats', label: 'Chats' },
    { icon: 'tab-settings', label: 'Settings' },
  ];
  const innerW = W - sideInset * 2;
  const pad = 4;
  const itemW = (innerW - pad * 2) / items.length;
  // The selection capsule (moves when the tab changes: app.js).
  bar.capsule = el('div', 'abs tab-pill', `left:${pad + selected * itemW}px;top:5px;width:${itemW}px;height:${h - 10}px;border-radius:999px;will-change:left`, bar);
  bar.items = [];
  bar.itemX = (i) => pad + i * itemW;
  bar.itemW = itemW;
  items.forEach((it, i) => {
    const x = pad + i * itemW;
    const item = el('div', `item${i === selected ? ' selected' : ''}`, `left:${x}px;width:${itemW}px`, bar);
    bar.items.push(item);
    maskIcon(it.icon, 'position:relative;width:30px;height:30px;margin-top:2px', item);
    el('div', 'label', '', item, it.label);
    if (badges[i]) {
      const b = el('div', 'badge', `left:${x + itemW / 2 + 4}px;top:7px;font-size:13px;height:18px;line-height:18px;min-width:18px;border-radius:9px;padding:0 5px;z-index:2`, bar, badges[i]);
    }
  });
  return bar;
}
