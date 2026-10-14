// Depth Swipe demo (?tab=chats&demo=swipe): close on the row, every swipe at full speed and again in slow
// motion — right (the letters roll back in a wave while you pull, the message leans, the photo tilts), left
// (the photo, then the name letter by letter, flip over the screen's edge and back out), all the way (the
// letters spin, the photo flips), flicks, and an archive with its undo.
// ?before=1 plays the same swipes in Telegram today: the row slides flat.

import { timeline } from './kit.js';

export function swipeDemo(ctx) {
  const { chats, W } = ctx;
  const before = !!ctx.before;
  const k = timeline();
  const row = (id) => chats.rows.find((r) => r.chat.id === id);
  const yOf = (id) => row(id).y + 38 - chats.scroller.offset;
  // A point on a chat row (screen pt), resolved when the finger gets there.
  const at = (id, x) => () => [x, yOf(id)];
  const rel = (id, x, pts) => () => { const y = yOf(id); return pts.map(([dx, dy]) => [x + dx, y + dy]); };
  // Close on one row: `x0…x1` (screen pt) across the frame.
  const frame = (id, x0, x1, dy = 0) => () => {
    const zoom = 1080 / (1.727 * (x1 - x0));
    return { zoom, focus: [(x0 + x1) / 2, yOf(id) + dy], anchor: [540, 520] };
  };
  const BASE = { zoom: 1.0, focus: [W / 2, 0], anchor: [539.5, 97] };
  const say = (after, today) => k.caption(before ? today : after);

  // The finger on the row through (dx, seconds, hold, ease) steps, then let go.
  const pull = (id, x0, steps) => {
    k.down(at(id, x0)).wait(0.08);
    let dx = 0;
    for (const [to, secs, hold = 0, ease = 'inOut'] of steps) {
      const from = dx;
      k.at(k.t, { drag: rel(id, x0, [[from + (to - from) * 0.5, 0], [to, 0]]), duration: secs, ease });
      k.wait(secs + hold);
      dx = to;
    }
    k.up();
  };
  // Close an open row with a tap on its content.
  const close = (id, x, after = 1.1) => { k.tap(at(id, x)); k.wait(after); };

  k.camera(BASE, 0.01);
  k.tag(before ? '<b>Before</b> <span>·</span> Telegram today' : '<b>After</b> <span>·</span> Depth Swipe');
  say('<b>Depth Swipe</b> — your chats move in 3D as you swipe', '<b>Today</b> — a swiped chat slides as one flat piece');
  k.wait(1.2);

  // 1. Right: the letters roll back while you pull, long before the swipe is done.
  k.camera(frame('alex', 6, 300), 1.1).wait(1.2);
  say('Start pulling right: the letters already roll back…', 'Pull right: the row slides');
  pull('alex', 110, [[70, 0.32, 0.45], [110, 0.28, 0.4], [50, 0.25, 0.3], [100, 0.25, 0.25]]);
  say('…the message leans, the photo tilts — then it all settles flat', 'Let go: it opens, flat');
  k.wait(1.0);
  close('alex', 330);
  say('A quick pull: they roll harder, in a wave', 'A quick pull: still flat');
  pull('alex', 110, [[115, 0.17, 0.75, 'out']]);
  k.wait(0.9);
  close('alex', 330);
  k.speed(0.25);
  say('Pulling right, in slow motion', 'In slow motion: one flat piece');
  pull('alex', 110, [[70, 0.32, 0.3], [110, 0.28, 0.35]]);
  k.wait(0.8);
  close('alex', 330, 1.0);
  k.speed(1).wait(0.3);

  // 2. Left: the screen's edge is the rim of the surface — the photo rolls over it, the letters flip over it.
  k.camera(frame('hike', -4, 236), 1.1).wait(1.2);
  say('Pull left: the photo rolls over the edge of the screen…', 'Pull left: the row slides under the edge');
  pull('hike', 340, [[-90, 0.6, 0.4], [-235, 0.95, 0.35]]);
  say('…and every letter flips over it, one after another', 'Photo and name are simply cut off');
  k.wait(1.0);
  say('Close it: they flip back out of the edge', 'Close it: flat again');
  close('hike', 90, 1.5);
  k.speed(0.25);
  say('Over the edge, in slow motion', 'In slow motion: one flat piece');
  pull('hike', 340, [[-215, 0.8, 0.25]]);
  k.wait(0.6);
  close('hike', 90, 1.4);
  k.speed(1).wait(0.3);

  // 3. All the way: the letters spin, the photo flips (a short name, so it all stays in frame).
  k.camera(frame('omar', 118, 402), 1.1).wait(1.2);
  say('All the way: the letters spin, the photo flips like a coin', 'All the way: the action runs, nothing moves');
  pull('omar', 80, [[250, 0.55, 0.9]]);
  k.wait(1.4);
  if (!before) {
    k.speed(0.3);
    say('All the way, in slow motion', '');
    pull('omar', 80, [[250, 0.55, 0.9]]);
    k.wait(1.2);
    k.speed(1).wait(0.3);
  }

  // 4. Flicks: the lean comes from the speed.
  k.camera({ zoom: 1.6, focus: [W / 2, 430], anchor: [540, 520] }, 1.0).wait(0.9);
  say('Fast flicks: it leans as hard as you flick', 'Fast flicks: flat');
  const flick = (id, x0, dx) => {
    k.gesture({ from: at(id, x0), path: rel(id, x0, [[dx * 0.5, 0], [dx, 1]]), hold: 0.06, duration: 0.13, ease: 'in' });
    k.wait(0.75);
  };
  flick('news', 110, 150);
  flick('news', 300, -150);
  flick('news', 320, -170);
  flick('news', 90, 170);
  k.wait(0.3);

  // 5. Archive: the row flies off over the rim; Undo brings it back.
  k.camera({ zoom: 1.05, focus: [W / 2, 560], anchor: [540, 560] }, 1.0).wait(0.9);
  say('Archive: it rolls off the edge…', 'Archive: the row slides away');
  pull('books', 350, [[-170, 0.35], [-330, 0.35, 0.25]]);
  k.wait(1.6);
  say('…Undo, and it is back', 'Undo: it is back');
  k.tap(() => ctx.centerOf(chats.toast.button));
  k.wait(1.5);
  k.caption(null);
  k.wait(0.6);
  return k.done();
}
