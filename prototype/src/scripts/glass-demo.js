// Glass Avatar demo (?demo=glass): the photo turns into glass under the finger and tilts any
// way; it turns over to either side (and once in slow motion, the glass edge-on); a flick spins
// it; a glass colour sends its light across the profile; turning then lights the name in the
// direction it turns (slow motion both ways), and a spin washes the name in the colour.

import { timeline } from './kit.js';

export function glassAvatarDemo(ctx) {
  if (ctx.before) return glassAvatarBefore(ctx);
  const { avatar, W, H, ui, sheets } = ctx;
  const ax = avatar.x;
  const ay = avatar.y;
  const k = timeline();
  const row = (id) => { const r = ui.rows.find((x) => x.id === id); return [r.x + 128, r.y + r.h / 2]; };
  const BASE = { zoom: 1.0, focus: [W / 2, 0], anchor: [539.5, 97] };
  const CLOSE = { zoom: 1.6, focus: [ax, ay + 28], anchor: [540, 470] };
  const HEADER = { zoom: 1.42, focus: [ax, ay + 72], anchor: [540, 520] };    // photo, name, subtitle, buttons
  const WHOLE = { zoom: 0.66, focus: [W / 2, H / 2], anchor: [540, 545] };

  // Turn it over: from one side of the photo to the other, past edge-on (1 pt = 1°).
  const turn = (dir, duration = 1.0, from = 30) => {
    k.gesture({ from: [ax - dir * from, ay + 8], path: [[ax + dir * 20, ay + 12], [ax + dir * 92, ay + 15]], hold: 0.2, duration, ease: 'inOut' });
  };
  const flick = (dir) => {
    k.gesture({ from: [ax - dir * 34, ay + 8], path: [[ax + dir * 10, ay + 12], [ax + dir * 150, ay + 16]], hold: 0.1, duration: 0.12, ease: 'in' });
  };

  k.camera(BASE, 0.01);
  k.tag('<b>After</b> <span>·</span> Glass Avatar');
  k.caption('<b>Glass Avatar</b> — your photo turns to glass under your finger');
  k.wait(0.7);
  k.camera(CLOSE, 1.0).wait(1.2);

  // 1. Touch: it lifts into glass; drag: it tilts any way and the light glides over it.
  k.caption('Touch and drag: it tilts any way you move');
  k.gesture({
    from: [ax + 18, ay + 10],
    path: [[ax + 50, ay + 4], [ax + 30, ay + 40], [ax - 20, ay + 34], [ax - 34, ay - 6], [ax + 6, ay - 26], [ax + 22, ay + 10]],
    hold: 0.35, duration: 2.6, ease: 'inOut', after: 0.15,
  });
  k.caption('Let go: back to normal at once — minimal, never in the way');
  k.wait(1.6);

  // 2. Past edge-on it turns over — either way.
  k.caption('Past edge-on it turns over — to the left…');
  turn(-1);
  k.wait(1.1);
  k.caption('…or to the right');
  turn(1, 0.9);
  k.wait(1.1);
  k.speed(0.25);
  k.caption('Edge-on it is a thin sheet of glass');
  turn(-1, 1.0);
  k.wait(0.75);
  k.speed(1).wait(0.25);

  // 3. A flick spins it; it lands on a side.
  k.caption('Flick: it spins and lands on a side');
  flick(1);
  k.wait(2.3);

  // 4. Glass colour: the light runs across the whole profile.
  k.camera(WHOLE, 1.0).wait(1.1);
  k.caption('Change Glass Color: its light runs across the profile');
  k.tap(row('glassColor'));
  k.wait(1.0);
  k.tap(() => sheets.color.itemCenter(3));        // violet
  k.wait(1.7);
  k.tap(() => sheets.color.itemCenter(1));        // gold
  k.wait(1.7);
  k.tap(() => [sheets.color.inset + 34, sheets.color.top + 34]);   // close
  k.wait(0.5);

  // 5. Turning it lights the name, the way it turns (slow motion, both ways).
  k.camera(HEADER, 1.0).wait(1.1);
  k.caption('Turn it: the light crosses your name the way it turns');
  turn(1, 1.1);
  k.wait(1.0);
  turn(-1, 1.1);
  k.wait(1.0);
  k.speed(0.3);
  k.caption('To the right, in slow motion');
  turn(1, 1.2);
  k.wait(0.8);
  k.caption('To the left, in slow motion');
  turn(-1, 1.2);
  k.wait(0.8);
  k.speed(1).wait(0.2);

  // 6. A spin washes the name in the colour.
  k.caption('A spin washes your name in its light');
  flick(-1);
  k.wait(2.4);
  k.caption(null);
  k.camera(BASE, 1.1).wait(1.5);
  return k.done();
}

// Before: the same moments in Telegram today — the photo ignores the finger; no glass, no colour.
function glassAvatarBefore(ctx) {
  const { avatar, W, H } = ctx;
  const ax = avatar.x;
  const ay = avatar.y;
  const k = timeline();
  const BASE = { zoom: 1.0, focus: [W / 2, 0], anchor: [539.5, 97] };
  const CLOSE = { zoom: 1.6, focus: [ax, ay + 28], anchor: [540, 470] };
  const WHOLE = { zoom: 0.66, focus: [W / 2, H / 2], anchor: [540, 545] };
  const turn = (dir, duration = 1.0, from = 30) => {
    k.gesture({ from: [ax - dir * from, ay + 8], path: [[ax + dir * 20, ay + 12], [ax + dir * 92, ay + 15]], hold: 0.2, duration, ease: 'inOut' });
  };
  k.camera(BASE, 0.01);
  k.tag('<b>Before</b> <span>·</span> Telegram today');
  k.caption('<b>Today</b> — your profile photo is a flat picture');
  k.wait(0.7);
  k.camera(CLOSE, 1.0).wait(1.2);
  k.caption('Touch and drag it: nothing happens');
  k.gesture({
    from: [ax + 18, ay + 10],
    path: [[ax + 50, ay + 4], [ax + 30, ay + 40], [ax - 20, ay + 34], [ax - 34, ay - 6], [ax + 6, ay - 26], [ax + 22, ay + 10]],
    hold: 0.35, duration: 2.6, ease: 'inOut', after: 0.15,
  });
  k.wait(0.6);
  k.caption('Try to turn it over, either way: it never turns');
  turn(-1);
  k.wait(0.8);
  turn(1, 0.9);
  k.wait(0.8);
  k.caption('Flick it: still nothing');
  k.gesture({ from: [ax + 34, ay + 8], path: [[ax - 10, ay + 12], [ax - 150, ay + 16]], hold: 0.1, duration: 0.12, ease: 'in' });
  k.wait(1.4);
  k.camera(WHOLE, 1.0).wait(1.1);
  k.caption('No glass and no glass colour to choose');
  k.wait(2.6);
  k.caption(null);
  k.camera(BASE, 1.1).wait(1.5);
  return k.done();
}
