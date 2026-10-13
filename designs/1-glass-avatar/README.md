# 1 · Glass Avatar

**Touch your profile photo and it becomes a thin sheet of glass under your finger.** It tilts any way you
move, turns over past edge-on, spins when flicked, and is a flat photo again a moment after you let go.
Choose a **glass colour** and its light runs across the whole profile — and from then on, turning the
photo throws that light across your name, in the direction it turns.

- Video: `renders/designs/1-glass.mp4` · Try it: <https://t.me/Tgdesignbot?start=glass> (Settings tab)
- Full behaviour spec: [concept.md](concept.md)

## Today in Telegram
A drag on the profile photo does nothing: the header gives touches on the avatar to the avatar
(`PeerInfoHeaderNode.hitTest`) and the avatar only has a tap (expand).

## The design
| Moment | What happens |
|---|---|
| Touch | The photo lifts (×1.03, TouchEffect's lift spring) and turns to glass: a 5 pt lens band folds the photo's edge, a 1 pt light edge, a faint sheen. Soft haptic. |
| Drag | Yaw follows the finger 1:1 (1 pt = 1°, PremiumCoinComponent), vertical travel tilts it (rubber band 60°, 0.4): any direction; the studio light glides over the glass. |
| Let go before edge-on | Home in 0.34 s (ζ 0.82): flat, pixel for pixel, 0.2–0.45 s after release. |
| Past edge-on | It completes the turn to its back (the same photo by default — or a back photo, design 2). A detent haptic as each side passes edge-on. |
| Flick | Momentum projection (0.995) picks the side; a hard flick spins it several times and lands. |
| **Change Glass Color** (new row) | Eight glass beads (Clear, Gold, Rose, Violet, Blue, Aqua, Green, Ember). The photo lifts into glass, the colour flows in, and a ring of its light leaves the photo and runs across the screen: the cover pattern glints, the glass buttons catch it, a soft glow stays around the photo. |
| **Turning with a colour** | A band of the colour sweeps across the name and the subtitle in the direction the photo turns (left→right turning right, back turning left; once per quarter turn) with a soft glow; the Edit/QR glass buttons get a sheen and a lit rim; a spin washes the name in the colour. Clear glass keeps the header plain. |

Scrolling, pull-to-expand and the tap behave as today (Telegram's own header formulas,
`research/telegram-ios/header-scroll.md`); the glass works only with the header at rest.

## Code
- **Web prototype**: physics `prototype/src/coin/coin-physics.js`, ray-traced glass `coin-shader.js` +
  `coin-renderer.js`, the colour's light `src/ui/light.js`, the turn light `src/ui/turn-light.js`, the colour sheet
  `src/ui/glass-sheets.js`, input `src/ui/input.js`, header scrolling `src/ui/profile-scroll.js`.
- **Native (Telegram-iOS)**: module `ios/GlassCoinAvatar/` (Swift + Metal on MetalEngine: physics, glass layer and
  shader, light wave, turn light, gesture, faces) and `ios/patches/0001-glass-avatar.patch` (module + PeerInfoScreen
  hooks + the "Change Glass Color" row). Details and verification: `ios/README.md`.

## Submission text
> **Glass Avatar — your photo turns to glass**
> Today a drag on a profile photo does nothing. Here it turns the photo into a thin sheet of glass: it lifts
> under your finger, tilts any way you move, turns over past edge-on and spins when flicked, and is a flat
> photo again 0.2–0.45 s after you let go. Pick a glass colour (new row, eight colours): its light runs across
> the whole profile, and turning the photo then sweeps that light across your name in the direction it turns.
> Built on Telegram's own constants (PremiumCoinComponent gesture, TouchEffect lift, LiquidGlass shadows,
> HapticFeedback detents, the header's scroll formulas). Code: a drop-in Swift + Metal module and a
> PeerInfoScreen patch, plus a web prototype running the same model. Try it: t.me/Tgdesignbot?start=glass
