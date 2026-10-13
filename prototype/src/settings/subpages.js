// The pages behind the Settings rows, in Telegram iOS 26's glass list style
// (research/telegram-ios/settings-icons-and-gifts.md §A6): bar SB + 60 with the 44 pt glass back
// circle (chevron only) and the title (semibold 17); cards inset 16, corner 26; rows ≈ 50 pt
// (vertical inset 15), the 30 pt icon tile centred in a 59 pt gutter, text at 59; section headers
// regular 13 at x 15. Notifications and Privacy carry their real first rows. Coming back from one is
// what makes the row's icon come alive (settings/living-icons.js).

import { chevronLeft } from './nav.js';

function el(tag, cls, style, parent, html) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (style) e.style.cssText = style;
  if (html !== undefined) e.innerHTML = html;
  if (parent) parent.appendChild(e);
  return e;
}

// PresentationResourcesSettings colours (PRS:145-172) and simple white glyphs (30 × 30).
const C = { blue: '#0079ff', green: '#34c759', orange: '#ff9f0a', violet: '#5e5ce6', pink: '#ff2d55', red: '#ff3b30', purple: '#af52de' };
const G = {
  member: '<path d="M15 6.8a4.2 4.2 0 1 1 0 8.4 4.2 4.2 0 0 1 0-8.4zM7.6 23.2c.4-3.9 3.6-6.4 7.4-6.4s7 2.5 7.4 6.4z" fill="#fff"/>',
  group: '<path d="M12.4 8a3.7 3.7 0 1 1 0 7.4 3.7 3.7 0 0 1 0-7.4zM5.9 22.6c.4-3.5 3.1-5.7 6.5-5.7s6.1 2.2 6.5 5.7z" fill="#fff"/><path d="M19.3 9.4a3.1 3.1 0 1 1 0 6.2 3.1 3.1 0 0 1 0-6.2zm1.6 7.9c2.2.6 3.6 2.4 3.8 4.9h-4.4c-.2-1.9-.9-3.6-2.1-4.9.9-.2 1.8-.2 2.7 0z" fill="#fff" opacity=".85"/>',
  channel: '<path d="M21.6 8.1v13.8c0 .7-.8 1.1-1.4.7l-4.6-3.3H11l.9 4.1c.1.6-.3 1.2-1 1.2h-.9c-.5 0-.9-.3-1-.8l-1.1-4.7A3.6 3.6 0 0 1 6.6 16v-2c0-2 1.6-3.6 3.6-3.6h5.4l4.6-3.1c.6-.4 1.4 0 1.4.8zM23.4 12.3a2.8 2.8 0 0 1 0 5.4z" fill="#fff"/>',
  stories: '<circle cx="15" cy="15" r="8.4" fill="none" stroke="#fff" stroke-width="1.9" stroke-dasharray="4.6 2.6" stroke-linecap="round"/><path d="M15 11.2v7.6M11.2 15h7.6" stroke="#fff" stroke-width="1.9" stroke-linecap="round"/>',
  heart: '<path d="M15 23s-7.6-4.6-7.6-10.1A4.1 4.1 0 0 1 15 10.6a4.1 4.1 0 0 1 7.6 2.3C22.6 18.4 15 23 15 23z" fill="#fff"/>',
  block: '<circle cx="15" cy="15" r="7.6" fill="none" stroke="#fff" stroke-width="2"/><path d="M9.7 20.3 20.3 9.7" stroke="#fff" stroke-width="2" stroke-linecap="round"/>',
  faceid: '<path d="M8 11.5V9.8C8 8.8 8.8 8 9.8 8h1.7M18.5 8h1.7c1 0 1.8.8 1.8 1.8v1.7M22 18.5v1.7c0 1-.8 1.8-1.8 1.8h-1.7M11.5 22H9.8C8.8 22 8 21.2 8 20.2v-1.7" fill="none" stroke="#fff" stroke-width="1.8" stroke-linecap="round"/><path d="M12.2 12.6v1.3M17.8 12.6v1.3M15.1 12.8v3.1h-.8M12.6 18.3c1.4 1.1 3.4 1.1 4.8 0" fill="none" stroke="#fff" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>',
  lock: '<path d="M11 13.6v-2.3a4 4 0 0 1 8 0v2.3h.4c1.1 0 2 .9 2 2v5.1c0 1.1-.9 2-2 2h-8.8c-1.1 0-2-.9-2-2v-5.1c0-1.1.9-2 2-2zm2.1 0h3.8v-2.3a1.9 1.9 0 0 0-3.8 0z" fill="#fff"/>',
  key: '<circle cx="11.2" cy="15" r="4.2" fill="none" stroke="#fff" stroke-width="2"/><path d="M15.4 15h7.4M20.2 15v3.2M22.8 15v2.4" stroke="#fff" stroke-width="2" stroke-linecap="round"/>',
  timer: '<circle cx="15" cy="16.2" r="7" fill="none" stroke="#fff" stroke-width="1.9"/><path d="M15 12.4v3.8l2.4 1.6M13 6.8h4" stroke="#fff" stroke-width="1.9" stroke-linecap="round"/>',
  email: '<rect x="7" y="9" width="16" height="12" rx="2.4" fill="#fff"/><path d="M8.2 10.6 15 15.6l6.8-5" fill="none" stroke="var(--tile)" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>',
};
const icon = (glyph, color) => ({ glyph, color });

// Settings row titles → page (title shown in the bar, sections).
export const PAGES = {
  'Notifications and Sounds': { title: 'Notifications', sections: [
    { header: 'Message notifications', rows: [
      { title: 'Private Chats', value: 'On', icon: icon('member', C.blue) },
      { title: 'Group Chats', value: 'On', icon: icon('group', C.green) },
      { title: 'Channels', value: 'On', icon: icon('channel', C.orange) },
      { title: 'Stories', value: 'Top 5', icon: icon('stories', C.violet) },
      { title: 'Reactions', subtitle: 'Messages, Stories', value: 'On', icon: icon('heart', C.pink) },
    ] },
    { header: 'In-app notifications', rows: [{ title: 'In-App Sounds', toggle: true }, { title: 'In-App Vibrate', toggle: true }, { title: 'In-App Preview', toggle: true }] },
  ] },
  'Privacy and Security': { sections: [
    { rows: [
      { title: 'Blocked Users', value: 'None', icon: icon('block', C.red) },
      { title: 'Passcode & Face ID', value: 'Off', icon: icon('faceid', C.green) },
      { title: 'Two-Step Verification', value: 'On', icon: icon('lock', C.orange) },
      { title: 'Passkey', value: 'Off', icon: icon('key', C.violet) },
      { title: 'Auto-Delete Messages', value: 'Off', icon: icon('timer', C.purple) },
    ], footer: 'Automatically delete messages for everyone after a period of time in all new chats you start.' },
    { rows: [{ title: 'Login Email', icon: icon('email', C.violet) }] },
    { header: 'Privacy', rows: [
      { title: 'Phone Number', value: 'My Contacts' }, { title: 'Last Seen & Online', value: 'Everybody' }, { title: 'Profile Photo', value: 'Everybody' },
      { title: 'Bio', value: 'Everybody' }, { title: 'Gifts', value: 'Everybody' }, { title: 'Birthday', value: 'My Contacts' },
    ] },
  ] },
  'My Profile': { sections: [
    { rows: [{ title: 'Edit Profile' }, { title: 'Posts', value: '12' }, { title: 'Gifts', value: '3' }] },
    { header: 'Profile', rows: [{ title: 'Name Color' }, { title: 'Profile Color' }, { title: 'Emoji Status' }] },
  ] },
  Money: { sections: [
    { rows: [{ title: 'Balance', value: '0.09 TON' }, { title: 'Add Funds', accent: true }, { title: 'Withdraw', accent: true }] },
    { header: 'History', rows: [{ title: 'Transactions' }] },
  ] },
  Proxy: { sections: [
    { rows: [{ title: 'Use Proxy', toggle: false }] },
    { header: 'Saved proxies', rows: [{ title: 'Add Proxy', accent: true }] },
    { rows: [{ title: 'Use for Calls', toggle: false }] },
  ] },
  'Saved Messages': { sections: [
    { rows: [{ title: 'Tags' }, { title: 'View as Chats', toggle: true }] },
  ] },
  'Recent Calls': { title: 'Calls', sections: [
    { rows: [{ title: 'Start New Call', accent: true }] },
    { header: 'Recent', rows: [{ title: 'Alex Turner', value: '9:12' }, { title: 'Mark Chen', value: 'Sat' }, { title: 'Omar', value: 'Fri' }] },
  ] },
  Devices: { sections: [
    { header: 'This device', rows: [{ title: 'iPhone 11 · Telegram iOS' }] },
    { rows: [{ title: 'Terminate All Other Sessions', destructive: true }] },
    { header: 'Active sessions', rows: [{ title: 'MacBook Pro', value: '9:20' }, { title: 'Telegram Web', value: 'Yesterday' }] },
  ] },
  'Chat Folders': { title: 'Folders', sections: [
    { header: 'My folders', rows: [{ title: 'Personal', value: '12' }, { title: 'Work', value: '8' }, { title: 'Create a Folder', accent: true }] },
    { header: 'Recommended folders', rows: [{ title: 'Unread', value: 'Add' }, { title: 'Personal', value: 'Add' }] },
  ] },
  'Data and Storage': { sections: [
    { rows: [{ title: 'Storage Usage', value: '1.2 GB' }, { title: 'Data Usage', value: '8.4 GB' }] },
    { header: 'Automatic media download', rows: [{ title: 'Using Cellular', value: 'On' }, { title: 'Using Wi-Fi', value: 'On' }, { title: 'Reset Auto-Download Settings', accent: true }] },
  ] },
  Appearance: { sections: [
    { header: 'Color theme', rows: [{ title: 'Night Mode', value: 'System' }, { title: 'Chat Wallpaper' }] },
    { rows: [{ title: 'Text Size', value: 'Default' }, { title: 'Message Corners', value: 'Default' }] },
    { rows: [{ title: 'Animations', toggle: true }] },
  ] },
  'Power Saving': { sections: [
    { rows: [{ title: 'Power Saving Mode', value: 'Off' }] },
    { header: 'Resource-intensive processes', rows: [{ title: 'Autoplay Videos', toggle: true }, { title: 'Animated Stickers', toggle: true }, { title: 'Interface Effects', toggle: true }] },
  ] },
  Language: { sections: [
    { header: 'Interface language', rows: [{ title: 'English', value: '✓' }, { title: 'العربية' }, { title: 'Español' }, { title: 'Deutsch' }] },
    { rows: [{ title: 'Show Translate Button', toggle: true }] },
  ] },
  'Telegram Premium': { sections: [
    { rows: [{ title: 'Doubled Limits' }, { title: 'Voice-to-Text' }, { title: 'Faster Download Speed' }, { title: 'Real-Time Translation' }] },
  ] },
  'My Stars': { title: 'Stars', sections: [
    { rows: [{ title: 'Balance', value: '★ 250' }, { title: 'Buy More Stars', accent: true }] },
    { header: 'Transactions', rows: [{ title: 'Gift to Alex', value: '−50' }] },
  ] },
  'Telegram Business': { sections: [
    { rows: [{ title: 'Location' }, { title: 'Opening Hours' }, { title: 'Quick Replies' }, { title: 'Greeting Messages' }] },
  ] },
  'Send a Gift': { sections: [
    { header: 'Choose a friend', rows: [{ title: 'Alex Turner' }, { title: 'Mark Chen' }, { title: 'Omar' }] },
  ] },
  'Ask a Question': { title: 'Support', sections: [
    { rows: [{ title: 'Ask a Volunteer', accent: true }], footer: 'Please note that Telegram Support is done by volunteers.' },
  ] },
  'Telegram FAQ': { title: 'FAQ', sections: [
    { rows: [{ title: 'General' }, { title: 'Telegram Basics' }, { title: 'Groups and Channels' }, { title: 'Privacy and Security' }] },
  ] },
  'Telegram Features': { title: 'Features', sections: [
    { rows: [{ title: 'Chat Folders' }, { title: 'Stories' }, { title: 'Gifts' }, { title: 'Mini Apps' }] },
  ] },
  'Change Emoji Status': { title: 'Emoji Status', sections: [
    { rows: [{ title: 'Emoji Status' }, { title: 'Collectible Gifts' }] },
  ] },
  'Change Profile Color': { title: 'Profile Color', sections: [
    { rows: [{ title: 'Name' }, { title: 'Profile' }] },
  ] },
  'Change Profile Photo': { title: 'Profile Photo', sections: [
    { rows: [{ title: 'Choose from Gallery', accent: true }, { title: 'Take Photo', accent: true }, { title: 'Use an Emoji', accent: true }] },
  ] },
};

const SWITCH = (onState) => `<div class="ios-switch${onState ? ' on' : ''}"><div class="knob"></div></div>`;
const ROW = 50.33;          // vertical inset 15 + one 17 pt line (20.3) + 15
const SUBTITLE = 1 + 17.9;  // spacing 1 + a 15 pt line

// A pushed page: { el, backButton }.
export function buildSubPage({ device, title }) {
  const W = device.width;
  const S = device.statusBar;
  const spec = PAGES[title] || { sections: [{ rows: [{ title: 'Coming soon' }] }] };
  const page = el('div', 'sub-page', `left:0;top:0;width:${W}px;height:${device.height}px`);
  const navY = S + 10;
  const back = el('div', 'glass sub-back', `left:16px;top:${navY}px;width:44px;height:44px`, page, chevronLeft);
  el('div', 'sub-title t17 w600', `left:70px;right:70px;top:${S + 2}px;height:60px`, page, spec.title || title);
  const inset = Math.max(16, Math.floor((W - 674) / 2));
  let y = S + 60;
  spec.sections.forEach((sec, si) => {
    // ItemListUI glass insets: 24 above the first section, 28 above a header after a section,
    // 35 above a header-less card after a section; a header block is its text (15.5) + 13.
    if (sec.header) {
      y += si === 0 ? 24 : 28;
      el('div', 'sub-header', `left:${inset + 15}px;top:${y + 7}px`, page, sec.header.toUpperCase());
      y += 15.5 + 13;
    } else {
      y += si === 0 ? 24 : 35;
    }
    const heights = sec.rows.map((r) => ROW + (r.subtitle ? SUBTITLE : 0));
    const total = heights.reduce((a, b) => a + b, 0);
    const box = el('div', 'section', `left:${inset}px;width:${W - inset * 2}px;top:${y}px;height:${total}px`, page);
    let ry = 0;
    sec.rows.forEach((r, i) => {
      const h = heights[i];
      const row = el('div', `row sub-row${r.accent ? ' accent' : ''}${r.destructive ? ' destructive' : ''}`, `top:${ry}px;height:${h}px`, box);
      const tx = r.icon ? 59 : 16;
      if (r.icon) {
        const tile = el('div', 'sub-icon', `left:14px;top:${(h - 30) / 2}px;background:${r.icon.color};--tile:${r.icon.color}`, row);
        tile.innerHTML = `<svg viewBox="0 0 30 30" width="30" height="30">${G[r.icon.glyph] || ''}</svg>`;
      }
      el('div', 'title t17 w400', `left:${tx}px;top:15px;line-height:20.3px;height:20.3px`, row, r.title);
      if (r.subtitle) el('div', 'sub-subtitle', `left:${tx}px;top:${15 + 20.3 + 1}px`, row, r.subtitle);
      if (r.toggle !== undefined) el('div', 'sub-switch', `top:${(h - 28) / 2}px`, row, SWITCH(r.toggle));
      else if (r.value) el('div', 'value t17 w400', `right:34px;top:15px;line-height:20.3px;height:20.3px`, row, r.value);
      if (r.toggle === undefined && !r.accent && !r.destructive) {
        const d = el('span', 'mask-icon abs', `right:7px;top:${(h - 24) / 2}px;width:24px;height:24px;color:var(--tg-disclosure)`, row);
        const url = new URL('../../assets/icons/ic-disclosure.svg', import.meta.url).href;
        d.style.webkitMaskImage = `url("${url}")`;
        d.style.maskImage = `url("${url}")`;
      }
      if (i < sec.rows.length - 1) el('div', 'sep', `left:${tx}px`, row);
      ry += h;
    });
    y += total;
    if (sec.footer) {
      el('div', 'sub-footer', `left:${inset + 15}px;right:${inset + 15}px;top:${y + 7}px`, page, sec.footer);
      y += 7 + 15.5 * 2 + 4;
    }
  });
  return { el: page, backButton: back };
}
