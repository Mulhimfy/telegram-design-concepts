// Living Icons: what is new. Every Settings row has a small icon that never moves. Here, when you
// come back from a row's page, its icon tells you where you were — and every part of it moves:
// the bell rings, its clapper swings and its badge swells; the padlock's shackle springs open
// and slams shut; the person in My Profile ducks and pops back up; the proxy's arrows run
// through the shield; the bookmark drops and its ribbon flaps; the battery strikes and its charge
// jolts; the Premium star's arms fly out as it spins; the laptop's lid shuts and opens; the shop's
// awning pops open a crack… Every icon is Telegram's own artwork (Telegram-iOS f1dd7a2), cut along
// its own sub-shapes into parts (or, where the file merges them, rebuilt part by part or cut by
// clips so it is the same icon at rest; cut-outs move inside masks), each with its own little
// physics. The tile pops on a spring and a sheen crosses it; then it is the same still icon again.
//
// One icon at a time, on the page clock (frame-exact in recordings); nothing runs at rest.

const SVGNS = 'http://www.w3.org/2000/svg';
const clamp = (x, a = 0, b = 1) => Math.max(a, Math.min(b, x));
const DEG = Math.PI / 180;

// Damped oscillation: amplitude a, frequency f (Hz), decay k (1/s), starting at t0.
const ring = (t, a, f, k, t0 = 0) => (t < t0 ? 0 : a * Math.sin(2 * Math.PI * f * (t - t0)) * Math.exp(-k * (t - t0)));
// Spring step 0 → 1 with overshoot (ζ ≈ 0.5), response r (s), starting at t0.
const pop = (t, r = 0.32, t0 = 0, zeta = 0.5) => {
  if (t <= t0) return 0;
  const w = (2 * Math.PI) / r;
  const wd = w * Math.sqrt(1 - zeta * zeta);
  const u = t - t0;
  return 1 - Math.exp(-zeta * w * u) * (Math.cos(wd * u) + ((zeta * w) / wd) * Math.sin(wd * u));
};
// Ball dropped from h (pt) onto the floor with restitution e: y offset (negative = up), from t0.
const drop = (t, h, t0 = 0, e = 0.38) => {
  const g = 2200;
  let u = t - t0;
  if (u < 0) return -h;
  let v = Math.sqrt(2 * g * h);
  let tFall = v / g;
  if (u < tFall) return -h + 0.5 * g * u * u;
  u -= tFall;
  for (let i = 0; i < 4; i++) {
    v *= e;
    const tb = (2 * v) / g;
    if (u < tb) return -(v * u - 0.5 * g * u * u);
    u -= tb;
  }
  return 0;
};
const ease = (u) => { u = clamp(u); return u * u * (3 - 2 * u); };
const easeOut = (u) => 1 - Math.pow(1 - clamp(u), 3);
const easeIn = (u) => Math.pow(clamp(u), 3);
// Lifted for `up` s, then dropped from h with bounces (no jump at t = 0).
const hopDrop = (t, h, t0 = 0, up = 0.1) => (t < t0 ? 0 : t < t0 + up ? -h * easeOut((t - t0) / up) : drop(t, h, t0 + up));
// A half-sine bump 0 → 1 → 0 over d from t0.
const bump = (t, t0, d) => (t <= t0 || t >= t0 + d ? 0 : Math.sin((Math.PI * (t - t0)) / d));

// --------------------------------------------------------------------------- geometry
// Telegram's single-shape icons, cut into their natural parts (identical to the file at rest).

// The padlock: its body and its shackle (a 1.66 pt bar on a radius-5 arc; the file merges them).
const LOCK_BODY = 'M13 13L17 13C18.86 13 19.8 13 20.53 13.31C21.51 13.71 22.29 14.49 22.7 15.47C23 16.2 23 17.14 23 19C23 20.86 23 21.8 22.7 22.53C22.29 23.51 21.51 24.29 20.53 24.7C19.8 25 18.86 25 17 25L13 25C11.14 25 10.2 25 9.47 24.7C8.49 24.29 7.71 23.51 7.3 22.53C7 21.8 7 20.86 7 19C7 17.14 7 16.2 7.3 15.47C7.71 14.49 8.49 13.71 9.47 13.31C10.2 13 11.14 13 13 13Z';
const LOCK_SHACKLE = 'M10 19V10A5 5 0 0 1 20 10V14.2';   // the long leg stays in the body when it opens
// My Profile: the bust under the head, down to the ring (clipped by its inner edge, r 8.67).
const PROFILE_BUST = 'M8.5 20.73C9.58 19.21 11.52 17.84 15 17.84C18.48 17.84 20.41 19.21 21.5 20.73L26 20.73L26 31L4 31L4 20.73Z';
// Power Saving: the line the battery's charge jolts along on impact (a unit vector; the charge goes the
// other way, up and left).
const BOLT_CUT = [0.857, 0.514];
// Premium: where its five arms fly out — the star's ten outline points (tips at 0, 2, …) and centre.
const STAR_PTS = [[15, 4.8], [18, 11.2], [25, 12], [19.8, 16.8], [21.2, 23.7], [15, 20.2], [8.8, 23.7], [10.2, 16.8], [5, 12], [12, 11.2]];
const STAR_C = [15, 15.24];
// Saved Messages: the bookmark with a ribbon end that can flap (n: notch, f: tail flare,
// g: tail length; 0, 0, 0 is the file's shape).
function bookmark(n = 0, f = 0, g = 0) {
  const N = (y) => (y + n).toFixed(2);
  const R = (x) => (x + f).toFixed(2);
  const L = (x) => (x - f).toFixed(2);
  const Y = (y) => (y + g).toFixed(2);
  return `M7 12.4C7 10.16 7 9.04 7.44 8.18C7.82 7.43 8.43 6.82 9.18 6.44C10.04 6 11.16 6 13.4 6L16.6 6C18.84 6 19.96 6 20.82 6.44C21.57 6.82 22.18 7.43 22.56 8.18C23 9.04 23 10.16 23 12.4L23 19.71C23 21.39 23 22.23 ${R(22.66)} ${Y(22.64)}C${R(22.36)} ${Y(23.01)} ${R(21.92)} ${Y(23.21)} ${R(21.45)} ${Y(23.2)}C${R(20.91)} ${Y(23.18)} ${R(20.29)} ${Y(22.63)} 19.02 21.52L16.58 ${N(19.38)}C16.02 ${N(18.89)} 15.74 ${N(18.65)} 15.43 ${N(18.55)}C15.15 ${N(18.47)} 14.85 ${N(18.47)} 14.57 ${N(18.55)}C14.26 ${N(18.65)} 13.98 ${N(18.89)} 13.42 ${N(19.38)}L10.98 21.52C9.71 22.63 9.09 23.18 ${L(8.55)} ${Y(23.2)}C${L(8.08)} ${Y(23.21)} ${L(7.64)} ${Y(23.01)} ${L(7.34)} ${Y(22.64)}C7 22.23 7 21.39 7 19.71Z`;
}

// How Telegram's glyphs are cut where one outline holds parts that move apart (the native port,
// ios/LivingSettingsIcons, cuts them the same way; tools/golden-icons.mjs records these numbers).
export const CUTS = {
  // Send a Gift: the lid and the bow are one outline; they part where the bow meets the lid (y 9).
  // The lid reaches 0.25 pt up into the bow, so the cut never shows at rest.
  giftCut: 9,
  giftOverlap: 0.25,
  // Telegram FAQ: the question mark was drawn as a 1.66 pt stroke round a radius-3 arc; it is cut
  // out along that centre line (running on past both round ends), 3.2 pt wide.
  faqCenterLine: 'M12 14.2L12 13A3 3 0 0 1 18 13C18 14.25 17.3 15.25 16.25 15.75C15.45 16.13 15 16.6 15 17.3L15 18.6',
  faqRevealWidth: 3.2,
  // Telegram Premium: the star's concave corners (top-left, top-right, right, bottom, the tip of
  // the swoosh cut into it), its tips (arm 0 … 4), the centre of the core between the corners, and
  // a point out along the swoosh (between the bottom-left and left arms).
  starCorners: [[11.3, 10.55], [18.7, 10.5], [20.75, 17.3], [14.97, 21.6], [15.5, 15.15]],
  starTips: [[15, 5], [25, 12.4], [20.5, 24], [9, 23.6], [5.3, 12.4]],
  starCore: [16.5, 14.5],
  starSwooshOut: [3.3, 20.85],
  // Appearance: the dial's ring (inner radius) and the circle its half disc stays in (0.3 pt into
  // the ring: no seam).
  dialInner: 8.339844,
  dialOpening: 8.64,
  // Language: the globe turning — a disc cut by its latitudes and two meridians, 1.33 wide, the
  // prototype's meridian (rx 3.9 on an 8.6 globe) scaled to Telegram's (4.165 at the equator),
  // cross-faded from the banded globe in 0.06 s and back over the last 0.1 s.
  globe: { radius: 10, latitudes: [11.5, 18.5], gap: 1.330078, meridianScale: 4.165039 / 3.9, meridianHeight: 11, fadeIn: 0.06, fadeOut: 0.1 },
};
// Premium: arm i lies between corners i and i + 1 — from 22 % inside the core out past both corners
// and past its tip (the arms overlap the core: no seams).
const towardCore = (p, k) => [p[0] + (CUTS.starCore[0] - p[0]) * k, p[1] + (CUTS.starCore[1] - p[1]) * k];
const awayFromCore = (p, k) => [p[0] + (p[0] - CUTS.starCore[0]) * k, p[1] + (p[1] - CUTS.starCore[1]) * k];
export const STAR_WEDGES = [0, 1, 2, 3, 4].map((i) => {
  const a = CUTS.starCorners[i];
  const b = CUTS.starCorners[(i + 1) % 5];
  const outA = i === 4 ? CUTS.starSwooshOut : awayFromCore(a, 2.5);
  const outB = (i + 1) % 5 === 4 ? CUTS.starSwooshOut : awayFromCore(b, 2.5);
  return [towardCore(a, 0.22), outA, awayFromCore(CUTS.starTips[i], 0.6), outB, towardCore(b, 0.22)];
});
const polygon = (pts) => `M${pts.map((p) => p.join(' ')).join('L')}Z`;
const circle = (cx, cy, r) => `M${cx - r} ${cy}A${r} ${r} 0 1 0 ${cx + r} ${cy}A${r} ${r} 0 1 0 ${cx - r} ${cy}Z`;
const meridian = (rx, ry) => `M${15 - rx} 15A${rx} ${ry} 0 1 0 ${15 + rx} 15A${rx} ${ry} 0 1 0 ${15 - rx} 15Z`;

// --------------------------------------------------------------------------- rigs
// parts: name → subpath indexes (in file order), or { idx, parent } to move inside another part;
// pivots in icon pt (30 × 30). build(c): the parts made by hand instead (c.group / c.path /
// c.mask / c.clip, c.pieces = the file's shapes, c.refs for run). run(t, P, fx, refs):
// P[name].set({ r, x, y, sx, sy, kx, o, cx, cy }); fx.* adds effects.
export const RIGS = {
  'ic-bell': {
    parts: { clapper: [0], body: [1], dot: { idx: [2, 3], parent: 'body' } },
    duration: 1.15,
    run(t, P, fx) {
      const a = ring(t, 22, 3.2, 3.6);
      P.body.set({ r: a, cx: 15, cy: 5.6 });
      // The clapper hangs from the same pivot and lags behind the bell.
      const c = ring(t, 30, 3.2, 3.2, 0.05);
      P.clapper.set({ r: c, cx: 15, cy: 5.6 });
      // The badge swells on the first swing and settles with a little wobble.
      const d = 1 + 0.36 * bump(t, 0.08, 0.26) + ring(t, 0.07, 5, 8, 0.34);
      P.dot.set({ sx: d, sy: d, cx: 20.5, cy: 9.5 });
      fx.waves(t, 0.06, 2);
    },
  },
  'ic-phone': {
    // Cut across the middle of its handle: the two ends shake against each other.
    build(c) {
      const handset = c.group('handset');
      const d = c.pieces[0].attrs.d;
      c.path(d, {}, c.group('ear', handset)).setAttribute('clip-path', c.clip('M-5 -5H35.6L-5 35.6Z'));
      c.path(d, {}, c.group('mouth', handset)).setAttribute('clip-path', c.clip('M35 -5.6V35H-5.6Z'));
    },
    duration: 1.0,
    run(t, P, fx) {
      const on = t < 0.7 ? 1 : 0;
      const buzz = Math.sin(2 * Math.PI * 13 * t) * 14 * Math.exp(-3.4 * t) * on;
      P.handset.set({ r: buzz, cx: 15, cy: 15, sx: 1 + 0.08 * Math.exp(-6 * t), sy: 1 + 0.08 * Math.exp(-6 * t) });
      // The ends, a quarter-beat apart: the earpiece and the mouthpiece rattle in turn.
      const flex = Math.cos(2 * Math.PI * 13 * t) * 7 * Math.exp(-3.8 * t) * on;
      P.ear.set({ r: flex, cx: 11.95, cy: 18.03 });
      P.mouth.set({ r: -flex, cx: 11.95, cy: 18.03 });
      fx.waves(t, 0.0, 3);
    },
  },
  'ic-folder': {
    parts: { back: [1, 2], front: [0] },
    paper: true,
    duration: 1.0,
    run(t, P, fx) {
      // The flap swings open (foreshortened about its bottom hinge) and falls back with a bounce.
      const open = t < 0.22 ? easeOut(t / 0.22) : 1 - pop(t, 0.42, 0.22, 0.42);
      P.front.set({ sy: 1 - 0.45 * open, kx: -14 * open, cx: 15, cy: 23 });
      fx.paper(open);
    },
  },
  'ic-saved': {
    build(c) {
      c.refs.mark = c.path(bookmark(), {}, c.group('mark'));
    },
    duration: 1.05,
    run(t, P, fx, E) {
      // Lifted, dropped in with bounces and a squash…
      const y = hopDrop(t, 9, 0, 0.1);
      const land = 0.1 + Math.sqrt((2 * 9) / 2200);
      const squash = t > land - 0.01 ? Math.max(0, 1 - Math.abs(y) / 1.2) * Math.exp(-5 * (t - 0.1)) : 0;
      P.mark.set({ y, sy: 1 - 0.14 * squash, sx: 1 + 0.08 * squash, cx: 15, cy: 23 });
      // …and its ribbon end flaps as it lands: the tails swing down and out, the notch snaps up.
      E.mark.setAttribute('d', bookmark(ring(t, -2.2, 4.6, 6.5, land), ring(t, 0.7, 4.6, 6.5, land), ring(t, 1.3, 4.6, 6.5, land)));
    },
  },
  'ic-data': {
    parts: { top: [4, 5], middle: [0, 1], bottom: [2, 3] },
    duration: 1.0,
    run(t, P) {
      for (const [name, t0] of [['top', 0], ['middle', 0.07], ['bottom', 0.14]]) {
        const u = t - t0;
        const y = u < 0 ? 0 : -3.2 * Math.sin(Math.PI * clamp(u / 0.26)) + ring(u, 0.9, 4, 7, 0.26);
        // Each disk lands with a squash.
        const sq = u > 0.26 ? 0.1 * Math.exp(-12 * (u - 0.26)) : 0;
        P[name].set({ y, sy: 1 - sq, sx: 1 + 0.5 * sq, cx: 15, cy: name === 'top' ? 12 : name === 'middle' ? 18 : 24 });
      }
    },
  },
  'ic-devices': {
    parts: { laptop: [2], screen: { idx: [3], parent: 'laptop' }, phone: [0, 1, 4, 5] },
    duration: 1.0,
    run(t, P, fx) {
      P.laptop.set({ y: -3 * Math.sin(Math.PI * clamp(t / 0.24)) + ring(t, 0.8, 4, 7, 0.24) });
      // The laptop's lid shuts on its hinge and springs open again.
      P.screen.set({ sy: 1 - 0.72 * bump(t, 0.02, 0.3) + ring(t, 0.07, 4.5, 7, 0.32), cx: 9.85, cy: 18.66 });
      P.phone.set({ y: -3.4 * Math.sin(Math.PI * clamp((t - 0.12) / 0.24)) + ring(t, 0.8, 4, 7, 0.36), r: ring(t, 8, 3, 5, 0.12), cx: 20, cy: 22 });
      fx.glow(t, 0.15, 0.5);
    },
  },
  'ic-lock': {
    build(c) {
      const lock = c.group('lock');
      c.path(LOCK_SHACKLE, { stroke: true, sw: 1.66 }, c.group('shackle', lock));
      c.path(LOCK_BODY, {}, c.group('body', lock));
    },
    duration: 1.2,
    run(t, P, fx) {
      // The lock hops; in the air its shackle springs up out of the body and swings open on
      // its long leg, holds, then swings back and slams down: a click (the body squashes, the
      // shackle bounces) and a glint.
      const lift = t < 0.16 ? -3 * easeOut(t / 0.16) : -3 + 3 * pop(t, 0.2, 0.16, 0.55);
      const shut = 1 - easeIn((t - 0.56) / 0.11);
      const rise = -2.7 * pop(t, 0.22, 0.03, 0.6) * shut + ring(t, -0.7, 7, 11, 0.67);
      const swing = -28 * pop(t, 0.34, 0.14, 0.5) * shut;
      const click = t > 0.67 ? Math.exp(-13 * (t - 0.67)) : 0;
      P.lock.set({ y: lift + 0.6 * click, cx: 15, cy: 25 });
      P.shackle.set({ y: rise, r: swing, cx: 10, cy: 15.6 });
      P.body.set({ sy: 1 - 0.1 * click, sx: 1 + 0.06 * click, cx: 15, cy: 25 });
      fx.glint(t, 0.64);
    },
  },
  'ic-profile': {
    // The ring with the person cut out of it (a mask), so the person can move inside.
    build(c) {
      const m = c.mask();
      c.path('M15 5a10 10 0 1 1 0 20a10 10 0 1 1 0-20z', { color: '#fff' }, m.el);
      const inner = c.group(null, m.el);
      inner.setAttribute('clip-path', c.clip('M15 6.33a8.67 8.67 0 1 1 0 17.34a8.67 8.67 0 1 1 0-17.34z'));
      c.path(PROFILE_BUST, { color: '#000' }, c.group('bust', inner));
      c.path('M15 8.66a3.5 3.5 0 1 1 0 7a3.5 3.5 0 1 1 0-7z', { color: '#000' }, c.group('head', m.el));
      const all = c.group('profile');
      const r = c.rect(all);
      r.setAttribute('mask', m.url);
    },
    duration: 1.05,
    run(t, P, fx) {
      const y = -3.4 * Math.sin(Math.PI * clamp(t / 0.26)) + ring(t, 0.7, 4, 7, 0.26);
      P.profile.set({ y, cx: 15, cy: 25 });
      fx.halo(t, 0.05);
      // The person ducks, pops back up (the head a beat later, overshooting) and nods.
      const duck = (d, t0, r, z) => (t < t0 ? d * easeIn(t / t0) : d * (1 - pop(t, r, t0, z)));
      P.bust.set({ y: duck(3.4, 0.12, 0.36, 0.42) });
      const hs = 1 + 0.12 * bump(t, 0.22, 0.26);
      P.head.set({ y: duck(4.8, 0.15, 0.34, 0.36), sx: hs, sy: hs, r: ring(t, 10, 2.3, 4.2, 0.46), cx: 15, cy: 15.6 });
    },
  },
  'ic-proxy': {
    // The shield with its two arrows cut out (a mask): the arrows run through it, one each way.
    build(c) {
      const shield = c.pieces[0].attrs.d;
      const m = c.mask();
      c.path(shield, { color: '#fff' }, m.el);
      const inside = c.group(null, m.el);
      inside.setAttribute('clip-path', c.clip(shield, 'translate(15 15) scale(0.8) translate(-15 -15)'));
      c.path(c.pieces[2].attrs.d, { color: '#000' }, c.group('right', inside));
      c.path(c.pieces[1].attrs.d, { color: '#000' }, c.group('left', inside));
      c.rect(c.group('shield')).setAttribute('mask', m.url);
    },
    duration: 1.05,
    run(t, P, fx) {
      const s = 1 + 0.16 * Math.sin(Math.PI * clamp(t / 0.3)) * (1 - clamp((t - 0.3) / 0.4));
      P.shield.set({ sx: s, sy: s, cx: 15, cy: 15 });
      // Out one side, back in from the other (hidden behind the rim on the way round).
      const run = (t0, sign) => {
        const u = clamp((t - t0) / 0.46);
        let x = 24 * ease(u);
        if (x > 12) x -= 24;
        return sign * x;
      };
      P.right.set({ x: run(0.08, 1) });
      P.left.set({ x: run(0.18, -1) });
      fx.glint(t, 0.12);
    },
  },
  'ic-stars': {
    // The disc with the star cut out (a mask): the star spins inside it.
    build(c) {
      const m = c.mask();
      c.path(c.pieces[0].attrs.d, { color: '#fff' }, m.el);
      c.path(c.pieces[1].attrs.d, { color: '#000' }, c.group('star', m.el));
      c.rect(c.group('disc')).setAttribute('mask', m.url);
    },
    duration: 1.1,
    run(t, P, fx) {
      // A full turn (the star isn't symmetric: it ends where it began) with a pop, the disc
      // giving under it.
      const turn = 360 * easeOut(t / 0.62) + ring(t, 8, 2.5, 6, 0.62);
      const s = 1 + 0.22 * bump(t, 0, 0.42) + ring(t, 0.05, 3, 6, 0.42);
      P.star.set({ r: turn, sx: s, sy: s, cx: 15, cy: 14.6 });
      const d = 1 - 0.05 * bump(t, 0, 0.16) + 0.04 * bump(t, 0.16, 0.24);
      P.disc.set({ sx: d, sy: d, cx: 15, cy: 15 });
      fx.sparkles(t, 0.1, 5, '#ffe9a8');
    },
  },
  'ic-premium': {
    // Telegram's star (five rounded arms, a swoosh cut in to its centre) as its core and five arms,
    // cut by clips at its concave corners: the arms fly out while it spins and snap back.
    build(c) {
      const star = c.group('star');
      const d = c.pieces[0].attrs.d;
      c.path(d, { rule: 'evenodd' }, c.group('core', star)).setAttribute('clip-path', c.clip(polygon(CUTS.starCorners)));
      STAR_WEDGES.forEach((w, i) => c.path(d, { rule: 'evenodd' }, c.group(`arm${i}`, star)).setAttribute('clip-path', c.clip(polygon(w))));
    },
    duration: 1.15,
    spin3d: true,
    run(t, P, fx) {
      fx.spin3d(t, 0, 0.7);
      for (let i = 0; i < 5; i++) {
        const tip = STAR_PTS[2 * i];
        const dx = tip[0] - STAR_C[0];
        const dy = tip[1] - STAR_C[1];
        const l = Math.hypot(dx, dy);
        const out = 1.9 * bump(t, 0.06 + i * 0.035, 0.42) + ring(t, 0.35, 4, 8, 0.48 + i * 0.035);
        P[`arm${i}`].set({ x: (dx / l) * out, y: (dy / l) * out });
      }
      const k = 1 - 0.14 * bump(t, 0.06, 0.4);
      P.core.set({ sx: k, sy: k, cx: STAR_C[0], cy: STAR_C[1] });
      fx.sparkles(t, 0.12, 7, '#ffffff');
    },
  },
  'ic-power': {
    // Telegram's battery: its shell and terminal, and the charge inside (`top`). The shell stays put
    // (`bottom` is empty) so the charge jolts inside it.
    build(c) {
      const bolt = c.group('bolt');
      c.path([0, 1, 3].map((i) => c.pieces[i].attrs.d).join(' '), {}, bolt);
      c.group('bottom', bolt);
      c.path(c.pieces[2].attrs.d, {}, c.group('top', bolt));
    },
    duration: 0.95,
    run(t, P, fx) {
      // Raised, then it strikes; on impact its charge jolts out of place and snaps back (twice, the
      // second smaller).
      const strike = t < 0.06 ? -4 * easeOut(t / 0.06) : t < 0.13 ? -4 + 4 * ((t - 0.06) / 0.07) : ring(t, 1.2, 6, 9, 0.13);
      const s = 1 + 0.22 * Math.exp(-7 * Math.max(0, t - 0.06)) * (t < 0.06 ? t / 0.06 : 1);
      P.bolt.set({ y: strike, sx: s, sy: s, cx: 15, cy: 15 });
      const crack = 1.5 * bump(t, 0.13, 0.12) + 0.7 * bump(t, 0.27, 0.1);
      P.top.set({ x: -BOLT_CUT[0] * crack, y: -BOLT_CUT[1] * crack });
      P.bottom.set({ x: BOLT_CUT[0] * crack, y: BOLT_CUT[1] * crack });
      fx.glow(t, 0.1, 0.42);
      fx.sparkles(t, 0.12, 4, '#fff3b0');
    },
  },
  'ic-language': {
    // Telegram's banded globe at rest; while it turns, the same globe drawn as a disc cut by its
    // latitudes and two moving meridians (a mask), cross-faded in and out (fx.globe).
    build(c) {
      const G = CUTS.globe;
      const globe = c.group('globe');
      // The two globes add up (plus-lighter, in a group of their own) at 1 − w and w: a true cross-fade,
      // which does not dim where both are white.
      globe.style.isolation = 'isolate';
      const rest = c.group(null, globe);
      c.path(c.pieces.map((p) => p.attrs.d).join(' '), {}, rest);
      const m = c.mask();
      c.path(circle(15, 15, G.radius), { color: '#fff' }, m.el);
      c.path(G.latitudes.map((y) => `M3 ${y}H27`).join(''), { stroke: true, sw: G.gap, color: '#000' }, m.el);
      const meridians = [0, 1].map(() => c.path(meridian(3.9 * G.meridianScale, G.meridianHeight), { stroke: true, sw: G.gap, color: '#000' }, m.el));
      const turning = c.group(null, globe);
      turning.setAttribute('opacity', '0');
      turning.style.mixBlendMode = 'plus-lighter';
      c.rect(turning).setAttribute('mask', m.url);
      c.refs.globe = { rest, turning, meridians };
    },
    globe: true,
    duration: 1.15,
    run(t, P, fx) {
      fx.globe(easeOut(t / 1.05));
    },
  },
  'ic-gift': {
    // Telegram's gift: the box's two halves, and the lid with the bow in one outline, parted where
    // the bow meets the lid (CUTS.giftCut).
    build(c) {
      const top = c.pieces[2].attrs.d;
      c.path(top, {}, c.group('lid')).setAttribute('clip-path', c.clip(`M-5 ${CUTS.giftCut - CUTS.giftOverlap}H35V35H-5Z`));
      c.path(`${c.pieces[0].attrs.d} ${c.pieces[1].attrs.d}`, {}, c.group('box'));
      c.path(top, {}, c.group('bow')).setAttribute('clip-path', c.clip(`M-5 -5H35V${CUTS.giftCut}H-5Z`));
    },
    duration: 1.1,
    run(t, P, fx) {
      const up = t < 0.16 ? easeOut(t / 0.16) : 1 - pop(t, 0.3, 0.16, 0.45);
      P.lid.set({ y: -4.5 * up, r: -9 * up, cx: 23.8, cy: 15.2 });
      P.bow.set({ y: -5.5 * up, r: -9 * up + ring(t, 10, 4, 5, 0.2), cx: 23.8, cy: 15.2 });
      fx.confetti(t, 0.1);
    },
  },
  'ic-business': {
    // Telegram's shop: its awning (the lid that pops open) and the shop under it with its window
    // (the base).
    build(c) {
      const cs = c.group('case');
      c.path(`${c.pieces[0].attrs.d} ${c.pieces[1].attrs.d}`, { rule: 'evenodd' }, c.group('base', cs));
      c.path(c.pieces[2].attrs.d, { rule: 'evenodd' }, c.group('lid', cs));
    },
    duration: 1.0,
    run(t, P) {
      const y = -3 * Math.sin(Math.PI * clamp(t / 0.24)) + ring(t, 0.8, 4, 7, 0.24);
      P.case.set({ y, r: ring(t, 9, 3.4, 4.5, 0.05), cx: 15, cy: 8 });
      // At the top of the hop the awning pops open a crack, and it snaps shut as the shop lands.
      const open = bump(t, 0.06, 0.22);
      const snap = t > 0.28 ? Math.exp(-14 * (t - 0.28)) : 0;
      P.lid.set({ y: -1.7 * open, r: -5 * open, cx: 6, cy: 15 });
      P.base.set({ sy: 1 - 0.08 * snap, sx: 1 + 0.04 * snap, cx: 15, cy: 23.3 });
    },
  },
  'ic-ask': {
    // Telegram's bubble with its three dots cut out (a mask): the dots are the typing dots (fx.dots).
    build(c) {
      const m = c.mask();
      c.path(c.pieces[0].attrs.d, { color: '#fff' }, m.el);
      c.refs.dots = [1, 2, 3].map((i) => {
        const g = c.group(null, m.el);
        c.path(c.pieces[i].attrs.d, { color: '#000' }, g);
        return g;
      });
      c.rect(c.group('bubble')).setAttribute('mask', m.url);
    },
    dots: true,
    duration: 1.2,
    run(t, P, fx) {
      const s = 0.82 + 0.18 * pop(t, 0.3, 0, 0.45);
      // A jelly wobble as it lands (wider, then taller).
      const w = ring(t, 0.07, 3.6, 5.5, 0.18);
      P.bubble.set({ sx: s * (1 + w), sy: s * (1 - w), cx: 9, cy: 22 });
      fx.dots(t, 0.18);
    },
  },
  'ic-faq': {
    // Telegram's disc with the question mark and its dot cut out (a mask). The mark is cut by a
    // stroke along its centre line, clipped to its outline, which the rig undraws and draws again.
    build(c) {
      const m = c.mask();
      c.path(c.pieces[0].attrs.d, { color: '#fff' }, m.el);
      c.path(CUTS.faqCenterLine, { stroke: true, sw: CUTS.faqRevealWidth, color: '#000' }, c.group('mark', m.el)).setAttribute('clip-path', c.clip(c.pieces[2].attrs.d));
      c.path(c.pieces[1].attrs.d, { color: '#000' }, c.group('dot', m.el));
      c.rect(c.group(null)).setAttribute('mask', m.url);
    },
    duration: 1.1,
    run(t, P) {
      // The question mark writes itself again (undrawn and drawn along its stroke), then wobbles;
      // the dot hops and drops back in.
      const d = t < 0.12 ? easeIn(t / 0.12) : 1 - easeOut((t - 0.12) / 0.32);
      P.mark.dash(d);
      P.mark.set({ r: ring(t, 16, 2.8, 4.2, 0.4), cx: 15.2, cy: 19 });
      P.dot.set({ y: hopDrop(t, 4, 0.3, 0.08) });
    },
  },
  'ic-features': {
    // Telegram's lamp: its bulb (piece 1) and its base (piece 0).
    build(c) {
      const lamp = c.group('lamp');
      c.path(c.pieces[1].attrs.d, {}, c.group('bulb', lamp));
      c.path(c.pieces[0].attrs.d, {}, c.group('base', lamp));
      // The glass catches a highlight as it lights (drawn in the tile's colour).
      c.refs.shine = c.path('M11.2 11.6a3.9 3.9 0 0 1 3.2-3.7', { stroke: true, sw: 1.3, cap: 'round', color: c.tileColor }, c.group('shine', lamp));
      c.refs.shine.setAttribute('pathLength', '1');
      c.refs.shine.setAttribute('stroke-dasharray', '1');
      c.refs.shine.setAttribute('stroke-dashoffset', '1');
    },
    duration: 1.05,
    run(t, P, fx, E) {
      const r = ring(t, 9, 2.6, 4.4);
      P.lamp.set({ r, cx: 15, cy: 4 });
      // The bulb swells as it lights; the base screws itself in (squeezes as it turns).
      const glow = bump(t, 0.05, 0.5);
      P.bulb.set({ sx: 1 + 0.06 * glow, sy: 1 + 0.06 * glow, cx: 15, cy: 11 });
      const turn = Math.abs(Math.sin(2 * Math.PI * 3 * clamp((t - 0.04) / 0.5))) * (1 - clamp((t - 0.04) / 0.5));
      P.base.set({ sx: 1 - 0.22 * turn, y: -0.5 * turn, cx: 15, cy: 22.7 });
      const drawn = easeOut((t - 0.12) / 0.25);
      E.shine.setAttribute('stroke-dashoffset', (1 - drawn).toFixed(3));
      E.shine.setAttribute('opacity', drawn <= 0.001 ? '0' : (1 - clamp((t - 0.6) / 0.3)).toFixed(3));
      fx.glow(t, 0.05, 0.6);
      fx.rays(t, 0.1);
    },
  },
  'ic-appearance': {
    // Telegram's dial: its ring (the handle) and the half disc filling its left side (the tip), which
    // stays inside the ring's opening.
    build(c) {
      const brush = c.group('brush');
      c.path(`${c.pieces[0].attrs.d} ${circle(15, 15, CUTS.dialInner)}`, { rule: 'evenodd' }, c.group('handle', brush));
      const opening = c.group(null, brush);
      opening.setAttribute('clip-path', c.clip(circle(15, 15, CUTS.dialOpening)));
      c.path('M15 4L15 26L4 26L4 4Z', {}, c.group('tip', opening));
    },
    duration: 1.05,
    run(t, P, fx) {
      // A brush stroke: wind up, paint, settle — the dial swings, its half disc trailing; a stroke of
      // paint under it.
      const a = t < 0.14 ? -18 * easeOut(t / 0.14) : -18 + 30 * easeOut((t - 0.14) / 0.2) - 12 * pop(t, 0.3, 0.34, 0.5);
      P.brush.set({ r: a, cx: 12, cy: 18 });
      const lag = t < 0.14 ? 10 * easeOut(t / 0.14) : 10 - 26 * easeOut((t - 0.14) / 0.2) + 16 * pop(t, 0.34, 0.34, 0.32);
      const press = bump(t, 0.2, 0.22);
      P.tip.set({ r: lag, sx: 1 + 0.12 * press, sy: 1 - 0.1 * press, cx: 13.4, cy: 16.4 });
      fx.stroke(t, 0.2);
    },
  },
  money: {
    element: true,            // Telegram's gem (a bitmap, settings-screen.js): the element itself turns
    duration: 1.1,
    run(t, P, fx, E) {
      fx.spin3d(t, 0, 0.75);
      // The sparkle inside it turns a quarter and flares as the gem comes round.
      if (E.inner) {
        const s = 1 + 0.45 * bump(t, 0.25, 0.45);
        E.inner.setAttribute('transform', `rotate(${(90 * easeOut((t - 0.2) / 0.6)).toFixed(1)} 15 13.4) translate(15 13.4) scale(${s.toFixed(3)}) translate(-15 -13.4)`);
      }
      fx.sparkles(t, 0.15, 6, '#bfe6ff');
    },
  },
  'set-emoji-status': {
    parts: { leftEye: [0, 1], rightEye: [2, 3], smile: [4, 5, 6, 7, 8], pencil: [9, 10, 11, 12, 13, 14], face: 'rest' },
    duration: 1.0,
    run(t, P) {
      const blink = t > 0.18 && t < 0.42 ? 1 - Math.sin(Math.PI * (t - 0.18) / 0.24) * 0.9 : 1;
      const y = -2.4 * Math.sin(Math.PI * clamp(t / 0.24)) + ring(t, 0.6, 4, 7, 0.24);
      P.leftEye.set({ y, cx: 19, cy: 12.7 });
      P.rightEye.set({ y, sy: blink, cx: 19, cy: 12.7 });
      P.face.set({ y });
      // The smile widens with the wink…
      const grin = 0.18 * bump(t, 0.16, 0.34);
      P.smile.set({ y: y + 0.4 * grin, sx: 1 + grin, sy: 1 + 0.6 * grin, cx: 15, cy: 18.5 });
      // …and the pencil scribbles (pivoting on its point, sliding along its length).
      const u = t - 0.22;
      const w = u > 0 ? Math.sin(2 * Math.PI * 3.4 * u) * Math.exp(-3.2 * u) : 0;
      P.pencil.set({ y: y - 0.6 * w, x: 0.6 * w, r: 9 * w, cx: 16.6, cy: 29.2 });
    },
  },
  'set-avatar': {
    parts: { camera: [], body: { idx: [0, 5], parent: 'camera' }, lens: { idx: [1, 2], parent: 'camera' }, flash: { idx: [3], parent: 'camera' }, plus: { idx: [4], parent: 'camera' } },
    duration: 1.0,
    run(t, P, fx) {
      const s = 1 - 0.1 * Math.sin(Math.PI * clamp(t / 0.16)) + ring(t, 0.04, 4, 6, 0.16);
      P.camera.set({ sx: s, sy: s, cx: 15, cy: 15 });
      // The shot: the lens zooms in and back, the flash bulb fires, and the plus spins in.
      const z = 1 - 0.18 * bump(t, 0, 0.14) + 0.14 * bump(t, 0.12, 0.2) + ring(t, 0.03, 4, 7, 0.32);
      P.lens.set({ sx: z, sy: z, cx: 15, cy: 15.3 });
      const f = 1 + 0.9 * bump(t, 0.08, 0.2);
      P.flash.set({ sx: f, sy: f, cx: 22.5, cy: 11.25 });
      const p = 1 + 0.25 * bump(t, 0.12, 0.3);
      P.plus.set({ r: 90 * pop(t, 0.36, 0.12, 0.5), sx: p, sy: p, cx: 5.5, cy: 22 });
      fx.flash(t, 0.1);
    },
  },
  'set-covercolor': {
    parts: {
      palette: [],
      frame: { idx: [0, 1, 2, 3, 4, 6, 9], parent: 'palette' },
      avatar: { idx: [7, 8], parent: 'palette' },
      bar: { idx: [5], parent: 'palette' },
      s1: { idx: [10], parent: 'palette' },
      s2: { idx: [11], parent: 'palette' },
      s3: { idx: [12, 13], parent: 'palette' },
    },
    duration: 1.15,
    hue: true,
    run(t, P, fx) {
      P.palette.set({ r: ring(t, 12, 2.4, 4), cx: 15, cy: 15 });
      // The photo pops, the name bar slides out under it and the sparkles twinkle in turn.
      const a = 1 + 0.16 * bump(t, 0.04, 0.3) + ring(t, 0.03, 4, 7, 0.34);
      P.avatar.set({ sx: a, sy: a, cx: 15, cy: 13.5 });
      P.bar.set({ sx: 0.55 + 0.45 * pop(t, 0.34, 0.1, 0.55), cx: 15.25, cy: 20.5 });
      [['s1', 6.5, 6.5, 0.1], ['s2', 25, 12, 0.2], ['s3', 11, 25, 0.3]].forEach(([k, cx, cy, t0]) => {
        const v = 1 - 0.85 * bump(t, t0, 0.12) + (t > t0 + 0.12 ? 0.5 * bump(t, t0 + 0.12, 0.24) : 0);
        P[k].set({ sx: v, sy: v, r: 90 * easeOut((t - t0) / 0.4), cx, cy });
      });
      fx.hue(t, 0.95);
    },
  },
};

// --------------------------------------------------------------------------- loading

const svgCache = new Map();
let UID = 0;
function fetchIcon(url) {
  if (!svgCache.has(url)) svgCache.set(url, fetch(url).then((r) => r.text()));
  return svgCache.get(url);
}

function splitSubpaths(d) {
  return d.trim().split(/(?=[Mm])/).map((s) => s.trim()).filter(Boolean);
}

// Every drawable piece of the icon, in file order, subpaths split: { d | shape, attrs }.
function parse(text) {
  const doc = new DOMParser().parseFromString(text, 'image/svg+xml');
  const out = [];
  doc.querySelectorAll('path,circle,ellipse,rect,line,polyline,polygon').forEach((n, src) => {
    const stroked = (n.getAttribute('stroke') || n.closest('g')?.getAttribute('stroke')) && (n.getAttribute('fill') === 'none' || n.closest('g')?.getAttribute('fill') === 'none');
    const sw = n.getAttribute('stroke-width') || n.closest('g')?.getAttribute('stroke-width') || '1.6';
    const lc = n.getAttribute('stroke-linecap') || '';
    if (n.tagName === 'path') {
      const rule = n.getAttribute('fill-rule') || 'nonzero';
      for (const sp of splitSubpaths(n.getAttribute('d') || '')) out.push({ tag: 'path', attrs: { d: sp, 'fill-rule': rule }, stroked, sw, lc, src });
    } else {
      const attrs = {};
      for (const a of n.attributes) if (!['fill', 'stroke', 'stroke-width'].includes(a.name)) attrs[a.name] = a.value;
      out.push({ tag: n.tagName, attrs, stroked, sw, lc, src });
    }
  });
  return out;
}

// --------------------------------------------------------------------------- player

export class LivingIcons {
  constructor({ iconURL }) {
    this.iconURL = iconURL;
    this.current = null;
  }

  // Warm the cache for the rows (so a return never waits for the network).
  prefetch(names) {
    for (const n of names) fetchIcon(this.iconURL(n)).catch(() => {});
  }

  // row: { el, icon (file name), tile (the coloured tile or null), glyph (the mask element), color }
  async play(row, now) {
    const rig = RIGS[row.icon];
    if (!rig || !row.glyph) return;
    this.stop();
    let text = '<svg/>';
    if (!rig.element) {
      try { text = await fetchIcon(this.iconURL(row.icon)); } catch (_) { return; }
    }
    const pieces = parse(text);
    const host = row.glyph.parentElement;
    const box = { left: row.glyph.offsetLeft, top: row.glyph.offsetTop, w: row.glyph.offsetWidth, h: row.glyph.offsetHeight };
    const color = row.color || getComputedStyle(row.glyph).color || '#fff';
    // Inline SVG in the glyph's place, parts as groups.
    const svg = document.createElementNS(SVGNS, 'svg');
    svg.setAttribute('viewBox', '0 0 30 30');
    svg.setAttribute('width', box.w);
    svg.setAttribute('height', box.h);
    svg.style.cssText = `position:absolute;left:${box.left}px;top:${box.top}px;overflow:visible;pointer-events:none;color:${color}`;
    const groups = {};
    const used = new Set();
    const tileColor = row.tileColor || color;
    const mk = (name, parent) => {
      const g = document.createElementNS(SVGNS, 'g');
      (parent || svg).appendChild(g);
      if (name) groups[name] = g;
      return g;
    };
    // Subpaths of one source path stay in one <path> (its holes keep cutting).
    const joined = new Map();   // group element → src → path element
    const add = (g, idx) => {
      const p = pieces[idx];
      if (!p) return;
      used.add(idx);
      if (p.tag === 'path') {
        let bySrc = joined.get(g);
        if (!bySrc) { bySrc = new Map(); joined.set(g, bySrc); }
        const prev = bySrc.get(p.src);
        if (prev) { prev.setAttribute('d', `${prev.getAttribute('d')} ${p.attrs.d}`); return; }
      }
      const e = document.createElementNS(SVGNS, p.tag);
      for (const [k, v] of Object.entries(p.attrs)) e.setAttribute(k, v);
      if (p.tag === 'path') joined.get(g).set(p.src, e);
      if (p.stroked) {
        e.setAttribute('fill', 'none');
        e.setAttribute('stroke', 'currentColor');
        e.setAttribute('stroke-width', p.sw);
        if (p.lc) e.setAttribute('stroke-linecap', p.lc);
      } else {
        e.setAttribute('fill', 'currentColor');
      }
      g.appendChild(e);
    };
    // Paper (folder) goes between the back and the flap.
    let paper = null;
    for (const [name, spec] of Object.entries(rig.parts || {})) {
      if (spec === 'all' || spec === 'rest') continue;
      const idx = Array.isArray(spec) ? spec : spec.idx;
      const g = mk(name, !Array.isArray(spec) && spec.parent ? groups[spec.parent] : null);
      idx.forEach((i) => add(g, i));
      if (rig.paper && name === 'back') {
        paper = document.createElementNS(SVGNS, 'rect');
        paper.setAttribute('x', '9');
        paper.setAttribute('width', '12');
        paper.setAttribute('height', '9');
        paper.setAttribute('rx', '1.2');
        paper.setAttribute('fill', 'currentColor');
        paper.setAttribute('opacity', '0.92');
        svg.appendChild(paper);
      }
    }
    const restName = Object.entries(rig.parts || {}).find(([, v]) => v === 'all' || v === 'rest')?.[0];
    if (restName) {
      const g = mk(restName);
      pieces.forEach((_, i) => { if (!used.has(i)) add(g, i); });
    }
    // Parts made by hand (an icon whose file merges them, or cut-outs that move: masks).
    const refs = {};
    if (rig.build) {
      let defs = null;
      let n = 0;
      const uid = `li${++UID}`;
      const def = (tag) => {
        if (!defs) { defs = document.createElementNS(SVGNS, 'defs'); svg.insertBefore(defs, svg.firstChild); }
        const e = document.createElementNS(SVGNS, tag);
        e.id = `${uid}-${++n}`;
        defs.appendChild(e);
        return e;
      };
      rig.build({
        pieces, refs, tileColor,
        group: (name, parent) => mk(name, parent),
        path(d, o = {}, parent) {
          const e = document.createElementNS(SVGNS, 'path');
          e.setAttribute('d', d);
          if (o.stroke) {
            e.setAttribute('fill', 'none');
            e.setAttribute('stroke', o.color || 'currentColor');
            e.setAttribute('stroke-width', o.sw || 1.6);
            if (o.cap) e.setAttribute('stroke-linecap', o.cap);
          } else {
            e.setAttribute('fill', o.color || 'currentColor');
            if (o.rule) e.setAttribute('fill-rule', o.rule);
          }
          (parent || svg).appendChild(e);
          return e;
        },
        rect(parent) {
          const e = document.createElementNS(SVGNS, 'rect');
          for (const [k, v] of [['x', -5], ['y', -5], ['width', 40], ['height', 40], ['fill', 'currentColor']]) e.setAttribute(k, v);
          (parent || svg).appendChild(e);
          return e;
        },
        clip(d, transform) {
          const c = def('clipPath');
          const e = document.createElementNS(SVGNS, 'path');
          e.setAttribute('d', d);
          if (transform) e.setAttribute('transform', transform);
          c.appendChild(e);
          return `url(#${c.id})`;
        },
        mask() {
          const m = def('mask');
          for (const [k, v] of [['maskUnits', 'userSpaceOnUse'], ['x', -5], ['y', -5], ['width', 40], ['height', 40]]) m.setAttribute(k, v);
          return { el: m, url: `url(#${m.id})` };
        },
      });
    }
    // Money: the sparkle that turns inside the gem (marked data-inner).
    if (rig.element) refs.inner = row.glyph.querySelectorAll('[data-inner]')[0] || null;
    if (!rig.element) {
      host.appendChild(svg);
      row.glyph.style.visibility = 'hidden';
    }

    // Effects layer: around the tile (particles may leave it), and inside it (sheen, glow).
    const tile = row.tile;
    const fxLayer = document.createElement('div');
    fxLayer.style.cssText = `position:absolute;left:${(tile || row.glyph).offsetLeft - 20}px;top:${(tile || row.glyph).offsetTop - 20}px;width:${(tile || row.glyph).offsetWidth + 40}px;height:${(tile || row.glyph).offsetHeight + 40}px;pointer-events:none;overflow:visible;z-index:4`;
    (tile ? tile.parentElement : host).appendChild(fxLayer);
    let sheen = null;
    if (tile) {
      sheen = document.createElement('div');
      sheen.style.cssText = 'position:absolute;inset:-40%;background:linear-gradient(115deg,rgba(255,255,255,0) 40%,rgba(255,255,255,0.55) 50%,rgba(255,255,255,0) 60%);pointer-events:none;z-index:5;transform:translateX(-100%)';
      tile.appendChild(sheen);
    }
    const P = {};
    for (const [name, g] of Object.entries(groups)) {
      P[name] = {
        el: g,
        set({ r = 0, x = 0, y = 0, sx = 1, sy = 1, kx = 0, o = 1, cx = 15, cy = 15 } = {}) {
          g.setAttribute('transform', `translate(${(x + cx).toFixed(2)} ${(y + cy).toFixed(2)}) rotate(${r.toFixed(2)}) skewX(${kx.toFixed(2)}) scale(${sx.toFixed(3)} ${sy.toFixed(3)}) translate(${-cx} ${-cy})`);
          if (o !== 1) g.setAttribute('opacity', o.toFixed(3));
        },
        // A stroked part drawn back (0: whole … 1: none).
        dash(v) {
          for (const e of g.querySelectorAll('[stroke]')) {
            if (!e.hasAttribute('pathLength')) { e.setAttribute('pathLength', '1'); e.setAttribute('stroke-dasharray', '1 1.01'); }
            e.setAttribute('stroke-dashoffset', clamp(v).toFixed(3));
            // Fully drawn back it's gone (a round cap would leave a dot).
            e.setAttribute('opacity', v >= 0.995 ? '0' : '1');
          }
        },
      };
    }
    const fx = {
      waves(t, t0, n) {
        // Sound waves: arcs on both sides, expanding and fading.
        const u = (t - t0) / 0.6;
        if (!fx._waves) {
          fx._waves = [];
          for (let i = 0; i < n * 2; i++) {
            const a = document.createElementNS(SVGNS, 'path');
            const side = i % 2 ? 1 : -1;
            a.setAttribute('d', side > 0 ? 'M25 10.5a6 6 0 0 1 0 9' : 'M5 10.5a6 6 0 0 0 0 9');
            a.setAttribute('fill', 'none');
            a.setAttribute('stroke', 'currentColor');
            a.setAttribute('stroke-width', '1.4');
            a.setAttribute('stroke-linecap', 'round');
            svg.appendChild(a);
            fx._waves.push({ a, side, k: Math.floor(i / 2) });
          }
        }
        for (const w of fx._waves) {
          const v = clamp(u - w.k * 0.18);
          w.a.setAttribute('opacity', (v > 0 && v < 1 ? Math.sin(Math.PI * v) : 0).toFixed(3));
          w.a.setAttribute('transform', `translate(${(w.side * 3.5 * v).toFixed(2)} 0)`);
        }
      },
      glow(t, t0, k) {
        const v = t < t0 ? 0 : Math.sin(Math.PI * clamp((t - t0) / 0.5));
        svg.style.filter = v > 0.01 ? `drop-shadow(0 0 ${(4 * v).toFixed(1)}px rgba(255,255,255,${(k * v).toFixed(2)}))` : '';
      },
      glint(t, t0) {
        if (!sheen) return;
        const u = clamp((t - t0) / 0.45);
        sheen.style.transform = `translateX(${(-100 + 200 * ease(u)).toFixed(1)}%)`;
      },
      halo(t, t0) {
        if (!fx._halo) {
          fx._halo = document.createElement('div');
          fx._halo.style.cssText = `position:absolute;left:20px;top:20px;width:${(tile || row.glyph).offsetWidth}px;height:${(tile || row.glyph).offsetHeight}px;border-radius:9px;box-shadow:0 0 0 2px ${tileColor};opacity:0`;
          fxLayer.appendChild(fx._halo);
        }
        const u = clamp((t - t0) / 0.55);
        fx._halo.style.opacity = (u > 0 && u < 1 ? (1 - u) * 0.8 : 0).toFixed(3);
        fx._halo.style.transform = `scale(${(1 + 0.45 * easeOut(u)).toFixed(3)})`;
      },
      sparkles(t, t0, n, c) {
        if (!fx._sp) {
          fx._sp = [];
          for (let i = 0; i < n; i++) {
            const s = document.createElement('div');
            const a = (i / n) * 360 + 20 * Math.sin(i * 7.1);
            s.style.cssText = `position:absolute;left:50%;top:50%;width:7px;height:7px;margin:-3.5px;opacity:0;background:${c};clip-path:polygon(50% 0,62% 38%,100% 50%,62% 62%,50% 100%,38% 62%,0 50%,38% 38%)`;
            fxLayer.appendChild(s);
            fx._sp.push({ s, a, d: 22 + 6 * Math.sin(i * 3.3), k: 0.8 + 0.3 * Math.cos(i * 5.1) });
          }
        }
        const u = (t - t0) / 0.6;
        for (const p of fx._sp) {
          const v = clamp(u * p.k);
          const r = p.d * easeOut(v);
          p.s.style.opacity = (v > 0 && v < 1 ? Math.sin(Math.PI * v) : 0).toFixed(3);
          p.s.style.transform = `translate(${(Math.cos(p.a * DEG) * r).toFixed(1)}px,${(Math.sin(p.a * DEG) * r).toFixed(1)}px) rotate(${(v * 90).toFixed(0)}deg) scale(${(0.4 + 0.8 * Math.sin(Math.PI * v)).toFixed(2)})`;
        }
      },
      confetti(t, t0) {
        if (!fx._cf) {
          fx._cf = [];
          const colors = ['#ffd84a', '#ff6b8a', '#6ee7ff', '#8cff7a', '#c79bff', '#ffffff'];
          for (let i = 0; i < 9; i++) {
            const s = document.createElement('div');
            s.style.cssText = `position:absolute;left:50%;top:42%;width:4px;height:6px;margin:-3px -2px;border-radius:1px;opacity:0;background:${colors[i % colors.length]}`;
            fxLayer.appendChild(s);
            fx._cf.push({ s, vx: (i - 4) * 26 + 10 * Math.sin(i * 2.7), vy: -150 - 40 * Math.cos(i * 1.9), spin: (i % 2 ? 1 : -1) * (400 + 90 * i) });
          }
        }
        const u = t - t0;
        for (const p of fx._cf) {
          if (u <= 0) continue;
          const x = p.vx * u;
          const y = p.vy * u + 0.5 * 520 * u * u;
          p.s.style.opacity = clamp(1.4 - u * 1.6).toFixed(3);
          p.s.style.transform = `translate(${x.toFixed(1)}px,${y.toFixed(1)}px) rotate(${(p.spin * u).toFixed(0)}deg)`;
        }
      },
      dots(t, t0) {
        // The bubble's own dots (refs.dots, cut out of it) bounce in turn — typing — until 1.05 s.
        (refs.dots || []).forEach((d, i) => {
          const u = t - t0 - i * 0.12;
          const on = u > 0 && t < 1.05;
          const b = on ? -1.4 * Math.max(0, Math.sin(2 * Math.PI * 2.2 * u)) : 0;
          d.setAttribute('transform', `translate(0 ${b.toFixed(2)})`);
        });
      },
      rays(t, t0) {
        if (!fx._rays) {
          fx._rays = [];
          for (let i = 0; i < 5; i++) {
            const a = -90 + (i - 2) * 38;
            const l = document.createElementNS(SVGNS, 'line');
            l.setAttribute('x1', 15 + Math.cos(a * DEG) * 10.5);
            l.setAttribute('y1', 11 + Math.sin(a * DEG) * 10.5);
            l.setAttribute('x2', 15 + Math.cos(a * DEG) * 13.5);
            l.setAttribute('y2', 11 + Math.sin(a * DEG) * 13.5);
            l.setAttribute('stroke', 'currentColor');
            l.setAttribute('stroke-width', '1.5');
            l.setAttribute('stroke-linecap', 'round');
            svg.appendChild(l);
            fx._rays.push(l);
          }
        }
        const u = clamp((t - t0) / 0.6);
        for (const l of fx._rays) l.setAttribute('opacity', (u > 0 && u < 1 ? Math.sin(Math.PI * u) : 0).toFixed(3));
      },
      stroke(t, t0) {
        if (!fx._stroke) {
          fx._stroke = document.createElementNS(SVGNS, 'path');
          fx._stroke.setAttribute('d', 'M4.5 26.2c3-1 6.5-1.2 9.8-.4');
          fx._stroke.setAttribute('fill', 'none');
          fx._stroke.setAttribute('stroke', 'currentColor');
          fx._stroke.setAttribute('stroke-width', '1.6');
          fx._stroke.setAttribute('stroke-linecap', 'round');
          fx._stroke.setAttribute('pathLength', '1');
          fx._stroke.setAttribute('stroke-dasharray', '1');
          svg.appendChild(fx._stroke);
        }
        const draw = clamp((t - t0) / 0.25);
        const fade = clamp((t - 0.75) / 0.25);
        fx._stroke.setAttribute('stroke-dashoffset', (1 - ease(draw)).toFixed(3));
        fx._stroke.setAttribute('opacity', draw <= 0.001 ? '0' : (1 - fade).toFixed(3));
      },
      paper(open) {
        if (!paper) return;
        paper.setAttribute('y', (14 - 6.5 * open).toFixed(2));
        paper.setAttribute('opacity', (0.92 * clamp(open * 3)).toFixed(3));
      },
      flash(t, t0) {
        if (!fx._flash) {
          fx._flash = document.createElementNS(SVGNS, 'circle');
          fx._flash.setAttribute('cx', '15'); fx._flash.setAttribute('cy', '15.3'); fx._flash.setAttribute('r', '6');
          fx._flash.setAttribute('fill', 'currentColor');
          svg.appendChild(fx._flash);
        }
        const u = clamp((t - t0) / 0.35);
        fx._flash.setAttribute('opacity', (u > 0 && u < 1 ? (1 - u) * 0.9 : 0).toFixed(3));
        fx._flash.setAttribute('r', (4 + 4 * easeOut(u)).toFixed(2));
      },
      hue(t, d) {
        const u = clamp(t / d);
        svg.style.filter = u > 0 && u < 1 ? `hue-rotate(${(360 * ease(u)).toFixed(0)}deg) saturate(1.4)` : '';
      },
      spin3d(t, t0, d) {
        const u = clamp((t - t0) / d);
        const a = 360 * (u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2);
        (rig.element ? row.glyph : svg).style.transform = u > 0 && u < 1 ? `perspective(60px) rotateY(${a.toFixed(1)}deg)` : '';
      },
      globe(u) {
        const g = refs.globe;
        if (!g) return;
        const G = CUTS.globe;
        // From the meridian at rest round to it again; the second one, a quarter turn behind, fades
        // in and out so neither end jumps (the prototype's 8.6 globe, scaled to Telegram's meridian).
        const th = Math.acos(3.9 / 8.6) + u * 2 * Math.PI;
        const rx = [u >= 1 ? 3.9 : 8.6 * Math.abs(Math.cos(th)), 8.6 * Math.abs(Math.sin(th))];
        g.meridians.forEach((e, i) => {
          const w = Math.max(0.01, rx[i] * G.meridianScale);
          e.setAttribute('d', meridian(w, G.meridianHeight));
          e.setAttribute('data-rx', w);
        });
        g.meridians[1].setAttribute('opacity', (clamp(u / 0.12) * clamp((1 - u) / 0.12)).toFixed(3));
        // Telegram's banded globe cross-fades into the turning one, and back before the end.
        const w = clamp(fx.t / G.fadeIn) * clamp((rig.duration - fx.t) / G.fadeOut);
        g.turning.setAttribute('opacity', w.toFixed(3));
        g.rest.setAttribute('opacity', (1 - w).toFixed(3));
      },
    };
    this.current = { row, rig, svg, P, fx, refs, fxLayer, sheen, t0: now, tile };
    this.update(now);
  }

  // The tap that opens the row's page: the tile gives under the finger (squash, spring back).
  press(row, now) {
    if (!row?.tile && !row?.glyph) return;
    this.pressed = { el: row.tile || row.glyph, t0: now };
  }

  update(now) {
    const pr = this.pressed;
    if (pr) {
      const t = now - pr.t0;
      const s = t < 0.07 ? 1 - 0.12 * easeOut(t / 0.07) : 0.88 + 0.12 * pop(t, 0.3, 0.07, 0.55);
      pr.el.style.transform = `scale(${s.toFixed(4)})`;
      if (t > 0.6) { pr.el.style.transform = ''; this.pressed = null; }
    }
    const c = this.current;
    if (!c) return !!this.pressed;
    const t = now - c.t0;
    // The tile: a spring pop and the sheen crossing it.
    if (c.tile) {
      const p = t < 0.09 ? 1 + 0.16 * easeOut(t / 0.09) : 1 + 0.16 * (1 - pop(t, 0.34, 0.09, 0.42));
      c.tile.style.transform = `scale(${p.toFixed(4)})`;
      if (c.sheen) {
        const u = clamp((t - 0.06) / 0.5);
        c.sheen.style.transform = `translateX(${(-100 + 200 * ease(u)).toFixed(1)}%)`;
      }
    }
    c.fx.t = t;
    c.rig.run(t, c.P, c.fx, c.refs);
    if (t >= c.rig.duration) {
      this.stop();
      return false;
    }
    return true;
  }

  stop() {
    const c = this.current;
    if (!c) return;
    this.current = null;
    c.svg.remove();
    c.fxLayer.remove();
    c.sheen?.remove();
    if (c.tile) c.tile.style.transform = '';
    c.row.glyph.style.visibility = '';
    if (c.rig.element) {
      c.row.glyph.style.transform = '';
      c.refs.inner?.removeAttribute('transform');
    }
  }
}
