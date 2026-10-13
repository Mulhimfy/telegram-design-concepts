// Depth Swipe demo (?tab=chats&demo=swipe): every swipe at full speed, then again in slow
// motion — right (letters roll back in a wave, lines lean, the photo turns into a coin), left
// (they roll over the screen's rounded edge and back out), all the way (the spin), flicks, and
// an archive with its undo.

import { timeline } from './kit.js';

export function swipeDemo(ctx) {
  const { chats, W } = ctx;
  const k = timeline();
  const row = (id) => chats.rows.find((r) => r.chat.id === id);
  // A point on a chat row (screen pt), resolved when the finger gets there.
  const at = (id, x) => () => [x, row(id).y + 38 - chats.scroller.offset];
  const rel = (id, x, pts) => () => { const y = row(id).y + 38 - chats.scroller.offset; return pts.map(([dx, dy]) => [x + dx, y + dy]); };

  const BASE = { zoom: 1.0, focus: [W / 2, 0], anchor: [539.5, 97] };
  const ROWS = { zoom: 1.55, focus: [W / 2, 330], anchor: [540, 520] };
  const LOW = { zoom: 1.55, focus: [W / 2, 450], anchor: [540, 520] };

  // A swipe that ends with the row open (finger held a beat), then a tap closes it.
  const openAndClose = (id, dir, { reach = 150, duration = 0.55, hold = 0.35, rest = 0.85, after = 1.0 } = {}) => {
    const x0 = dir > 0 ? 110 : 320;
    k.gesture({ from: at(id, x0), path: rel(id, x0, [[dir * reach * 0.55, 1], [dir * reach, 2]]), hold: 0.1, duration, ease: 'inOut', after: hold });
    k.wait(rest);
    // On the row's content (not on its buttons): the tap closes it, and it moves in 3D again.
    k.tap(at(id, dir > 0 ? 300 : 90));
    k.wait(after);
  };
  // All the way: the letters spin, the photo flips; the action runs and the row closes.
  const full = (id, dir, { duration = 0.7, hold = 0.25, after = 1.5 } = {}) => {
    const x0 = dir > 0 ? 80 : 350;
    k.gesture({ from: at(id, x0), path: rel(id, x0, [[dir * 170, 1], [dir * 330, 3]]), hold: 0.1, duration, ease: 'inOut', after: hold });
    k.wait(after);
  };

  k.camera(BASE, 0.01);
  k.caption('<b>Depth Swipe</b> — chats move in 3D as you swipe');
  k.wait(1.1);
  k.camera(ROWS, 1.1).wait(1.4);

  // 1. Right
  k.caption('Swipe right: the letters roll back in a wave');
  openAndClose('alex', 1);
  k.caption('…the message leans, the photo becomes a coin');
  openAndClose('hike', 1, { reach: 140 });
  k.speed(0.25);
  k.caption('Swipe right, in slow motion');
  openAndClose('alex', 1, { after: 0.9 });
  k.speed(1).wait(0.3);

  // 2. Left: the screen's edge is the rim of the surface
  k.caption('Swipe left: they roll over the edge of the screen');
  openAndClose('hike', -1, { reach: 200 });
  k.caption('…and roll back out as it closes');
  openAndClose('alex', -1, { reach: 200 });
  k.speed(0.25);
  k.caption('Swipe left, in slow motion');
  openAndClose('hike', -1, { reach: 200, after: 0.9 });
  k.speed(1).wait(0.3);

  // 3. All the way
  k.caption('All the way: the letters spin, the photo flips');
  full('alex', 1);
  k.speed(0.3);
  k.caption('All the way, in slow motion');
  full('hike', 1, { after: 1.4 });
  k.speed(1).wait(0.3);

  // 4. Flicks: the lean comes from the speed
  k.camera(LOW, 0.8).wait(0.6);
  k.caption('Fast or slow, it follows your finger');
  const flick = (id, x0, dx) => {
    k.gesture({ from: at(id, x0), path: rel(id, x0, [[dx * 0.5, 0], [dx, 1]]), hold: 0.06, duration: 0.13, ease: 'in' });
    k.wait(0.75);
  };
  flick('omar', 110, 150);     // opens
  flick('omar', 300, -150);    // closes
  flick('news', 320, -170);    // opens on the right: photo and name round the rim
  flick('news', 90, 170);      // closes: they roll back out
  k.wait(0.3);

  // 5. Archive: the row flies off over the rim; Undo brings it back
  k.camera({ zoom: 1.05, focus: [W / 2, 560], anchor: [540, 560] }, 1.0).wait(0.9);
  k.caption('Archive: it rolls off the edge…');
  full('omar', -1, { after: 1.6 });
  k.caption('…Undo, and it is back');
  k.tap(() => ctx.centerOf(chats.toast.button));
  k.wait(1.5);
  k.caption(null);
  k.wait(0.6);
  return k.done();
}
