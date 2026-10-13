// Glass Gifts demo (?tab=chats&demo=gifts): a chat's profile, its Gifts — touch a gift and the
// glass leans toward the finger while light runs across it (slow motion once); hold and slide
// and every gift you cross follows; tilt the phone and the light moves across all of them.
// A tap keeps opening the gift's info, as Telegram does today: the glass is what happens
// under the finger (like hover).

import { timeline } from './kit.js';

export function giftsDemo(ctx) {
  const { chats, nav, W, stage } = ctx;
  const k = timeline();
  const row = (id) => chats.rows.find((r) => r.chat.id === id);
  const page = () => nav.top;
  // Centre of gift i on screen, plus an offset (u, v in −1…1 of half the tile).
  const gift = (i, u = 0, v = 0) => () => {
    const t = page().tiles[i];
    const s = t.slot;
    return [s.x + s.w / 2 + (u * s.w) / 2, s.y + s.h / 2 + (v * s.h) / 2 - page().scroller.offset];
  };
  const BASE = { zoom: 1.0, focus: [W / 2, 0], anchor: [539.5, 97], tilt: [0, 0] };
  const GRID = () => {
    const a = gift(0)();
    const b = gift(8)();
    return { zoom: 1.5, focus: [W / 2, (a[1] + b[1]) / 2 - 20], anchor: [540, 520], tilt: [0, 0] };
  };

  // The phone's tilt drives the gifts' light (as the gyroscope would).
  ctx.addUpdater(() => {
    const p = page();
    if (!p?.motion) return false;
    const [rx, ry] = stage.currentCam?.tilt || [0, 0];
    const on = Math.abs(rx) + Math.abs(ry) > 0.01;
    p.motion.set(on ? { x: ry * 1.6, y: -rx * 1.6 } : null);
    return on;
  });

  k.camera(BASE, 0.01);
  k.caption('<b>Glass Gifts</b> — every gift becomes a pane of glass');
  k.wait(1.0);
  // Open a profile; its Gifts are below the info.
  k.tap(() => [200, row('alex').y + 38 - chats.scroller.offset]);
  k.wait(1.2);
  k.gesture({ from: [200, 520], path: [[200, 110]], hold: 0.08, duration: 1.0, ease: 'inOut', after: 0.05 });
  k.wait(0.3);
  k.camera(GRID, 1.1).wait(1.6);

  // 1. Touch: the glass leans toward the finger, light runs across it.
  k.caption('Touch a gift: it leans to your finger, light runs across it');
  k.down(gift(1, 0.55, -0.5)).wait(1.1).up().wait(0.7);
  k.down(gift(3, -0.6, 0.55)).wait(1.0).up().wait(0.7);
  k.down(gift(5, 0.5, 0.45)).wait(1.0).up().wait(0.6);
  k.speed(0.3);
  k.caption('Touch, in slow motion');
  k.down(gift(4, -0.45, -0.5)).wait(0.9).up().wait(0.7);
  k.speed(1).wait(0.2);

  // 2. Hold and slide: every gift you cross leans after the finger.
  k.caption('Hold and slide: every gift you cross follows');
  k.down(gift(0, 0.1, 0.1));
  k.wait(0.3);
  k.drag(() => [gift(0, 0.15, 0.12)(), gift(1, 0, 0.2)(), gift(2, 0.2, 0)(), gift(5, 0.3, 0.1)(), gift(4, 0, 0.3)(), gift(3, -0.3, 0.1)(), gift(6, 0.1, 0.2)(), gift(7, 0.3, -0.2)(), gift(4, 0.2, -0.3)()], 3.6, 'inOutSine');
  k.wait(0.2).up().wait(1.0);

  // 3. Tilt the phone: the light moves across all of them.
  k.caption('Tilt your phone: the light moves across the glass');
  k.camera(() => ({ ...GRID(), tilt: [7, -11] }), 1.3).wait(1.4);
  k.camera(() => ({ ...GRID(), tilt: [-6, 11] }), 1.9).wait(2.0);
  k.camera(() => ({ ...GRID(), tilt: [5, 4] }), 1.2).wait(1.25);
  k.camera(() => ({ ...GRID(), tilt: [0, 0] }), 1.0).wait(1.1);

  // 4. It is hover-like: a tap keeps opening the gift, as today.
  k.caption('Like hover: a tap still opens the gift’s info, as today');
  k.wait(2.6);
  k.caption(null);
  k.camera(BASE, 1.1).wait(1.4);
  return k.done();
}
