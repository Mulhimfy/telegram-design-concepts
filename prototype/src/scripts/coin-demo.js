// Demo timeline (screen pt, seconds) for the 1080×1080 video: one take on the own profile.
//   1. the avatar turns into glass under the finger, tilts, turns over to its emblem and back
//   2. Add Back Photo → pick a photo → the avatar turns over to show it; a flick spins it
//   3. Change Glass Color → violet, gold: the light runs across the whole screen
//   4. the tinted glass turns over once more
// Every touch goes through the page's InputRouter, like a finger.

export function glassDemoScript({ avatar, W, H, ui, sheets }) {
  const ax = avatar.x;
  const ay = avatar.y;
  const row = (id) => {
    const r = ui.rows.find((x) => x.id === id);
    return [r.x + 128, r.y + r.h / 2];
  };
  const base = { zoom: 1.0, focus: [W / 2, 0], anchor: [539.5, 97] };
  const close = { zoom: 1.6, focus: [ax, ay + 28], anchor: [540, 470] };
  const whole = { zoom: 0.66, focus: [W / 2, H / 2], anchor: [540, 545] };
  const s = [];
  const at = (t, e) => s.push({ t, ...e });

  at(0, { camera: base, duration: 0.01 });
  at(0.6, { camera: close, duration: 1.0 });

  // 1. press and tilt (the light glides over the glass), let go: flat again at once
  at(1.95, { down: [ax + 18, ay + 10] });
  at(2.3, { drag: [[ax + 52, ay + 2], [ax - 6, ay + 22], [ax + 22, ay + 12]], duration: 1.6, ease: 'inOut' });
  at(4.05, { up: true });
  // turn it over: the emblem (profile colour + emoji)
  at(4.75, { down: [ax + 28, ay + 8] });
  at(5.0, { drag: [[ax - 24, ay + 12], [ax - 94, ay + 15]], duration: 1.0, ease: 'inOut' });
  at(6.12, { up: true });
  // and back
  at(7.2, { down: [ax - 30, ay + 10] });
  at(7.42, { drag: [[ax + 20, ay + 12], [ax + 88, ay + 14]], duration: 0.9, ease: 'inOut' });
  at(8.42, { up: true });

  // 2. Add Back Photo
  at(9.1, { camera: whole, duration: 1.1 });
  at(10.45, { tap: row('backPhoto') });
  at(11.65, { tap: sheets.back.itemCenter(1) });          // the Milky Way
  at(11.75, { camera: close, duration: 0.9 });
  // flick: it spins and lands on a side
  at(13.75, { down: [ax + 34, ay + 8] });
  at(13.85, { drag: [[ax - 10, ay + 12], [ax - 150, ay + 16]], duration: 0.12, ease: 'in' });
  at(13.98, { up: true });
  at(16.0, { down: [ax - 30, ay + 8] });
  at(16.2, { drag: [[ax + 24, ay + 10], [ax + 86, ay + 12]], duration: 0.8, ease: 'inOut' });
  at(17.1, { up: true });

  // 3. Change Glass Color
  at(17.6, { camera: whole, duration: 1.0 });
  at(18.85, { tap: row('glassColor') });
  at(19.85, { tap: sheets.color.itemCenter(3) });         // violet
  at(21.45, { tap: sheets.color.itemCenter(1) });         // gold
  at(23.1, { tap: [sheets.color.inset + 34, sheets.color.top + 34] }); // close

  // 4. the gold glass, turned over
  at(23.55, { camera: close, duration: 1.0 });
  at(24.85, { down: [ax + 26, ay + 8] });
  at(25.1, { drag: [[ax - 20, ay + 12], [ax - 96, ay + 16]], duration: 1.0, ease: 'inOut' });
  at(26.2, { up: true });
  at(27.25, { down: [ax - 30, ay + 10] });
  at(27.45, { drag: [[ax + 22, ay + 12], [ax + 90, ay + 14]], duration: 0.85, ease: 'inOut' });
  at(28.4, { up: true });
  at(29.1, { camera: base, duration: 1.1 });
  at(30.7, { call: () => {} });
  return s;
}
