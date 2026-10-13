# GlassCoinAvatar — Telegram-iOS module

Two designs on the own profile (Settings tab), shipped as one module and two patches that apply in order:

- **Glass Avatar** — the avatar turns into a thin sheet of glass under the finger and turns over to its back: the same
  photo by default (one picture, both sides). "Change Glass Color" tints the glass and sends a ring of that colour's light
  from the avatar across the screen (the glass button rims catch it, a soft glow of the colour stays around the
  avatar), and while the photo turns, the glass throws its colour across the header: a band of light sweeps over the
  name and the line under it in the direction it turns, a spin washes the name in the colour, the glass buttons get a
  sheen and a rim light, an aura grows around the photo. Clear glass throws nothing.
- **Back Photo** — "Add Back Photo" (then "Change Back Photo") puts a picture on the back of the photo, picked and
  cropped with the avatar's own media picker and editor; the photo turns over by itself to show it. Removing it makes the
  back the photo itself again.

The web prototype (`prototype/`) is the reference; every file below names the prototype file it mirrors.

```sh
cd Telegram-iOS                                   # at f1dd7a2 (master, 2026-10-07)
git apply /path/to/tgdesign/ios/patches/0001-glass-avatar.patch
git apply /path/to/tgdesign/ios/patches/0002-back-photo.patch     # optional; needs 0001
```

`ios/GlassCoinAvatar` is the single source of truth for the module (`submodules/TelegramUI/Components/PeerInfo/
GlassCoinAvatar`); patch 0001 carries it verbatim, CI checks that it does.

## Module

| File | Role |
|---|---|
| `Sources/GlassCoinPhysics.swift` | Interaction model (`coin/coin-physics.js`): press lift (flat, no tilt), drag (1 pt = 1°, rubber-banded pitch), release decision (90° / 200 pt/s, projection 0.995, toss > 600 pt/s), spring landing that starts dissolving the glass over the last ~11°, detent ticks, `onFaceChange` (every half turn), `pulse(at:hold:)` (a lift into glass without turning), `turnBy(_:at:)` (turns over by itself: flip spring, 1.3× the response for more than one face, lands like a release), `back` = `.photo(0)` / `.emblem` / `.backPhoto`. Pure Swift; CI replays the web's golden trajectories through it. |
| `Sources/GlassCoinLayer.swift` | `SimpleLayer` + `MetalEngineSubject` with one `MetalEngineSubjectLayer` (dedicated surface, bgra8, premultiplied). `GlassCoinLook` = `CoinLook` (h 3.4, w 7.5, liftZ 22, eye 520 for the 100 pt avatar); `makeUniforms` mirrors `CoinRenderer.render()` uniform for uniform (`glass = max(active, restGlass · tint)`, w = max(h, rimWidth · glass), centred shadow, tint/flash glow, early-out bounds). Glass colour: `glassColor` (rgb), `glassTint` (0…1), `flash`. The 224-byte uniform layout is tabulated in `GlassCoin.metal`. |
| `Metal/GlassCoin.metal` | `coin/coin-shader.js`, function by function: a two-sided photo card in a sheet of glass of the same radius whose rounded edge band lies inside the photo's circle (elliptical quarter-round, conservative scaled SDF), a soft studio (key soft box, a strip on each side, top bar: 3.8 / 3.4 / 2.0), sheen (0.15), glass tint denser toward the edge, matte haze (0.09) and a faint darker line where the lens band begins, edge line (power 2.3, 0.85 + 0.55 crescent + `edgeBoost`), refraction of the cover with dispersion, one centred soft shadow, tight glow, motion blur. Every `pow` base is ≥ 0 (fast math). Shipped in `GlassCoinAvatarMetalSourcesBundle` (BUILD mirrors LiquidGlassShapes). |
| `Sources/GlassCoinAvatarNode.swift` | Host node (`app.js`, `coin-controller.js`): gesture, `SharedDisplayLinkDriver` (`.max`), `HapticFeedback` (`.soft` on press, `tap()` per detent, `.rigid` on catch, `.medium` on landing, `.light` on a colour change), faces (the photo on both sides until a back photo is set), `setBackPhoto(_:animated:)` (app.js `chooseBack`, 0.75 s after the pick: with the front in view the back changes at once, out of sight, and it turns over to show it (`turnBy(1)`; none: a 0.18 s lift); with the back in view it turns two faces (none: one) and the back changes as the front passes — nothing pops), `setGlassColor(_:animated:)` (lift 0.18 s, colour/tint cross-fade 0.22 s ease-in-out, flash 0.55 s), `lightUpdated` (pose and colour every frame, for the lights), `landed`, VoiceOver "Turn Over", Reduce Motion. |
| `Sources/GlassLightWaveNode.swift` | `ui/light.js`: the ring (1.1 s; travel 0.62u + 0.38u², width 30 + 100u, intensity min(1, u/0.06)·(1−u)^1.5, core = colour lightened 0.5; only the annulus it covers is drawn), the flash where it starts, the glow (two 180 pt radial layers: the colour and the one it replaces; (dark 0.2 / light 0.1) × 1.8 at full lift, opacity = amount × visibility × (1 + 0.8 · lift) / 1.8 — `setLift` while the photo is held), an optional pattern glint (`setPatternMask`) and the rim spill (`spillTargets` → `spillUpdated` → `GlassLightSpillLayer`: rest light tint · (0.55 + 0.35 · lift), shadow rebuilt only when its colour or direction changes, otherwise opacity only). Dark: `screenBlendMode`; light theme: normal blending, the ring at 0.42. A display link only while the ring runs. |
| `Sources/GlassTurnLightNode.swift` | `ui/turn-light.js`, function for function: from the glass state each frame (face tilt ψ, direction, spin = smoothstep(7, 20, ω)) the band over the name and the subtitle (sawtooth along the face direction: it crosses the letters once per quarter turn, in the turn direction; a gradient clipped to the glyphs, plus the wash of a spin), their glow (the glyphs' text-shadow 4 / 11 / 24 / 42 pt, blurred once per text off the main thread, masked to the band), the sheen stripe and the rim light of the glass buttons, the aura (44–230 pt, screen-blended; 2.6× in the emoji pattern once it has the mask). Only at rest, only with a colour, never with Reduce Motion; no display link of its own — per frame only opacities and transforms. |
| `Sources/GlassCoinGestureRecognizer.swift` | Press feedback on touch down without claiming the touch; begins on movement past 6 pt in any direction (the header gives touches on the avatar to the avatar, so a drag there never scrolled or pulled anyway — `ui/input.js`); a tap still fails, so the existing tap recognizer expands the avatar. |
| `Sources/GlassCoinFaces.swift` | Square photo faces (`glassCoinSquareImage`, 640 px). |

### Lifecycle

- **active** — a touch, a pulse, a colour change or a turn: the display link runs, the real avatar is hidden once the
  face in front is loaded, and `lightUpdated` drives the glow (`setLift`) and the turn light every frame.
- **resting** — when the avatar at rest is not the plain photo (a back photo is in front, or the glass is tinted, which
  keeps `restGlass · tint` of glass at rest like the web), the last frame stays over the real avatar: no display link,
  one surface (≈ 1.7 MB at 3x). It is released when the node leaves the window or is disabled, and drawn again when it
  comes back. The lights rest.
- **inactive** — the default (clear glass, or the photo on both sides): nothing is drawn, the surface is released, the
  real `AvatarNode` shows as before.

## Patches (against Telegram-iOS `f1dd7a2`)

Generated from pristine copies of the touched files at `f1dd7a2` (not from a working checkout): `0001` is the diff from
pristine to the Glass Avatar tree, `0002` the diff from there to the Back Photo tree.

### `0001-glass-avatar.patch` — Glass Avatar

- The module, and `//submodules/TelegramUI/Components/PeerInfo/GlassCoinAvatar` in `PeerInfoScreen/BUILD`.
- `PeerInfoAvatarTransformContainerNode` — owns `coinNode` (2.2× the avatar, centred, the photo's radius inside a story
  ring, laid out after the ring in `updateStoryView`), attaches the recognizer to `avatarNode.view` next to the tap,
  hides `containerNode` while the glass moves, cancels it when the context menu fires, enables it only when collapsed
  and not a forum/topic, deleted or photo-less peer, and passes the cover's colours (`effectiveProfileColor`) as the
  glass environment.
- `PeerInfoAvatarListNode` — the face: photo 0 (`avatarNode.unroundedImage`, else `chatAvatarGalleryPhoto`) on both
  sides; a new profile photo resets the glass to its front. No gallery flipping.
- `PeerInfoHeaderNode` — `glassLightNode` right above the cover (under the avatar, title and buttons; it follows the
  avatar and fades as the header collapses or the photo expands), `glassTurnLightNode` above the title and subtitle
  (`lines`: the regular-state text layers of `titleNode` and `subtitleNode`, strength 1 / 0.85, glow 1 / 0.7), its
  `auraLayer` right above the light node, the rim spill and the turn light's sheen and rim in the two navigation
  capsules (`leftButtonsBackground` / `rightButtonsBackground`), `coinNode.lightUpdated` → `setLift` + turn light, the
  turn light at rest only (content offset 0, not expanded, editing, searching or in a transition), the cover snapshot
  the glass refracts, the pattern bounce on landing, `setGlassColor(_:animated:)`, and restoring the stored colour for
  the own profile.
- `PeerInfoSettingsItems` / `PeerInfoScreenSettingsActions` / `PeerInfoScreen` — "Change Glass Color" under "Change
  Profile Photo" (`PeerInfoSettingsSection.glassColor`).
- `PeerInfoScreenGlassAvatar.swift` (new) — `PeerInfoGlassAvatarStore` (the prototype's eight colours, a
  `UserDefaults` key per account) and `openGlassColorSetup()` (an action sheet; the glass takes the colour as the sheet
  leaves).

### `0002-back-photo.patch` — Back Photo (applies on top of 0001)

- `PeerInfoSettingsItems` / `PeerInfoScreenSettingsActions` / `PeerInfoScreen` — "Add Back Photo" ("Change Back Photo"
  once one is set) between "Change Profile Photo" and "Change Glass Color" (`PeerInfoSettingsSection.glassBackPhoto`).
- `PeerInfoScreenGlassBackPhoto.swift` (new) — the picker action through the avatar's own media picker and editor
  (round crop; a camera or library video gives its cover, the emoji avatar maker its picture). The prototype's "None"
  tile is the picker's remove action, offered while a back photo is set: the back is the photo itself again. The store
  extends `PeerInfoGlassAvatarStore`: a JPEG in the account folder, read and written on a serial queue.
- `PeerInfoHeaderNode` — `setGlassBackPhoto(_:animated:)` (→ `GlassCoinAvatarNode.setBackPhoto`) and restoring the
  stored back photo.

## Verification

`.github/workflows/ios-verify.yml` (macOS runner) — **what CI compiles and checks**:
1. `Standalone/Core` — `swift test`: `GlassCoinPhysics.swift` replays `golden.json` within 1e-6, with the same haptic
   ticks, faces passing and landings. `tools/golden.mjs` records it by running `coin-physics.js` directly in node:
   gestures, flicks and spins, and `turnBy` / `pulse` / `jumpToFace` / back changes (a new back photo with the front in
   view, a change and "None" with the back in view swapped as the front passes).
2. `xcrun -sdk iphoneos metal` + `metallib` on `GlassCoin.metal`.
3. `Standalone/TypeCheck` — builds every file of the module for the iOS Simulator with `-warnings-as-errors`, against
   signature stubs copied from Telegram's Display (incl. `HapticFeedback`, `SimpleLayer`/`SimpleShapeLayer`/
   `SimpleGradientLayer`, `SharedDisplayLinkDriver`), MetalEngine, SwiftSignalKit, AsyncDisplayKit (incl.
   `didEnterHierarchy`/`didExitHierarchy`/`isInHierarchy`) and UIKitRuntimeUtils.
4. The patches — a sparse checkout of Telegram-iOS at `f1dd7a2`: `0001` applies, then `0002`, and the module the patch
   carries is `ios/GlassCoinAvatar` byte for byte.

**What CI does not compile**: the `PeerInfoScreen` hooks (they need the whole Telegram-iOS Bazel build). They are kept
small, follow the surrounding code and its signatures exactly (the back photo picker is `openAvatarForEditing`'s flow),
and were checked against the sources at `f1dd7a2`; the real proof is building the patched app. The module's BUILD keeps
Telegram's `-warnings-as-errors`.

## Notes

- Live refraction alternative: on iOS 26 the cover could be refracted live through `LiquidGlassBackdropLayers`
  (backdrop + `displacementMap`), with this shader writing the offset map. The snapshot is used instead because the
  cover is static while the glass is held, it works on every iOS version, and it keeps the chromatic dispersion.
- Server fields: the back photo and the glass colour are stored on the device only. `TODO(server)`: `back_photo` and
  `glass_color` profile fields, so others see them (the faces callback already asks for `.backPhoto` when the node has
  no image of its own).
- Localization: the settings rows, the colour sheet, the colour names and the VoiceOver action ("Turn Over") are plain
  English, marked `TODO(localization)`; the row icons reuse "Settings/SetAvatar" and the cover-colour perk icon
  (`TODO(design)`: `set-backphoto` / `set-glass` from the prototype, and the NEW badge).
- The pattern glint of the wave and the aura in the emoji pattern need the cover's pattern as a mask
  (`GlassLightWaveNode.setPatternMask`, `GlassTurnLightNode.setPatternMask`); `PeerInfoCoverComponent` keeps it in
  private layers, so it is not wired yet (`TODO(design)` in the header hook).
- The colour picker is an action sheet (it closes on a pick); the prototype's sheet stays open without dimming so the
  light can be seen while trying colours — a custom sheet is the follow-up.
- A video avatar at rest under a tinted glass shows the glass's still frame (the glass samples the photo, not the
  video).
- `GlassCoinFaceContent.emblem` (the profile colour and emoji) stays in the physics twin because `coin-physics.js` keeps
  it; the design no longer uses it, so the module draws no emblem.
