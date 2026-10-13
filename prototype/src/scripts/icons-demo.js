// Living Icons demo (?demo=icons): open a Settings row and come back — its icon comes alive;
// close-ups in slow motion of the parts moving (the padlock's shackle, the bell's clapper, the
// battery's charge jolting, the Premium star's arms, the person in My Profile); then every icon of every
// section in a wave.

import { timeline } from './kit.js';
import { LivingIcons } from '../settings/living-icons.js';

export function livingIconsDemo(ctx) {
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
  // Open its page, come back: the icon plays as the page leaves.
  const visit = (title, { stay = 0.85, slow = null, after = 1.45 } = {}) => {
    k.tap(rowAt(title));
    k.wait(0.6 + stay);
    k.tap(() => ctx.centerOf(nav.top.backButton));
    if (slow) {
      k.wait(0.14);
      k.speed(slow, 0.2);
    }
    k.wait(after);
    if (slow) k.speed(1, 0.2);
  };
  // Play one icon directly (the motion itself, for a close-up).
  const play = (title, { slow = null, after = 1.3 } = {}) => {
    if (slow) k.speed(slow, 0.2);
    k.call(({ now }) => living.play(row(title), now));
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
  k.caption('<b>Living Icons</b> — Settings icons come alive');
  k.wait(1.0);
  scrollBy(640);
  k.camera(column('Privacy and Security'), 1.0).wait(1.1);

  // 1. The real thing: open a page, come back.
  k.caption('Open a page and come back…');
  visit('Privacy and Security', { after: 0.3 });
  k.caption('…its icon tells you where you were');
  k.wait(1.4);

  // 2. Close-ups, slow motion.
  k.camera(closeUp('Privacy and Security'), 0.9).wait(0.9);
  k.caption('The shackle springs open and slams shut');
  visit('Privacy and Security', { slow: 0.25, after: 1.35 });
  k.camera(closeUp('Notifications and Sounds'), 0.9).wait(0.9);
  k.caption('The bell rings, its clapper swings, its badge swells');
  visit('Notifications and Sounds', { slow: 0.3, after: 1.3 });
  k.camera(closeUp('Power Saving'), 0.9).wait(0.9);
  k.caption('The battery strikes, its charge jolts and snaps back');
  play('Power Saving', { slow: 0.3, after: 1.1 });
  k.camera(closeUp('Data and Storage'), 0.7).wait(0.7);
  k.caption('The storage disks hop one by one and land');
  play('Data and Storage', { slow: 0.3, after: 1.1 });

  // 3. Whole sections, every part moving.
  k.camera(column('Recent Calls', 1.45), 1.0).wait(1.0);
  k.caption('Every icon moves its own parts');
  wave(['Saved Messages', 'Recent Calls', 'Devices', 'Chat Folders'], 0.24, 1.2);
  k.camera(column('Appearance', 1.45), 0.8).wait(0.8);
  wave(['Notifications and Sounds', 'Privacy and Security', 'Data and Storage', 'Appearance', 'Power Saving', 'Language'], 0.24, 1.3);

  // 4. Further down: Premium, Stars, Business, Gift, help.
  k.caption(null);
  scrollBy(335);
  k.camera(closeUp('Telegram Premium'), 0.9).wait(0.9);
  k.caption('The Premium star’s arms fly out as it spins');
  play('Telegram Premium', { slow: 0.3, after: 1.2 });
  k.camera(closeUp('Telegram Business'), 0.7).wait(0.7);
  k.caption('The shop’s awning pops open and snaps shut');
  play('Telegram Business', { slow: 0.3, after: 1.05 });
  k.camera(column('Send a Gift', 1.3), 1.0).wait(1.0);
  k.caption('…every one of them');
  wave(['Telegram Premium', 'My Stars', 'Telegram Business', 'Send a Gift', 'Ask a Question', 'Telegram FAQ', 'Telegram Features'], 0.24, 1.3);

  // 5. Back up: the profile's own rows, then My Profile and Proxy close.
  k.caption(null);
  k.camera(BASE, 0.9);
  scrollBy(-975, 1.0);
  k.wait(0.5);
  k.camera(column('Change Profile Photo', 1.3), 1.0).wait(1.0);
  k.caption('Even the profile’s own rows');
  wave(['Change Emoji Status', 'Change Profile Color', 'Change Profile Photo', 'My Profile', 'Money'], 0.24, 1.3);
  k.caption(null);
  scrollBy(150, 0.8);
  k.camera(closeUp('My Profile'), 0.9).wait(0.9);
  k.caption('The person in My Profile ducks and pops up');
  play('My Profile', { slow: 0.3, after: 1.1 });
  k.camera(closeUp('Proxy'), 0.7).wait(0.7);
  k.caption('The arrows run through the shield');
  play('Proxy', { slow: 0.3, after: 1.1 });
  k.caption(null);
  k.camera(BASE, 1.0).wait(1.3);
  return k.done();
}
