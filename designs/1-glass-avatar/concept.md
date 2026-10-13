# Glass Avatar — behaviour spec

**One line:** touch your profile photo and it becomes a thin sheet of glass under your finger — it
tilts any way you move, turns over to its back (the same photo, or a **back photo** you add — design 2), and
is a flat photo again a moment after you let go. Pick a **glass colour** and its light runs across the
whole profile.

(Code names: `GlassCoin…` — the interaction started from Telegram's draggable coin. The look is now an
avatar, not a coin: no rim, no thickness at rest, nothing framing the photo.)

## Why

- The avatar is the largest, most personal element of the profile header and the first thing people
  touch. Today a drag on it does **nothing**: the header gives touches on the avatar to the avatar
  (`PeerInfoHeaderNode.hitTest`), and the avatar only has a tap.
- iOS 26 turns controls into Liquid Glass *while you touch them* (slider and toggle thumbs, the tab-bar
  pill). This applies the same idea to content: a flat photo at rest, glass only while it is touched,
  then exactly the same pixels again.
- One photo, two sides: the back is a small, personal surprise for whoever turns your photo over — the
  same photo by default, or a second photo you choose for it (design 2, Back Photo).

## Behaviour

| Moment | What happens | Numbers (and where they come from) |
|---|---|---|
| Touch down | The photo lifts straight up (≈ ×1.03) and turns to glass: a 5 pt lens band folds the photo's edge, a 1 pt light edge, a faint sheen; no tilt toward the finger, so every edge reads the same. A soft haptic. | lift-on spring m 1.36 / k 568 / c 39.7 (`TouchEffect.swift`) |
| Drag | Yaw follows the finger 1:1 (1 pt = 1°); vertical travel tilts it (rubber band, range 60°, coefficient 0.4): it moves in **any direction**, the studio light glides over the glass. | `PremiumCoinComponent.handlePan` |
| Release before edge-on | Back home: response 0.34 s, ζ 0.82. | thresholds 90° / 200 pt/s from `PremiumCoinComponent` |
| Release past edge-on | It completes the turn: the **back** lands (the same photo, or the back photo); turn again for the front. | flip spring 0.40 s, ζ 0.80 (~1.5 % overshoot) |
| Flick | Momentum projection (rate 0.995) picks the landing side; a hard flick spins it several times with constant friction and lands on the chosen side. | WWDC18 *Designing Fluid Interfaces* |
| Landing | The glass starts dissolving during the last ~11° of the motion, so the photo is flat again **0.2–0.45 s after you let go** (it was ~1 s). `impact(.medium)` when it shows the other side; the cover pattern bounces like a colour change. | glass-out 0.22 s ζ 1; settle 0.28 s ζ 0.9; `PeerInfoCoverComponent.animateTransition` [1, 1.14, 1] |
| Each side passing edge-on | A detent haptic, at most one per 45 ms; catching a spinning photo: `impact(.rigid)`. | `HapticFeedback.swift` |
| Tap | Expands the photo as today (0.35 s curve). | `PeerInfoScreen` |

### Back photo
A separate design: [../2-back-photo](../2-back-photo/). Without it the back is the same photo.

### Glass colour (new settings row: *Change Glass Color*)
- A compact sheet with eight glass beads: Clear, Gold, Rose, Violet, Blue, Aqua, Green, Ember. The
  screen stays undimmed so you see the result live.
- Picking a colour: the avatar lifts into glass for a moment (0.3 s), the colour flows into it
  (0.38 s), and a **ring of its light** leaves the avatar and runs across the whole screen in 1.5 s —
  about 0.5 s across the header, then over the list. The emoji pattern glints as it passes, the glass
  buttons' rims catch the light on the side facing the avatar, and a soft glow of the colour stays
  around the photo (light spill, as in the designer video's colour changes).
- The tint itself is light: a 10–30 % wash denser toward the edge, a coloured edge line and sheen.
  It shows while the photo is glass and as a faint hint at rest; Clear keeps the exact photo.

### Turn light (with a glass colour)
- While the glass turns, its colour lights the header from the photo: a band of the colour sweeps across the
  **name and the subtitle** in the direction the photo turns — left to right turning right, back again
  turning left — crossing the letters once per quarter turn (band position = sawtooth of the tilt along the
  face's direction, 1.2 rad per sweep), with a masked glow around the letters (4/11/24/42 pt shadows).
- A fast spin washes the whole name in the colour; the Edit and QR glass buttons get a moving sheen and a lit
  rim on the side facing the photo; an aura of the colour breathes around the photo.
- Strength follows the tilt (nothing below ~1.5°, full by ~7°) and fades as the glass lands. Clear glass: no
  light at all. (`prototype/src/ui/turn-light.js`, native `GlassTurnLightNode.swift`.)

### Scrolling (Telegram's own header, rebuilt in the prototype)
Scrolling up collapses the header (avatar to 0.55, title to 0.6 locked in the navigation bar at S + 31,
pattern sliding into the avatar, banner fading out past S + 70); pulling down past 32 pt expands the
photo to the full width; releases between 0 and 140 snap. Exact formulas with source lines:
`research/telegram-ios/header-scroll.md`. The glass avatar is only active at rest (not collapsed or
expanded).

## The glass

A two-sided photo card inside a thin sheet of glass of the **same radius** — ray traced per pixel
(WebGL2 in the prototype, Metal in the app, same functions):

- **Geometry:** flat faces over the photo; the edge is an elliptical quarter-round 5 pt wide and 2.6 pt
  deep that lies *inside* the photo's circle. The silhouette is exactly the avatar's; edge-on it is a
  5 pt sheet.
- **Refraction:** the photo folds into the lens band at the edge (iOS 26 liquid-glass edge);
  grazing rays that pass the photo show the cover behind, with light dispersion.
- **Reflection:** Fresnel (Schlick) against a soft studio in the profile colours — a key light up-left,
  a strip right, a top bar — plus a faint overhead sheen; the lights glide across as it tilts.
- **Edge:** a thin light line, the same all around with a faint crescent up-left (designer video:
  1–2 pt edge, denser band, crescent, minimal shadow).
- **Shadow:** one soft ellipse centred under the photo, only while lifted (Telegram's `liquidGlassErf`
  coverage).
- At rest (glass = 0) the shader returns the flat avatar pixel for pixel.

## Accessibility & performance
- **Reduce Motion:** disabled; the avatar behaves as today. **VoiceOver:** an action turns it over.
- **Cost:** nothing renders at rest. While touched one MetalEngine layer (2.2× the avatar) draws at the
  display rate; empty pixels exit early. On the web a frame-time governor lowers the resolution if a
  phone can't keep ~40 fps.

## Files
- Web prototype: `prototype/` — physics `src/coin/coin-physics.js`, shader `src/coin/coin-shader.js`,
  light `src/ui/light.js`, turn light `src/ui/turn-light.js`, sheets `src/ui/glass-sheets.js`, scrolling
  `src/ui/profile-scroll.js`, input `src/ui/input.js`.
- Native: `ios/GlassCoinAvatar/` (Swift + Metal module, incl. `GlassTurnLightNode.swift`) and
  `ios/patches/0001-glass-avatar.patch`; the back photo UI is `ios/patches/0002-back-photo.patch` (design 2, on top of 0001).
- Constants traced in `research/telegram-ios/README.md` and `research/telegram-ios/header-scroll.md`.
