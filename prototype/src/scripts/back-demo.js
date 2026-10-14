// Back Photo demo (?demo=back): without a back photo both sides show the photo; "Add Back
// Photo" picks one and the photo turns over by itself to show it; it turns between both sides
// (and spins); "Change Back Photo" while the back is showing turns it to the new one.

import { timeline } from './kit.js';

export function backPhotoDemo(ctx) {
  if (ctx.before) return backPhotoBefore(ctx);
  const { avatar, W, H, ui, sheets } = ctx;
  const ax = avatar.x;
  const ay = avatar.y;
  const k = timeline();
  const row = (id) => () => { const r = ui.rows.find((x) => x.id === id); return [r.x + 128, r.y + r.h / 2]; };
  const BASE = { zoom: 1.0, focus: [W / 2, 0], anchor: [539.5, 97] };
  const CLOSE = { zoom: 1.6, focus: [ax, ay + 28], anchor: [540, 470] };
  const WHOLE = { zoom: 0.66, focus: [W / 2, H / 2], anchor: [540, 545] };

  const turn = (dir, duration = 0.95) => {
    k.gesture({ from: [ax - dir * 30, ay + 8], path: [[ax + dir * 20, ay + 12], [ax + dir * 92, ay + 15]], hold: 0.2, duration, ease: 'inOut' });
  };

  k.camera(BASE, 0.01);
  k.tag('<b>After</b> <span>·</span> Back Photo');
  k.caption('<b>Back Photo</b> — your profile photo gets a back side');
  k.wait(0.7);
  k.camera(CLOSE, 1.0).wait(1.1);
  k.caption('Today there is no back photo');
  turn(-1);
  k.wait(1.2);

  // Add Back Photo → the picker → it turns over by itself.
  k.camera(WHOLE, 1.0).wait(1.1);
  k.caption('<b>Add Back Photo</b>: pick a picture for the back');
  k.tap(row('backPhoto'));
  k.wait(1.25);
  k.tap(() => sheets.back.itemCenter(2));     // stars over the mountains
  k.wait(0.15);
  k.camera(CLOSE, 0.9);
  k.caption('Your photo turns over by itself to show it');
  k.wait(2.4);
  k.caption('Surprise your followers: a hidden photo, shown only when it turns over');
  k.wait(2.2);

  // Both sides, by hand; a flick shows front, back, front…
  k.caption('Turn it: the photo…');
  turn(1);
  k.wait(1.1);
  k.caption('…and its back');
  turn(-1);
  k.wait(1.1);
  k.speed(0.3);
  k.caption('Turning over, in slow motion');
  turn(1, 1.0);
  k.wait(0.7);
  k.speed(1).wait(0.2);
  k.caption('Flick it: front, back, front…');
  k.gesture({ from: [ax + 34, ay + 8], path: [[ax - 10, ay + 12], [ax - 160, ay + 16]], hold: 0.1, duration: 0.12, ease: 'in' });
  k.wait(2.5);

  // Change it: the photo turns to the new back.
  k.camera(WHOLE, 1.0).wait(1.1);
  k.caption('<b>Change Back Photo</b> any time');
  k.tap(row('backPhoto'));
  k.wait(1.25);
  k.tap(() => sheets.back.itemCenter(5));     // the cat
  k.wait(0.15);
  k.camera(CLOSE, 0.9);
  k.caption('It turns over to the new one');
  k.wait(2.6);
  k.caption(null);
  k.camera(BASE, 1.1).wait(1.5);
  return k.done();
}

// Before: Telegram today — one side, nothing to add, nothing to turn.
function backPhotoBefore(ctx) {
  const { avatar, W, H } = ctx;
  const ax = avatar.x;
  const ay = avatar.y;
  const k = timeline();
  const BASE = { zoom: 1.0, focus: [W / 2, 0], anchor: [539.5, 97] };
  const CLOSE = { zoom: 1.6, focus: [ax, ay + 28], anchor: [540, 470] };
  const WHOLE = { zoom: 0.66, focus: [W / 2, H / 2], anchor: [540, 545] };
  const turn = (dir, duration = 0.95) => {
    k.gesture({ from: [ax - dir * 30, ay + 8], path: [[ax + dir * 20, ay + 12], [ax + dir * 92, ay + 15]], hold: 0.2, duration, ease: 'inOut' });
  };
  k.camera(BASE, 0.01);
  k.tag('<b>Before</b> <span>·</span> Telegram today');
  k.caption('<b>Today</b> — your profile photo has one side');
  k.wait(0.7);
  k.camera(CLOSE, 1.0).wait(1.1);
  k.caption('Turn it to see its back: it doesn’t turn, there is no back');
  turn(-1);
  k.wait(0.8);
  turn(1);
  k.wait(1.0);
  k.camera(WHOLE, 1.0).wait(1.1);
  k.caption('And no way to add a hidden photo for your followers');
  k.wait(3.0);
  k.caption(null);
  k.camera(BASE, 1.1).wait(1.5);
  return k.done();
}
