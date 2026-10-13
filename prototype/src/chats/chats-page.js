// The Chats tab on iOS 26 (spec: research/telegram-ios/chat-list-swipe.md §5): no large title —
// a 44 pt row at SB + 10 with a glass "Edit" capsule, "Chats" (semibold 17) in the middle and one
// glass capsule with new-story + compose; under it a 44 pt search field that scrolls away over
// the first 54 pt (the list starts with it hidden); a fade instead of a bar. The chat list is
// chats/chat-list.js. Lives above the Settings page in the same screen; the tab bar switches.

import { ChatListScreen, ChatMetrics } from './chat-list.js';

function el(tag, cls, style, parent, html) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (style) e.style.cssText = style;
  if (html !== undefined) e.innerHTML = html;
  if (parent) parent.appendChild(e);
  return e;
}

// Chat List/ComposeIcon and Chat List/AddStoryIcon (30 × 30), redrawn.
const composeIcon = '<svg viewBox="0 0 30 30" width="30" height="30"><path d="M14.2 7.4H9.6a2.6 2.6 0 0 0-2.6 2.6v10.4a2.6 2.6 0 0 0 2.6 2.6H20a2.6 2.6 0 0 0 2.6-2.6v-4.6" fill="none" stroke="currentColor" stroke-width="1.66" stroke-linecap="round"/><path d="M21.3 6.3a1.9 1.9 0 0 1 2.7 2.7l-8.3 8.3-3.6.9.9-3.6z" fill="none" stroke="currentColor" stroke-width="1.66" stroke-linejoin="round"/></svg>';
const storyIcon = '<svg viewBox="0 0 30 30" width="30" height="30"><path d="M15 6.6a8.4 8.4 0 1 0 8.4 8.4" fill="none" stroke="currentColor" stroke-width="1.66" stroke-linecap="round"/><path d="M19.3 7.7a8.4 8.4 0 0 1 2.4 1.9M22.6 11.4a8.4 8.4 0 0 1 .7 2.2" fill="none" stroke="currentColor" stroke-width="1.66" stroke-linecap="round"/><path d="M15 11v8M11 15h8" stroke="currentColor" stroke-width="1.66" stroke-linecap="round"/></svg>';
const searchIcon = '<svg viewBox="0 0 24 24" width="24" height="24"><circle cx="10.6" cy="10.6" r="6.1" fill="none" stroke="currentColor" stroke-width="1.7"/><path d="M15.2 15.2l4.3 4.3" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg>';

export function buildChatsPage(screen, { device, dark, clock, photoURL, before = false }) {
  const W = device.width;
  const S = device.statusBar;
  const C = ChatMetrics.searchCollapse;
  // Built visible (hidden from view) so the rows can measure their text; app.js shows it.
  const page = el('div', 'chats-page', `left:0;top:0;width:${W}px;height:${device.height}px;visibility:hidden`, screen);
  const barH = S + 121;
  const navY = S + 10;

  // Fade behind the bar: list background @0.85 down to barH + 14, the last 54 pt fading
  // (EdgeEffect stops), moving up as the search field collapses.
  const fadeH = barH + 14;
  const stops = [[1, 0], [0.92, 0.23], [0.74, 0.38], [0.51, 0.49], [0.25, 0.62], [0.11, 0.73], [0, 1]];
  const band = Math.min(54, fadeH);
  const mask = stops.map(([a, u]) => `rgba(0,0,0,${a}) ${(fadeH - band + u * band).toFixed(1)}px`).join(',');
  const fade = el('div', 'chats-fade', `left:0;top:0;width:${W}px;height:${fadeH}px;will-change:transform;-webkit-mask-image:linear-gradient(180deg,#000 0,#000 ${fadeH - band}px,${mask});mask-image:linear-gradient(180deg,#000 0,#000 ${fadeH - band}px,${mask})`, page);

  // Search: node 60 tall at SB + 56, the 44 pt field 8 pt into it.
  const searchNode = el('div', 'chats-search-node', `left:16px;top:${S + 56}px;width:${W - 32}px;height:60px`, page);
  const field = el('div', 'chats-search', 'left:0;width:100%', searchNode);
  const placeholder = el('div', 'chats-search-text', '', field, `${searchIcon}<span>Search</span>`);

  const header = {
    barH,
    layout(offset) {
      const f = Math.max(0, Math.min(1, offset / C));
      const vp = Math.max(0, Math.min(1, (1 - f - 0.267) / 0.733));
      searchNode.style.transform = `translate3d(0,${(-8 * f).toFixed(2)}px,0)`;
      const h = 44 * vp;
      field.style.top = `${(8 + 44 - h).toFixed(2)}px`;
      field.style.height = `${h.toFixed(2)}px`;
      field.style.borderRadius = `${Math.min(22, h / 2).toFixed(2)}px`;
      field.style.opacity = (Math.min(0.3, vp) / 0.3).toFixed(3);
      placeholder.style.opacity = Math.max(0, Math.min(1, (vp - 0.77) / 0.23)).toFixed(3);
      // Pulled down past the top the header stays; the fade follows the collapse.
      fade.style.transform = `translate3d(0,${(-C * f).toFixed(2)}px,0)`;
    },
  };

  const chats = new ChatListScreen(page, { device, dark, clock, photoURL, header, before });
  page.appendChild(fade);         // above the list
  page.appendChild(searchNode);

  const edit = el('div', 'glass chats-edit', `left:16px;top:${navY}px;height:44px`, page, '<span>Edit</span>');
  const right = el('div', 'glass chats-buttons', `left:${W - 16 - 88}px;top:${navY}px;width:88px;height:44px`, page);
  el('div', 'chats-button', 'left:0', right, storyIcon);
  el('div', 'chats-button', 'left:44px', right, composeIcon);
  el('div', 'chats-title t17 w600', `left:0;top:${navY}px;width:${W}px;height:44px`, page, '<span style="transform:translateX(4px)">Chats</span>');
  header.layout(chats.scroller.offset);
  page.style.display = 'none';
  page.style.visibility = '';
  return { page, chats, edit };
}
