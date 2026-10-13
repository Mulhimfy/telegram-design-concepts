// Telegram iOS chat list (the Chats tab, iOS 26 design) with its swipe actions, ported from
// Telegram-iOS f1dd7a2 (spec with file:line refs: research/telegram-ios/chat-list-swipe.md):
//   · ChatListItem: the 76 pt row (avatar 60 at (16, 8), text column 86 … W − 16, baselines
//     23.33 / 23.0 / 43 / 63, badge at y 39); swiped, it becomes a rounded card (radius 26,
//     itemHighlightedBackgroundColor) that only moves;
//   · ItemListRevealOptionsItemNode (the gesture): axis lock at 4 pt with a 2.5 : 1 ratio, offset =
//     dx with no resistance; release under 100 pt/s opens if it started closed (or went past the
//     strip), faster follows the flick; one 0.6 s spring for everything (customSpring m 2, k 200,
//     c 100 squeezed into 0.6 s), finger velocity not carried;
//   · ItemListRevealOptionsNode (the circles): chats/reveal-options.js.
// New: Depth Swipe (chats/depth.js) — the name, the message and the photo go 3D while it moves.

import { Haptics } from '../core/haptics.js';
import { SpringParams, solveSpring } from '../core/spring.js';
import { VelocityTracker } from '../core/velocity.js';
import { Scroller } from '../core/scroller.js';
import { RevealOptions } from './reveal-options.js';
import { DepthRig } from './depth.js';
import { diag } from '../core/diag.js';
import { CHATS, AVATAR_GRADIENTS, initials } from './chat-data.js';
import { LottieIcon, lottie, loadAnimation } from './lottie-icon.js';

export const ChatMetrics = {
  rowH: 76,
  avatar: 60,
  avatarX: 16,
  avatarY: 8,
  textX: 86,
  rightInset: 16,
  titleTop: 7.14,   // line box 21 → baseline 23.33
  dateTop: 9.02,    // line box 18 → baseline 23.0
  textTop: 27.67,   // line boxes 20 → baselines 43 / 63
  badgeTop: 39,
  searchCollapse: 54,
};

// progress(t) of the reveal spring squeezed into 0.6 s (spec §1.4): 50 % at 65 ms, 90 % at 208 ms.
const REVEAL_DURATION = 0.6;
export function revealCurve(t) {
  if (t >= REVEAL_DURATION) return 1;
  const s = Math.max(0, t);
  return 1 - 1.0455 * Math.exp(-11.28 * s) + 0.0455 * Math.exp(-259 * s);
}

// The list's "system" curve (iOS 26 spring m 1, k 555.027, c 47.118) for rows moving / collapsing.
const LIST_SPRING = new SpringParams(1, 555.027, 47.118);
const listCurve = (t) => (t >= 0.4 ? 1 : 1 - solveSpring(LIST_SPRING, 1, 0, Math.max(0, t)).x);

const rgb = (hex) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255);

// theme.list.itemDisclosureActions (Night / Day, spec §4).
export function actionColors(dark) {
  return dark
    ? { neutral2: '#cd7800', destructive: '#c70c0c', constructive: '#08a723', accent: '#666666', inactive: '#666666', label: '#8d8e93' }
    : { neutral2: '#f09a37', destructive: '#ff3824', constructive: '#00c900', accent: '#0088ff', inactive: '#bcbcc3', label: '#8e8e93' };
}

// ChatListItem.revealOptions / leftRevealOptions (spec §2.2, §2.3).
function optionsFor(chat, C) {
  const label = rgb(C.label);
  const opt = (key, title, color, name, startFrame, extra = {}) => ({
    key, title, color: rgb(color), iconColor: [1, 1, 1], textColor: label,
    icon: { name, scale: 1, offset: 0, startFrame, ...extra },
  });
  const mute = chat.muted ? opt('unmute', 'Unmute', C.neutral2, 'anim_unmute', 3) : opt('mute', 'Mute', C.neutral2, 'anim_mute', 3, { replaceColors: [0xff9500] });
  const del = opt('delete', 'Delete', C.destructive, 'anim_delete', 3);
  const archive = opt('archive', 'Archive', C.inactive, 'anim_archive', 5, { offset: 2, replaceColors: [0xa9a9ad] });
  let right;
  if (chat.kind === 'saved') right = [del];
  else if (chat.kind === 'service') right = [mute, del];
  else right = [mute, del, archive];
  const left = [
    chat.unread ? opt('read', 'Read', C.inactive, 'anim_read', 5) : opt('unread', 'Unread', C.accent, 'anim_unread', 5, { replaceColors: [0x2194fa] }),
    chat.pinned ? opt('unpin', 'Unpin', C.constructive, 'anim_unpin', 5, { replaceColors: [0x1993fa] }) : opt('pin', 'Pin', C.constructive, 'anim_pin', 3),
  ];
  return { left, right };
}

function el(tag, cls, style, parent, html) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (style) e.style.cssText = style;
  if (html !== undefined) e.innerHTML = html;
  if (parent) parent.appendChild(e);
  return e;
}

const ICONS = {
  // PeerMutedIcon (24 pt box): a speaker with a slash.
  muted: '<svg viewBox="0 0 24 24" width="24" height="24"><path d="M8.2 10.1h1.5l2.6-2.2c.3-.3.8-.1.8.4v7.4c0 .5-.5.7-.8.4l-2.6-2.2H8.2a.7.7 0 0 1-.7-.7v-2.4c0-.4.3-.7.7-.7z" fill="currentColor"/><path d="M7.2 7.4l9.4 9.4" stroke="currentColor" stroke-width="1.25" stroke-linecap="round"/></svg>',
  verified: '<svg viewBox="0 0 16 16" width="16" height="16"><path d="M8 .9l1.6 1.2 2-.1.6 1.9 1.6 1.2-.6 1.9.6 1.9-1.6 1.2-.6 1.9-2-.1L8 15.1 6.4 13.9l-2 .1-.6-1.9-1.6-1.2.6-1.9-.6-1.9 1.6-1.2.6-1.9 2 .1z" fill="var(--tg-accent)"/><path d="M5.3 8.1l1.8 1.8 3.6-3.7" stroke="#fff" stroke-width="1.5" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  pinned: '<svg viewBox="0 0 20 20" width="20" height="20"><path d="M12.4 3.1l4.5 4.5c.3.3.2.7-.2.8l-1.6.5-2.6 2.6.3 2.8c0 .3-.1.5-.3.7l-.7.7c-.3.3-.7.3-1 0l-2.2-2.2-3.9 3.9c-.2.2-.5.2-.7 0-.2-.2-.2-.5 0-.7l3.9-3.9-2.2-2.2c-.3-.3-.3-.7 0-1l.7-.7c.2-.2.4-.3.7-.3l2.8.3 2.6-2.6.5-1.6c.1-.4.5-.5.8-.2z" fill="currentColor"/></svg>',
  read: '<svg viewBox="0 0 24 24" width="24" height="24"><path d="M3.8 12.6l3 3 6.4-7.4M11 15.4l.3.2 6.4-7.4" stroke="currentColor" stroke-width="1.33" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  sent: '<svg viewBox="0 0 24 24" width="24" height="24"><path d="M7.3 12.6l3 3 6.4-7.4" stroke="currentColor" stroke-width="1.33" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  saved: '<svg viewBox="0 0 60 60" width="60" height="60"><path d="M21 17.5h18c1.4 0 2.5 1.1 2.5 2.5v23.2c0 .9-1 1.4-1.7.9L30 37.3l-9.8 6.8c-.7.5-1.7 0-1.7-.9V20c0-1.4 1.1-2.5 2.5-2.5z" fill="#fff"/></svg>',
  telegram: '<svg viewBox="0 0 60 60" width="60" height="60"><path d="M15.5 29.2c7.3-3.2 12.2-5.3 14.6-6.3 7-2.9 8.4-3.4 9.4-3.4.2 0 .7.1 1 .3.3.2.3.5.4.7v.7c-.4 4-2 13.7-2.9 18.2-.4 1.9-1.1 2.5-1.8 2.6-1.5.1-2.6-1-4.1-2l-5.7-3.8c-2.5-1.7-.9-2.6.6-4.1.4-.4 6.8-6.2 6.9-6.7 0-.1 0-.3-.1-.4-.1-.1-.3-.1-.5 0-.2 0-3.6 2.3-10.1 6.7-1 .7-1.8 1-2.6 1-.9 0-2.5-.5-3.7-.9-1.5-.5-2.7-.7-2.6-1.5.1-.4.6-.8 1.6-1.2z" fill="#fff"/></svg>',
};

export class ChatListScreen {
  // header: { barH (search shown), search: { node, field, text } } — the search field collapses
  // over the first 54 pt of scrolling and the list starts with it collapsed.
  // before: Telegram as it is today (no Depth Swipe: the row slides flat).
  constructor(page, { device, dark, clock, header, photoURL, before = false }) {
    this.before = before;
    this.page = page;
    this.device = device;
    this.dark = dark;
    this.clock = clock;
    this.W = device.width;
    this.H = device.height;
    this.C = actionColors(dark);
    this.photoURL = photoURL;
    this.header = header;
    this.top = header.barH;                 // first row, content coordinates
    this.list = el('div', 'abs', `left:0;top:0;width:${this.W}px;height:${this.H}px;will-change:transform`, page);
    this.rows = CHATS.map((c, i) => new ChatRow(this, { ...c }, i));
    this.order = this.rows.slice();
    this.scroller = new Scroller({ viewport: this.H - this.top, content: 0 });
    this.layoutRows(null);
    this.scroller.offset = ChatMetrics.searchCollapse;    // launch: search scrolled away
    this.touch = null;
    this.tracker = new VelocityTracker(0.08);
    this.openRow = null;
    this.toast = null;
    this.lastNow = clock.now();
    this.timers = [];
    this.laid = null;
    // The icons are fetched before the first swipe needs them (no empty circles on a phone).
    setTimeout(() => {
      lottie().catch(() => {});
      for (const n of ['anim_mute', 'anim_unmute', 'anim_delete', 'anim_archive', 'anim_read', 'anim_unread', 'anim_pin', 'anim_unpin', 'anim_archiveswipe']) loadAnimation(n).catch(() => {});
    }, 600);
  }

  // Callbacks on the page clock (frame-exact in recordings).
  after(delay, fn) {
    this.timers.push({ at: this.lastNow + delay, fn });
  }

  // Rows at their places in the current order (animated when `now` is given).
  layoutRows(now) {
    let y = this.top;
    this.order.forEach((r, i) => {
      r.place(y, now);
      const next = this.order[i + 1];
      r.setSeparator(!next ? 'full' : r.chat.pinned && !next.chat.pinned ? 'full' : 'inset');
      y += ChatMetrics.rowH;
    });
    const bottom = (this.device.bottomInset || 0) + 20 + 64 + 8;
    this.scroller.content = this.order.length * ChatMetrics.rowH + bottom + ChatMetrics.searchCollapse;
  }

  rowAt(p) {
    const y = p[1] + this.scroller.offset;
    return this.order.find((r) => y >= r.y && y < r.y + ChatMetrics.rowH && !r.removing) || null;
  }

  // ---------------------------------------------------------------- input (screen pt)

  down(p, now) {
    this.tracker.reset();
    this.tracker.add(now, p[0], p[1]);
    if (this.toast && this.toast.hit(p)) {
      this.touch = { kind: 'toast', start: p, last: p };
      return;
    }
    const barBottom = this.top - Math.min(ChatMetrics.searchCollapse, Math.max(0, this.scroller.offset));
    const row = p[1] > barBottom ? this.rowAt(p) : null;
    const t = { kind: 'pending', start: p, last: p, row, t0: now };
    this.touch = t;
    if (this.scroller.moving) {
      this.scroller.stop();   // a touch catches the list; it doesn't select
      t.caught = true;
    }
    // Touching another row closes the open one; that touch can still swipe.
    if (this.openRow && this.openRow !== row) {
      this.openRow.close(now);
      t.caught = true;
    }
    if (row && row.offsetModel !== 0) {
      t.option = row.optionAt(p[0]);
    } else if (row && !t.caught) {
      const h = { cancelled: false };
      t.highlight = h;
      this.after(0.08, () => { if (!h.cancelled) row.setHighlighted(true); });
    }
  }

  move(p, now) {
    const t = this.touch;
    if (!t) return;
    this.tracker.add(now, p[0], p[1]);
    t.last = p;
    const dx = p[0] - t.start[0];
    const dy = p[1] - t.start[1];
    if (t.kind === 'pending') {
      const vertical = Math.abs(dy) > 4 && Math.abs(dy) > Math.abs(dx) * 2.5;
      const horizontal = Math.abs(dx) > 4 && Math.abs(dy) * 2.5 < Math.abs(dx);
      if (t.row && horizontal) {
        t.kind = 'swipe';
        this.cancelHighlight(t);
        t.row.beginSwipe(p[0], now);
        if (this.openRow && this.openRow !== t.row) this.openRow.close(now);
        this.openRow = t.row;
      } else if ((vertical && Math.abs(dy) > 8) || (!t.row && Math.hypot(dx, dy) > 8)) {
        t.kind = 'scroll';
        this.cancelHighlight(t);
        if (this.openRow) { this.openRow.close(now); }
        this.scroller.begin(p[1]);
      }
    }
    if (t.kind === 'swipe') t.row.trackSwipe(p[0], now);
    else if (t.kind === 'scroll') this.scroller.drag(p[1]);
  }

  up(p, now, cancelled) {
    const t = this.touch;
    if (!t) return;
    this.touch = null;
    const v = this.tracker.velocity(now);
    this.cancelHighlight(t);
    if (t.kind === 'toast') {
      if (!cancelled && this.toast?.hit(p)) this.toast.tap(now);
      return;
    }
    if (t.kind === 'swipe') {
      t.row.endSwipe(cancelled ? 0 : v.x, now);
      return;
    }
    if (t.kind === 'scroll') {
      this.scroller.end(cancelled ? 0 : v.y, now);
      this.snapSearch(now);
      return;
    }
    if (cancelled || t.caught) return;
    const row = t.row;
    if (!row) return;
    if (t.option) row.select(t.option.key, now);
    else if (row.offsetModel !== 0) row.close(now);
    else {
      row.flash(now);
      this.onOpen?.(row.chat, now);   // the prototype opens the chat's profile (its Gifts)
    }
  }

  // A rest between the search field's open and closed positions snaps to the nearer one.
  snapSearch(now) {
    const S = ChatMetrics.searchCollapse;
    const s = this.scroller;
    const settle = () => {
      if (s.mode === 'idle' && s.offset > 0 && s.offset < S) s.springTo(s.offset < S / 2 ? 0 : S, 0, this.lastNow, 0.35);
    };
    if (s.mode === 'decel') {
      const d = s.decel;
      const rest = d.o0 + d.v0 / (-1000 * Math.log(0.998)) / 1000;
      if (rest > 0 && rest < S) s.springTo(rest < S / 2 ? 0 : S, d.v0, now, 0.4);
    } else settle();
  }

  cancelHighlight(t) {
    if (t.highlight) { t.highlight.cancelled = true; t.highlight = null; }
    if (t.row && t.kind !== 'pending') t.row.setHighlighted(false);
  }

  // ---------------------------------------------------------------- actions

  // Archive / delete: the row has slid out; it collapses (0.4 s, no fade) and a toast offers Undo.
  removeRow(row, delay, text) {
    const index = this.order.indexOf(row);
    row.removing = true;
    if (this.openRow === row) this.openRow = null;
    this.after(delay, () => {
      this.order = this.order.filter((r) => r !== row);
      row.root.style.visibility = 'hidden';
      this.layoutRows(this.lastNow);
      this.showToast(text, this.lastNow, () => {
        row.removing = false;
        row.resetAfterRemoval();
        this.order.splice(Math.min(index, this.order.length), 0, row);
        row.root.style.visibility = '';
        row.appear(this.lastNow);
        this.layoutRows(this.lastNow);
      });
    });
  }

  showToast(text, now, undo) {
    this.toast?.dismiss(now, true);
    this.toast = new UndoToast(this.page, { device: this.device, text, undo, now, onGone: (t) => { if (this.toast === t) this.toast = null; } });
  }

  // ---------------------------------------------------------------- frame

  update(now) {
    const dt = Math.max(0, Math.min(0.05, now - this.lastNow));
    this.lastNow = now;
    const due = this.timers.filter((t) => t.at <= now);
    if (due.length) {
      this.timers = this.timers.filter((t) => t.at > now);
      for (const t of due) t.fn();
    }
    let busy = this.scroller.update(now) || this.timers.length > 0;
    if (this.scroller.mode === 'idle' && !this.scroller.tracking && !this.touch) {
      const o = this.scroller.offset;
      if (o > 0 && o < ChatMetrics.searchCollapse) this.snapSearch(now);
    }
    const o = this.scroller.offset;
    if (o !== this.laid) {
      this.laid = o;
      this.list.style.transform = `translate3d(0,${(-o).toFixed(2)}px,0)`;
      this.header.layout(o);
    }
    for (const r of this.rows) busy = r.update(now, dt) || busy;
    if (this.toast) busy = this.toast.update(now) || busy;
    return busy || !!this.touch;
  }
}

// ------------------------------------------------------------------ a row

class ChatRow {
  constructor(list, chat, index) {
    this.list = list;
    this.chat = chat;
    this.index = index;
    this.W = list.W;
    this.offset = 0;          // presented
    this.offsetModel = 0;     // where it is going
    this.anim = null;
    this.tracking = false;
    this.sides = { left: null, right: null };
    this.y = 0;
    this.yAnim = null;
    this.prevX = 0;
    this.vel = 0;
    this.highlighted = false;
    this.build();
  }

  build() {
    const M = ChatMetrics;
    const L = this.list;
    const chat = this.chat;
    const H = M.rowH;
    const root = el('div', 'chat-row', `left:0;top:0;width:${this.W}px;height:${H}px`, L.list);
    this.root = root;
    this.bg = el('div', 'chat-bg', `left:0;top:0;width:${this.W}px;height:${H}px`, root);
    this.sep = el('div', 'chat-sep', '', root);
    // The card: the highlight node, 1px taller to cover the hairline above.
    this.card = el('div', 'chat-card', `left:0;top:-1px;width:${this.W}px;height:${H + 1}px;opacity:0`, root);
    this.content = el('div', 'chat-content', `left:0;top:0;width:${this.W}px;height:${H}px`, root);
    // avatar
    const av = el('div', 'chat-avatar', `left:${M.avatarX}px;top:${M.avatarY}px;width:${M.avatar}px;height:${M.avatar}px`, this.content);
    const pic = el('div', 'avatar-pic', '', av);
    if (chat.photo) {
      const img = el('img', '', 'width:100%;height:100%;object-fit:cover;display:block', pic);
      img.src = L.photoURL(chat.photo);
      img.draggable = false;
      this.avatarColor = null;
      img.onload = () => { this.avatarColor = meanColor(img); };
    } else {
      const g = chat.kind === 'saved' || chat.kind === 'service' ? AVATAR_GRADIENTS[5] : AVATAR_GRADIENTS[(chat.avatar ?? 0) % AVATAR_GRADIENTS.length];
      pic.style.background = `linear-gradient(180deg, ${g[1]}, ${g[0]})`;
      if (chat.kind === 'saved') pic.innerHTML = ICONS.saved;
      else if (chat.kind === 'service') pic.innerHTML = ICONS.telegram;
      else el('span', 'avatar-initials', '', pic, initials(chat.title));
      this.avatarColor = rgb(g[0]);
    }
    this.avatar = av;
    // title + icons
    const titleRow = el('div', 'chat-title', `left:${M.textX}px;top:${M.titleTop}px`, this.content);
    this.titleText = el('span', 'chat-title-text', '', titleRow);
    this.titleText.textContent = chat.title;
    if (chat.verified) el('span', 'chat-icon verified', '', titleRow, ICONS.verified);
    this.muteIcon = el('span', 'chat-icon muted', '', titleRow, ICONS.muted);
    // date + read checks (right-aligned to W − 16)
    const meta = el('div', 'chat-meta', `right:${M.rightInset}px;top:${M.dateTop}px`, this.content);
    if (chat.out) el('span', 'chat-check', '', meta, chat.out === 'read' ? ICONS.read : ICONS.sent);
    el('span', 'chat-date', '', meta, chat.date);
    // message (groups: the author on the first line, the message on the second)
    this.textBox = el('div', 'chat-text', `left:${M.textX}px;top:${M.textTop}px;width:${this.W - M.textX - M.rightInset - 26}px`, this.content);
    this.renderText();
    this.badge = el('div', 'chat-badge', `right:${M.rightInset}px;top:${M.badgeTop}px`, this.content);
    this.pin = el('div', 'chat-pin', `right:${M.rightInset}px;top:${M.badgeTop}px`, this.content, ICONS.pinned);
    this.updateBadge();
  }

  renderText() {
    const chat = this.chat;
    const box = this.textBox;
    box.textContent = '';
    const lines = [];
    const fill = (line, text, maxLines) => {
      // Word spans, wrapped by the browser, cut to maxLines with an ellipsis (TextNode .end).
      const words = [];
      const probe = el('div', 'chat-flow', '', box);
      for (const w of text.split(/(\s+)/)) {
        if (!w) continue;
        if (/^\s+$/.test(w)) { probe.appendChild(document.createTextNode(' ')); continue; }
        const s = el('span', 'chat-word', '', probe);
        s.textContent = w;
        words.push(s);
      }
      const maxBottom = 20 * maxLines + 1;
      let last = words.length - 1;
      while (last > 0 && words[last].offsetTop + words[last].offsetHeight > maxBottom) last--;
      const cut = last < words.length - 1;
      const keep = words.slice(0, last + 1);
      if (cut) {
        const w = keep[keep.length - 1];
        w.textContent += '…';
        while (w.offsetTop + w.offsetHeight > maxBottom && w.textContent.length > 2) w.textContent = `${w.textContent.slice(0, -2)}…`;
      }
      // Group the kept words by visual line; each line becomes its own block.
      const groups = [];
      for (const w of keep) {
        const top = w.offsetTop;
        let g = groups.find((x) => Math.abs(x.top - top) < 4);
        if (!g) { g = { top, words: [] }; groups.push(g); }
        g.words.push(w);
      }
      probe.remove();
      for (const g of groups) {
        const l = el('div', `chat-line${line ? ` ${line}` : ''}`, '', box);
        g.words.forEach((w, i) => {
          if (i > 0) l.appendChild(document.createTextNode(' '));
          l.appendChild(w);
        });
        lines.push(l);
      }
    };
    if (chat.author) {
      fill('author', chat.author, 1);
      fill(chat.textColor === 'accent' ? 'accent' : '', chat.text, 1);
    } else {
      fill(chat.textColor === 'accent' ? 'accent' : '', chat.text, 2);
    }
    this.lines = lines;
  }

  updateBadge() {
    const chat = this.chat;
    this.badge.textContent = chat.unread ? String(chat.unread) : '';
    this.badge.style.display = chat.unread ? '' : 'none';
    this.badge.classList.toggle('muted', !!chat.muted);
    this.pin.style.display = !chat.unread && chat.pinned ? '' : 'none';
    this.muteIcon.style.display = chat.muted ? '' : 'none';
    this.root.classList.toggle('pinned', !!chat.pinned);
  }

  setSeparator(kind) {
    this.sep.classList.toggle('full', kind === 'full');
  }

  place(y, now) {
    if (now == null || this.y === y) {
      this.y = y;
      this.yAnim = null;
      this.root.style.top = `${y}px`;
      return;
    }
    const from = this.yAnim ? this.yAnimValue : this.y;
    this.yAnim = { from, to: y, t0: now };
    this.yAnimValue = from;
    this.y = y;
  }

  appear(now) {
    this.appearT0 = now;
  }

  resetAfterRemoval() {
    this.offset = 0;
    this.offsetModel = 0;
    this.anim = null;
    this.depth?.end();
    for (const k of ['left', 'right']) this.dropSide(k);
    this.content.style.transform = '';
    this.card.style.opacity = '0';
  }

  // ---------------------------------------------------------------- swipe

  beginSwipe(x, now) {
    this.tracking = true;
    this.trackX0 = x;
    // Caught mid-animation: it continues from where it is.
    if (this.anim) {
      this.offsetModel = this.offset;
      this.anim = null;
    }
    this.initial = this.offsetModel;
    this.depthStart(now);
  }

  trackSwipe(x, now) {
    const opts = optionsFor(this.chat, this.list.C);
    let offset = this.initial + (x - this.trackX0);
    if (!opts.left.length) offset = Math.min(0, offset);
    this.setOffset(offset, now, false);
  }

  endSwipe(vx, now) {
    this.tracking = false;
    diag('swipe', { title: this.chat.title, x: Math.round(this.offsetModel), vx: Math.round(vx), rig: !!this.depth?.active, glyphs: this.depth?.glyphs?.length || 0 });
    const side = this.offsetModel > 0 ? 'left' : this.offsetModel < 0 ? 'right' : null;
    if (!side) { if (this.list.openRow === this) this.list.openRow = null; return; }
    const node = this.sides[side];
    const width = node ? node.width : 0;
    let reveal;
    if (side === 'left') reveal = Math.abs(vx) < 100 ? (this.initial === 0 && this.offsetModel > 0) || this.offsetModel > width : vx > 0;
    else reveal = Math.abs(vx) < 100 ? (this.initial === 0 && this.offsetModel < 0) || this.offsetModel < -width : vx < 0;
    if (reveal && node && node.displaysExtendedAction) {
      const option = side === 'left' ? node.options[0] : node.options[node.count - 1];
      this.select(option.key, now);
      return;
    }
    this.setOffset(reveal ? (side === 'left' ? width : -width) : 0, now, true);
    if (!reveal && this.list.openRow === this) this.list.openRow = null;
  }

  close(now) {
    if (this.offsetModel === 0 && !this.anim) return;
    this.setOffset(0, now, true);
    if (this.list.openRow === this) this.list.openRow = null;
  }

  ensureSide(side) {
    if (this.sides[side]) return this.sides[side];
    const opts = optionsFor(this.chat, this.list.C)[side];
    if (!opts.length) return null;
    const node = new RevealOptions(this.root, {
      options: opts,
      isLeft: side === 'left',
      height: ChatMetrics.rowH,
      haptic: (armed) => {
        Haptics.impact('medium');
        if (armed) this.depth?.spin(this.list.lastNow, side === 'left' ? 1 : -1);
      },
    });
    // The strip sits behind the card (the content moves over it).
    this.root.insertBefore(node.root, this.card);
    this.sides[side] = node;
    return node;
  }

  dropSide(side) {
    const node = this.sides[side];
    if (!node) return;
    node.root.remove();
    node.nodes.forEach((n) => n.lottie?.destroy());
    this.sides[side] = null;
  }

  // updateRevealOffsetInternal: immediate (the finger) or animated (the reveal spring: every
  // derived value runs from where it is to its target, as Core Animation does).
  setOffset(offset, now, animated, done) {
    if (offset > 0) this.ensureSide('left');
    if (offset < 0) this.ensureSide('right');
    // A row that moves on its own (a tap closing it, an action closing it, another row taking
    // the touch) goes 3D the same way as under the finger.
    if (animated && Math.abs(offset - this.offset) > 0.5) this.depthStart(now);
    if (!animated) {
      this.anim = null;
      this.offsetModel = offset;
      this.offset = offset;
      if (offset <= 0 && this.sides.left) this.dropSide('left');
      if (offset >= 0 && this.sides.right) this.dropSide('right');
      return;
    }
    const layouts = {};
    for (const side of ['left', 'right']) {
      const node = this.sides[side];
      if (!node) continue;
      const d1 = side === 'left' ? Math.max(0, offset) : Math.max(0, -offset);
      layouts[side] = { from: node.lastLayout || node.layout(0, 0), to: node.layout(d1, d1) };
      node.stepVisual(d1, 0, true);
    }
    this.anim = {
      from: this.offset, to: offset, t0: now, layouts, done,
      cardFrom: this.cardState(), closing: offset === 0,
    };
    this.offsetModel = offset;
  }

  optionAt(x) {
    const side = this.offsetModel > 0 ? 'left' : 'right';
    const node = this.sides[side];
    if (!node) return null;
    const rootX = parseFloat(node.root.style.left || '0');
    const i = node.hit(x - rootX, 0);
    return i >= 0 ? { side, index: i, key: node.options[i].key } : null;
  }

  // revealOptionSelected (ChatListItem, spec §2.5).
  select(key, now) {
    const chat = this.chat;
    const L = this.list;
    if (key === 'archive') {
      // animateRevealOptionsFill: the card leaves to −W − 74 and the capsule fills the row.
      this.setOffset(-this.W - 74, now, true);
      L.removeRow(this, 0.3, 'Chat archived');
      return;
    }
    if (key === 'delete') {
      this.close(now);
      L.removeRow(this, 0.32, 'Chat deleted');
      return;
    }
    if (key === 'mute' || key === 'unmute' || key === 'read' || key === 'unread') {
      // Stays open until the toggle lands, then closes.
      L.after(0.12, () => {
        if (key === 'mute' || key === 'unmute') chat.muted = key === 'mute';
        else chat.unread = key === 'unread' ? 1 : 0;
        this.updateBadge();
        this.close(L.lastNow);
      });
      return;
    }
    if (key === 'pin' || key === 'unpin') {
      this.close(now);
      chat.pinned = key === 'pin';
      this.updateBadge();
      L.after(0.3, () => {
        L.order = L.order.filter((r) => r !== this);
        const firstUnpinned = L.order.findIndex((r) => !r.chat.pinned);
        L.order.splice(chat.pinned ? 0 : (firstUnpinned < 0 ? L.order.length : firstUnpinned), 0, this);
        L.layoutRows(L.lastNow);
      });
    }
  }

  setHighlighted(on) {
    this.highlighted = on;
    this.highlightT0 = on ? null : this.list.lastNow;
  }

  flash() {
    this.setHighlighted(true);
    this.list.after(0.1, () => this.setHighlighted(false));
  }

  // The card's look now: { alpha, radius }.
  cardState() {
    return { alpha: parseFloat(this.card.style.opacity || '0'), radius: parseFloat(this.card.style.borderRadius || '0') };
  }

  // ---------------------------------------------------------------- Depth Swipe

  depthStart(now) {
    if (this.list.before) return;
    if (!this.depth) {
      this.depth = new DepthRig({
        title: this.titleText,
        icons: [...this.titleText.parentElement.querySelectorAll('.chat-icon')],
        lines: this.lines,
        avatar: this.avatar,
        avatarColor: this.avatarColor || [0.35, 0.4, 0.45],
        dark: this.list.dark,
      });
    }
    this.depth.begin(now);
  }

  // ---------------------------------------------------------------- frame

  update(now, dt) {
    let busy = false;
    if (this.yAnim) {
      const a = this.yAnim;
      const e = listCurve(now - a.t0);
      this.yAnimValue = a.from + (a.to - a.from) * e;
      this.root.style.top = `${this.yAnimValue.toFixed(2)}px`;
      if (now - a.t0 >= 0.4) { this.root.style.top = `${a.to}px`; this.yAnim = null; } else busy = true;
    }
    if (this.appearT0 != null) {
      const u = Math.min(1, (now - this.appearT0) / 0.3);
      this.root.style.opacity = u.toFixed(3);
      if (u >= 1) { this.appearT0 = null; this.root.style.opacity = ''; } else busy = true;
    }
    // presented offset
    let p = 1;
    if (this.anim) {
      const a = this.anim;
      p = revealCurve(now - a.t0);
      this.offset = a.from + (a.to - a.from) * p;
      if (now - a.t0 >= REVEAL_DURATION) {
        this.offset = a.to;
        this.anim = null;
        if (a.to === 0) {
          // Closed: the circles go and their icons rewind (clipping frame completion).
          for (const k of ['left', 'right']) if (this.sides[k]) { this.sides[k].resetAnimations(); this.dropSide(k); }
        } else {
          if (a.to > 0) this.dropSide('right');
          if (a.to < 0) this.dropSide('left');
        }
        a.done?.();
      }
      busy = true;
    }
    const x = this.offset;
    const tr = x === 0 ? '' : `translate3d(${x.toFixed(2)}px,0,0)`;
    if (this.content.style.transform !== tr) this.content.style.transform = tr;
    if (this.card.style.transform !== tr) this.card.style.transform = tr;
    // The card: active (radius 26, at once) while the options are out; on close it fades and
    // loses its radius on the same spring; a tap shows it full-bleed (0.3 s fade out).
    const active = this.offsetModel !== 0 || (this.anim && !this.anim.closing);
    let alpha;
    let radius;
    if (this.anim && this.anim.closing) {
      alpha = this.anim.cardFrom.alpha * (1 - p);
      radius = this.anim.cardFrom.radius * (1 - p);
    } else if (active || (this.tracking && x !== 0)) {
      alpha = 1;
      radius = 26;
    } else if (this.highlighted) {
      alpha = 1;
      radius = 0;
    } else if (this.highlightT0 != null) {
      const u = Math.min(1, (now - this.highlightT0) / 0.3);
      alpha = (1 - (u < 0.5 ? 2 * u * u : 1 - Math.pow(-2 * u + 2, 2) / 2)) * (this.card.style.borderRadius === '0px' ? 1 : 0);
      radius = 0;
      if (u >= 1) this.highlightT0 = null; else busy = true;
    } else {
      alpha = 0;
      radius = 0;
    }
    const av = alpha < 0.003 ? '0' : alpha.toFixed(3);
    if (this.card.style.opacity !== av) this.card.style.opacity = av;
    const rv = `${radius.toFixed(2)}px`;
    if (this.card.style.borderRadius !== rv) this.card.style.borderRadius = rv;
    const sepHidden = x !== 0 || this.offsetModel !== 0;
    this.sepHidden = sepHidden;
    const prev = this.list.order[this.list.order.indexOf(this) - 1];
    const hideSep = sepHidden || !!this.nextHides;
    const sv = hideSep ? '0' : '1';
    if (this.sep.style.opacity !== sv) this.sep.style.opacity = sv;
    if (prev) prev.nextHides = sepHidden;
    // the options on each side
    for (const side of ['left', 'right']) {
      const node = this.sides[side];
      if (!node) continue;
      const left = side === 'left' ? Math.min(x - node.width, 0) : Math.min(this.W, this.W + x);
      const lv = `${left.toFixed(2)}px`;
      if (node.root.style.left !== lv) node.root.style.left = lv;
      const d = side === 'left' ? Math.max(0, x) : Math.max(0, -x);
      let layout;
      if (this.anim && this.anim.layouts[side]) {
        const ls = this.anim.layouts[side];
        layout = RevealOptions.mix(ls.from, ls.to, p);
        busy = node.apply(layout, now, dt, { interactive: false, final: ls.to }) || busy;
      } else {
        if (node.stepVisual(d, dt, false)) busy = true;
        layout = node.layout(d, node.visual.d);
        busy = node.apply(layout, now, dt, { interactive: this.tracking }) || busy;
      }
      node.lastLayout = layout;
    }
    // Depth Swipe: driven by where the row is and how fast it moves.
    const v = dt > 0 ? (x - this.prevX) / dt : 0;
    this.vel = this.vel * 0.45 + v * 0.55;
    this.prevX = x;
    if (this.depth && this.depth.active) {
      let moving = false;
      try {
        moving = this.depth.update(now, x, this.vel, this.tracking ? x - this.initial : 0);
      } catch (e) {
        // A broken frame must never stop the list: report it and fall back to the flat row.
        diag('depth-error', { msg: String(e && e.message), stack: String(e && e.stack).slice(0, 400) });
        try { this.depth.end(); } catch (_) {}
      }
      const still = !this.tracking && !this.anim && Math.abs(this.vel) < 1;
      // Settled flat: back to the flat DOM. Settled open with pieces round the rim: it stays.
      if (!moving && still) { if (!this.depth.rolled) this.depth.end(); } else busy = true;
    }
    return busy || this.tracking;
  }
}

function meanColor(img) {
  try {
    const c = document.createElement('canvas');
    c.width = 8; c.height = 8;
    const g = c.getContext('2d');
    g.drawImage(img, 0, 0, 8, 8);
    const d = g.getImageData(0, 0, 8, 8).data;
    let r = 0, gg = 0, b = 0;
    for (let i = 0; i < d.length; i += 4) { r += d[i]; gg += d[i + 1]; b += d[i + 2]; }
    const n = d.length / 4;
    return [r / n / 255, gg / n / 255, b / n / 255];
  } catch (_) {
    return [0.35, 0.4, 0.45];
  }
}

// ------------------------------------------------------------------ undo toast

// UndoOverlayController, iOS 26: a glass capsule over the tab bar with the archive icon, the
// text, "Undo" and a 5 s countdown ring.
class UndoToast {
  constructor(page, { device, text, undo, now, onGone }) {
    this.undoFn = undo;
    this.onGone = onGone;
    this.t0 = now;
    this.life = 5;
    const W = device.width;
    const bottom = 20 + 64 + 10 + (device.bottomInset > 30 ? 0 : 0);
    this.h = 50;
    this.x = 12;
    this.w = W - 24;
    this.y = device.height - bottom - this.h;
    this.root = el('div', 'undo-toast glass', `left:${this.x}px;top:${this.y}px;width:${this.w}px;height:${this.h}px;z-index:35;opacity:0;transform:translateY(16px) scale(0.96)`, page);
    const icon = el('div', 'undo-icon', '', this.root);
    this.icon = new LottieIcon(icon, { name: 'anim_archiveswipe' });
    el('div', 'undo-text', '', this.root, text);
    this.button = el('div', 'undo-button', '', this.root, 'Undo');
    this.ring = el('div', 'undo-ring', '', this.root, '<svg viewBox="0 0 24 24" width="24" height="24"><circle cx="12" cy="12" r="10" fill="none" stroke="currentColor" stroke-width="2" stroke-dasharray="62.83" stroke-dashoffset="0" transform="rotate(-90 12 12)"/></svg><span>5</span>');
    this.ringCircle = this.ring.querySelector('circle');
    this.ringText = this.ring.querySelector('span');
    this.state = 'in';
    this.icon.play(now);
  }

  hit(p) {
    return this.state !== 'out' && p[0] >= this.x && p[0] <= this.x + this.w && p[1] >= this.y && p[1] <= this.y + this.h;
  }

  tap(now) {
    this.undoFn?.();
    this.dismiss(now);
  }

  dismiss(now, instant = false) {
    if (this.state === 'out') return;
    this.state = 'out';
    this.tOut = now;
    if (instant) { this.root.remove(); this.onGone(this); }
  }

  update(now) {
    this.icon.update(now);
    if (this.state === 'out') {
      const u = Math.min(1, (now - this.tOut) / 0.25);
      this.root.style.opacity = (1 - u).toFixed(3);
      this.root.style.transform = `translateY(${(u * 16).toFixed(1)}px) scale(${(1 - 0.04 * u).toFixed(3)})`;
      if (u >= 1) { this.root.remove(); this.onGone(this); return false; }
      return true;
    }
    const age = now - this.t0;
    const u = Math.min(1, age / 0.35);
    const e = 1 - Math.pow(1 - u, 3);
    this.root.style.opacity = e.toFixed(3);
    this.root.style.transform = `translateY(${((1 - e) * 16).toFixed(1)}px) scale(${(0.96 + 0.04 * e).toFixed(3)})`;
    const left = Math.max(0, this.life - age);
    this.ringCircle.setAttribute('stroke-dashoffset', (62.83 * (1 - left / this.life)).toFixed(2));
    const s = String(Math.ceil(left));
    if (this.ringText.textContent !== s) this.ringText.textContent = s;
    if (left <= 0) this.dismiss(now);
    return true;
  }
}
