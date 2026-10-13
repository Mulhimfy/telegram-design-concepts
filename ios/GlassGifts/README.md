# GlassGifts — Telegram-iOS module

On a profile's **Gifts** tab every gift tile becomes a pane of glass with the gift floating inside it. It behaves like
hover, because a tap keeps doing what it does today (opening the gift's info sheet):

- **touch** a tile and it leans toward the finger and lifts a hair (×1.01) while a burst of light fragments runs across
  the glass and sparkles catch at its corners;
- **press, hold** (0.12 s, Telegram's context-gesture threshold) **and slide**: every tile the finger crosses leans after
  it, with a selection tick per tile;
- **tilt the phone** and the light moves across all tiles — specular sheen, faint prismatic streak, lit edge — with only
  a hint of lean (≤ 2.5°);
- nothing turns far (≤ 9° yaw / 7° pitch) and it eases home on release.

The motion is Telegram's own TON wallet card (`WalletCardComponent`): angles follow their targets with 1 − e^(−8 dt),
the scale with 1 − e^(−12 dt), targets decay e^(−4 dt) after release, device motion moves the light rather than the
card, m34 = −1/650. The web prototype is the reference (`prototype/src/profile/glass-gifts.js`, `profile-page.js`,
`styles/telegram.css`); every file below names the prototype file it mirrors.

Drop-in module for `submodules/TelegramUI/Components/Gifts/GlassGifts` plus the hooks that wire it into the gifts grid.
Everything is in `ios/patches/0005-glass-gifts.patch` (against Telegram-iOS `f1dd7a2`, master 2026-10-07):

```sh
git apply /path/to/tgdesign/ios/patches/0005-glass-gifts.patch
```

`ios/GlassGifts` is the single source of truth for the module; the patch carries a copy of `BUILD` and `Sources/`. (Its
blank lines in the hooks keep Telegram's indentation, which `git apply` reports as whitespace; it applies cleanly.)

## Module

| File | Mirrors | Role |
|---|---|---|
| `Sources/GlassTileModel.swift` | `glass-gifts.js` — `GiftLook`, `GlassTile` | The tile model, pure Swift: `aim(u:v:)`, `release()`, `burst(at:)`, `update(now:dt:light:)` → `GlassTileState` with everything the prototype writes per frame: the transform (translate, scale, pitch, yaw, roll), sheen offset / opacity, holo position / opacity, rim angle, gift slide, shadow offset / scale / opacity, shard and sparkle progress, and whether it still moves. Also `GlassGiftTiming.easeOut` (the context gesture's ease back). |
| `Sources/GlassGiftMotionFilter.swift` | `glass-gifts.js` — `MotionSource` | The tilt filter, pure Swift: the first reading is the reference, 0.1 s smoothing, ~4 s re-centring, ±20° → full effect, scripted override. `GlassGiftRotationIntegrator` turns the gyroscope into its readings; `GlassGiftScreenRotation` keeps the light in screen axes (iPad, landscape). |
| `Sources/GlassGiftMotion.swift` | `glass-gifts.js` — `MotionSource.start/stop` | One shared `CMMotionManager` (60 Hz, like the wallet card's). Panes are **clients** (the sensor runs while one is on screen), tiles are **listeners** (they get each change > 0.01°). Stops on standby, app inactive, Reduce Motion. |
| `Sources/GlassGiftTileLayers.swift` | `telegram.css` — `.gift-shadow`, `.gift-body`, `.gift-holo`, `.gift-sheen`, `.gift-shard`, `.gift-rim`, `.gift-sparkle` | The glass's own layers, in the tile view next to its own: shadow (flat under the glass), glaze, prismatic streak (screen blend, multiply in the light theme, tiled like `background-repeat`), sheen, shards (screen blend), 1 pt rim (CSS gradient angle → start / end points, premultiplied colour ramp), corner sparkles. |
| `Sources/GlassGiftTile.swift` | `profile-page.js` — a tile's wiring | The glass on one `GiftItemComponent.View`: the tile's lean as its `sublayerTransform` (perspective, translate, scale, X / Y / Z rotation, then the context gesture's press shrink), the floating parts' depth as `zPosition` (gift 14, ribbon 18, badges 10 pt) and the gift's slide, the shadow kept flat by undoing the lean, the display link, the motion listener, Reduce Motion. |
| `Sources/GlassGiftGestureRecognizer.swift` | `profile-page.js` — `down` / `move` / `up` | The touch: aim and burst on touch down without claiming the touch, the hold, the slide across tiles, the release. |

## Hooks (`ios/patches/0005-glass-gifts.patch`)

- **`GiftItemComponent`** (`Gifts/GiftItemComponent`): a `glassEffect: Bool = false` parameter (stored, compared in
  `==`), a `glassTile: GlassGiftTile?` in the view, and one block at the end of `View.update`: with `glassEffect`, in
  `.profile` mode and not editing, the view creates its `GlassGiftTile` and passes it the size, corner, theme, whether the
  gift is a collectible, the backdrop layer (pattern view or background layer), the sticker layer and the views that
  float (hidden-gift badge and resale price on the sticker; ribbon outline, ribbon and its text; sender avatar, pinned
  and date-locked icons). Otherwise it removes it. BUILD: `+ //submodules/TelegramUI/Components/Gifts/GlassGifts`.
- **`GiftsListView`** (the profile grid, in `PeerInfoVisualMediaPaneNode`): `glassEffect: !self.canSelect &&
  !self.isReordering` — profile panes only (not the "add gifts" picker), and not while reordering.
- **`PeerInfoGiftsPaneNode`**: while in the window (`didEnterHierarchy` … `didExitHierarchy`) the pane holds a
  `GlassGiftMotion.Client` for its view: the phone's tilt is read only while a gifts pane is on screen. BUILD:
  `+ //submodules/TelegramUI/Components/Gifts/GlassGifts`.

Nothing else changes: the grid's metrics, the sticker, the ribbon and badges are Telegram's own, laid out by
`GiftItemComponent` as before. The glass never sets a frame: the lean goes through the tile view's `sublayerTransform`,
which the grid's `setFrame` doesn't see, and depth goes through `zPosition`. The sticker's slide over the glass moves
its position on top of where the tile view put it; every update of the tile view re-lays it, and the glass reads that
as the new base.

### Why a tap still opens the info sheet

The tile's tap is its `HighlightTrackingButton` (`.touchUpInside` → `GiftViewScreen`); its long press is the
`ContextGesture` of `ContextControllerSourceView`. The glass adds one more recognizer to the tile view:

| Touch | Glass | Telegram |
|---|---|---|
| down | aims the lean at the finger and bursts at once; stays `.possible` (`delaysTouchesBegan` / `delaysTouchesEnded` false) | the button gets the touch as before |
| moves > 8 pt before the hold | fails; the glass eases home | the pane scrolls / pages / swipes back as before (a pan that starts sooner fails the glass itself) |
| lifts (any time, without sliding) | fails; eases home | **tap → info sheet**, also for a slow tap of 0.12–0.32 s |
| still at 0.12 s (`beginDelay`), within 10 pt | arms: fails the `.possible` pans of the views above (as `cancelParentGestures` does when the menu opens), so a slide now belongs to the tiles | the context gesture starts its shrink; the glass composes it into the tile's transform (`customActivationProgress`, same `(w − 15)/w`, same 0.2 s ease-out back) |
| still at ≈ 0.32 s | is failed by `cancelParentGestures`; eases home | **context menu**, as before |
| armed, then slides 10 pt | begins: the button's touch is cancelled (no sheet), the context gesture is cancelled (no menu); every tile crossed leans after the finger, bursts and ticks (`HapticFeedback().tap()`, the selection tick) | — |
| lifts after sliding | ends; every tile eases home | — |

A touch that stops a scrolling grid only catches it (no lean, no burst), as in the prototype.

## Lifecycle and performance

- **At rest the tile keeps Telegram's geometry**: its transform is exactly identity and nothing floats (`zPosition` 0,
  no perspective), and no display link runs. The glass's own layers are its static look: shadow (`shadowPath`, no
  offscreen pass), glaze, streak, sheen, rim; the shards and sparkles are hidden. While resting, the blended streak and
  the masked rim are rasterized, so a still grid scrolls without their offscreen passes.
- **Awake** (a touch, a release easing home, a burst, the press shrink, the light above 0.05°): a
  `SharedDisplayLinkDriver` link (`.max`) per moving tile, stopped when it settles. The depth — the perspective's
  strength and the parts' `zPosition` — fades in with 1 − e^(−12 dt) when the glass wakes (the floating parts lift a
  little toward you) and out when it rests.
- **The phone's tilt** runs one `CMMotionManager` at 60 Hz, only while a gifts pane is on screen: a pane next to the
  selected tab is in the window but off screen, so the source goes on standby (sensor off, a look twice a second); with
  no pane in the window nothing runs. Tiles get only changes over 0.01° and draw them directly (no display link); a phone
  held still drifts back to neutral (the ~4 s re-centring), after which nothing more is published. The sensor also
  stops when the app resigns active and with Reduce Motion. The tilt is the gyroscope's rotation about the device's own
  x / y axes since the first reading (`CMDeviceMotion.rotationRate`, bias-corrected): the directions of the browser's
  beta / gamma, without their lock-up when the phone is held upright; the filter's re-centring absorbs integration
  drift.
- Tiles that leave the window (scrolled away: the grid drops them; covered by a pushed screen) stop and come back at
  rest.

## Accessibility

- **Reduce Motion**: no lean, lift, depth or sticker slide, and the phone's tilt is not read; the light still follows the
  finger (sheen, streak, rim, fragments, sparkles), and the context gesture's own shrink stays as in Telegram.
- **VoiceOver**: unchanged — the glass adds no accessibility elements; activating a tile is the button's action (no
  touch, no glass).
- **Haptics**: one selection tick when sliding starts and one per tile crossed (`HapticFeedback().tap()`); none for a tap.

## Verification

`.github/workflows/ios-glass-gifts.yml` (macOS runner) — **what CI compiles and runs**:
1. `Standalone/GlassGiftsCore` — `swift test`: `GlassTileModel.swift` and `GlassGiftMotionFilter.swift` (copied from
   here) replay `golden-gifts.json`, recorded from the unmodified web prototype by `tools/golden-gifts.mjs` (taps,
   corners, a held finger rocking, aims past the edges, a slide across three tiles with a gap, bursts on bursts, the
   phone's tilt alone and with a tap, uneven frame times; the motion filter's reference, re-centring, clamp, override and
   uneven frames). Every value of every 60 Hz frame within 1e-6, and the shards / sparkles exactly on the frames the
   prototype writes them. Plus the gyroscope integration, the screen rotation of the light and the ease-out curve.
2. `Standalone/GlassGiftsTypeCheck` — builds every file of the module for the iOS Simulator with `-warnings-as-errors`
   against signature stubs of Telegram's Display (`ContextControllerSourceView`, `ContextGesture`, `HapticFeedback`,
   `SharedDisplayLinkDriver`, `SimpleLayer` & co., `UIScreenScale`) and AsyncDisplayKit (`didEnterHierarchy` /
   `didExitHierarchy`), and the patch's two Swift hooks (`HookCheck/`) line for line against reduced shapes of
   `GiftItemComponent.View` and `PeerInfoGiftsPaneNode`.

**What CI does not compile**: the patched `GiftItemComponent`, `GiftsListView` and `PeerInfoGiftsPaneNode` themselves
(they need the whole Telegram-iOS Bazel build). The hooks are small, follow the surrounding code and its signatures
exactly, were checked against the sources at `f1dd7a2`, and the patch applies cleanly there (`git apply --check`); the
real proof is building the patched app. The module's BUILD keeps Telegram's `-warnings-as-errors`.

**What CI cannot show**: how it looks and feels on a device — the rendering (layers, blend modes, perspective) and the
gesture's interplay with the profile's own scroll and tab paging. Worth a look on device: the blur-backed badges (the
hidden-gift eye, the resale price) while a tile leans in 3D.

## Notes

- **Depth at rest.** In the prototype the perspective is always on, so the floating parts sit 1.6–2.8 % larger than the
  flat tile even at rest. Natively the depth fades in only while the glass is awake, so an untouched tile keeps
  Telegram's exact geometry under its glass (crisp ribbon text, the ribbon exactly in its corner).
- **Stacking.** The resale price stays above the sticker as in Telegram (it shares the sticker's depth instead of the
  badges' 10 pt, where the sticker would cover it).
- **Sheen.** One tile-sized radial gradient instead of the prototype's 170 % box: the box only trims a fringe under 1 %
  white at its top edge.
- **Not ported**: the prototype's mouse hover (no pointer on a phone).
