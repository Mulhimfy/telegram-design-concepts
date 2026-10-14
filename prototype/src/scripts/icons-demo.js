// Living Icons demo (?demo=icons): open a Settings row and come back — its icon comes alive;
// close-ups in slow motion (each after tapping its row and coming back) of the parts moving (the padlock's shackle, the bell's clapper, the
// battery's charge jolting, the Premium star's arms, the person in My Profile); then every icon of every
// section in a wave.

import { timeline } from './kit.js';
import { LivingIcons } from '../settings/living-icons.js';

export function livingIconsDemo(ctx) {
  if (ctx.before) return livingIconsBefore(ctx);
  const { ui, W, scroll, nav, living } = ctx;
  const k = timeline();
  const row = (title) => ui.rows.find((r) => (r.title?.firstChild?.textContent || r.id) === title || r.id === title);
  const rowAt = (title, x = 200) => () => { const r = row(title); return [x, r.y - scroll.offset + r.h / 2]; };
  const iconAt = (title) => () => ctx.centerOf(row(title).tile || row(title).glyph);
  const BASE = { zoom: 1.0, focus: [W / 2, 0], anchor: [539.5, 97] };
  // The icon column with the titles beside it.
  const column = (title, zoom = 1.7) => () => { const c = iconAt(title)(); return { zoom, focus: [c[0] + 118, c[1]], anchor: [540, 520] }; };
  // One icon, close.
  const closeUp = (title, zoom = 3.6) => () => { const c = iconAt(title)(); return { zoom, focus: [c[0] + 34, c[1]], anchor: [540, 520] }; };

  // Scroll the list by dragging it (finger 1:1, let go at rest).
  const scrollBy = (d, duration = 0.95) => {
    k.gesture({ from: [250, d > 0 ? 700 : 260], path: [[250, (d > 0 ? 700 : 260) - d]], hold: 0.08, duration, ease: 'inOut', after: 0.05 });
    k.wait(0.25);
  };
  // The page that opens, from its title down (closer in, a short page is mostly empty black).
  const PAGE = { zoom: 1.3, focus: [W / 2, 0], anchor: [540, 90] };
  // Open its page, come back: the icon plays as the page leaves. With `close`, the camera pulls back to the
  // page while it is open and zooms into the icon as you come back.
  const visit = (title, { stay = 0.85, slow = null, after = 1.45, close = false } = {}) => {
    let target = null;
    if (close) k.call(() => { target = closeUp(title)(); });   // where the icon is, at rest
    k.tap(rowAt(title));
    if (close) k.camera(PAGE, 0.6);
    k.wait(0.6 + stay);
    k.tap(() => ctx.centerOf(nav.top.backButton));
    if (close) k.camera(() => target, 0.6);
    if (slow) {
      k.wait(0.14);
      k.speed(slow, 0.2);
    }
    k.wait(after);
    if (slow) k.speed(1, 0.2);
  };
  // Every icon in view, one after another (each with its own player, so they overlap).
  const players = new Map();
  ctx.addUpdater((now) => { let busy = false; for (const p of players.values()) busy = p.update(now) || busy; return busy; });
  const wave = (titles, gap = 0.2, after = 1.4) => {
    titles.forEach((title, i) => {
      k.at(k.t + i * gap, { call: ({ now }) => {
        let p = players.get(title);
        if (!p) { p = new LivingIcons({ iconURL: ctx.iconURL }); players.set(title, p); }
        p.play(row(title), now);
      } });
    });
    k.wait(titles.length * gap + after);
  };

  k.camera(BASE, 0.01);
  k.tag('<b>After</b> <span>·</span> Living Icons');
  k.caption('<b>Living Icons</b> — tap a Settings row, come back: its icon comes alive');
  k.wait(1.2);
  scrollBy(640);
  k.camera(column('Privacy and Security'), 1.0).wait(1.1);

  // 1. The real thing: open a page, come back.
  k.caption('Tap a row, its page opens…');
  visit('Privacy and Security', { after: 0.3 });
  k.caption('…come back: its icon tells you where you were');
  k.wait(1.5);

  // 2. Close-ups, slow motion — each one after tapping its row and coming back.
  k.camera(column('Privacy and Security', 2.0), 0.9).wait(0.9);
  k.caption('Privacy → back: the shackle springs open and slams shut');
  visit('Privacy and Security', { slow: 0.25, after: 1.35, close: true });
  k.camera(column('Notifications and Sounds', 2.0), 0.9).wait(0.9);
  k.caption('Notifications → back: the bell rings, its clapper swings');
  visit('Notifications and Sounds', { slow: 0.3, after: 1.3, close: true });
  k.camera(column('Power Saving', 2.0), 0.9).wait(0.9);
  k.caption('Power Saving → back: the battery’s charge jolts');
  visit('Power Saving', { slow: 0.3, after: 1.1, close: true });
  k.camera(column('Data and Storage', 2.0), 0.7).wait(0.7);
  k.caption('Data and Storage → back: the disks hop one by one');
  visit('Data and Storage', { slow: 0.3, after: 1.1, close: true });

  // 3. Whole sections, every part moving.
  k.camera(column('Recent Calls', 1.45), 1.0).wait(1.0);
  k.caption('Every icon has its own motion — shown in a row here');
  wave(['Saved Messages', 'Recent Calls', 'Devices', 'Chat Folders'], 0.24, 1.2);
  k.camera(column('Appearance', 1.45), 0.8).wait(0.8);
  k.caption('(in the app each plays when you come back from its page)');
  wave(['Notifications and Sounds', 'Privacy and Security', 'Data and Storage', 'Appearance', 'Power Saving', 'Language'], 0.24, 1.3);

  // 4. Further down: Premium, Stars, Business, Gift, help.
  k.caption(null);
  scrollBy(335);
  k.camera(column('Telegram Premium', 2.0), 0.9).wait(0.9);
  k.caption('Telegram Premium → back: the star’s arms fly out as it spins');
  visit('Telegram Premium', { slow: 0.3, after: 1.2, close: true });
  k.camera(column('Telegram Business', 2.0), 0.7).wait(0.7);
  k.caption('Telegram Business → back: the shop’s awning pops open');
  visit('Telegram Business', { slow: 0.3, after: 1.05, close: true });
  k.camera(column('Send a Gift', 1.3), 1.0).wait(1.0);
  k.caption('…every one of them (shown in a row here)');
  wave(['Telegram Premium', 'My Stars', 'Telegram Business', 'Send a Gift', 'Ask a Question', 'Telegram FAQ', 'Telegram Features'], 0.24, 1.3);

  // 5. Back up: the profile's own rows, then My Profile and Proxy close.
  k.caption(null);
  k.camera(BASE, 0.9);
  scrollBy(-975, 1.0);
  k.wait(0.5);
  k.camera(column('Change Profile Photo', 1.3), 1.0).wait(1.0);
  k.caption('Even the profile’s own rows (shown in a row here)');
  wave(['Change Emoji Status', 'Change Profile Color', 'Change Profile Photo', 'My Profile', 'Money'], 0.24, 1.3);
  k.caption(null);
  scrollBy(150, 0.8);
  k.camera(column('My Profile', 2.0), 0.9).wait(0.9);
  k.caption('My Profile → back: the person ducks and pops up');
  visit('My Profile', { slow: 0.3, after: 1.1, close: true });
  k.camera(column('Proxy', 2.0), 0.7).wait(0.7);
  k.caption('Proxy → back: the arrows run through the shield');
  visit('Proxy', { slow: 0.3, after: 1.1, close: true });
  k.caption(null);
  k.camera(BASE, 1.0).wait(1.3);
  return k.done();
}

// Before: Telegram today — the same visits, the icons stay still.
function livingIconsBefore(ctx) {
  const { ui, W, scroll, nav } = ctx;
  const k = timeline();
  const row = (title) => ui.rows.find((r) => (r.title?.firstChild?.textContent || r.id) === title || r.id === title);
  const rowAt = (title, x = 200) => () => { const r = row(title); return [x, r.y - scroll.offset + r.h / 2]; };
  const iconAt = (title) => () => ctx.centerOf(row(title).tile || row(title).glyph);
  const BASE = { zoom: 1.0, focus: [W / 2, 0], anchor: [539.5, 97] };
  const column = (title, zoom = 1.7) => () => { const c = iconAt(title)(); return { zoom, focus: [c[0] + 118, c[1]], anchor: [540, 520] }; };
  const closeUp = (title, zoom = 3.6) => () => { const c = iconAt(title)(); return { zoom, focus: [c[0] + 34, c[1]], anchor: [540, 520] }; };
  const scrollBy = (d, duration = 0.95) => {
    k.gesture({ from: [250, d > 0 ? 700 : 260], path: [[250, (d > 0 ? 700 : 260) - d]], hold: 0.08, duration, ease: 'inOut', after: 0.05 });
    k.wait(0.25);
  };
  const PAGE = { zoom: 1.3, focus: [W / 2, 0], anchor: [540, 90] };
  // With `close`: back to the page while it is open, into the icon on the way back (as in the after video).
  const visit = (title, after = 1.5, close = false) => {
    let target = null;
    if (close) k.call(() => { target = closeUp(title)(); });
    k.tap(rowAt(title));
    if (close) k.camera(PAGE, 0.6);
    k.wait(1.45);
    k.tap(() => ctx.centerOf(nav.top.backButton));
    if (close) k.camera(() => target, 0.6);
    k.wait(after);
  };
  k.camera(BASE, 0.01);
  k.tag('<b>Before</b> <span>·</span> Telegram today');
  k.caption('<b>Today</b> — Settings icons are still pictures');
  k.wait(1.2);
  scrollBy(640);
  k.camera(column('Privacy and Security'), 1.0).wait(1.1);
  k.caption('Tap a row, its page opens…');
  visit('Privacy and Security', 0.3);
  k.caption('…come back: the icon stays still');
  k.wait(1.6);
  k.camera(column('Notifications and Sounds', 2.0), 0.9).wait(0.9);
  k.caption('Notifications → back: nothing moves');
  visit('Notifications and Sounds', 1.8, true);
  k.camera(column('Power Saving', 2.0), 0.9).wait(0.9);
  k.caption('Power Saving → back: nothing moves');
  visit('Power Saving', 1.8, true);
  k.caption(null);
  k.camera(BASE, 1.0).wait(1.3);
  return k.done();
}
