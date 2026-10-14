# DepthSwipe — Telegram-iOS module

Swiping a chat in the chat list (the iOS 26 swipe actions) lifts its row into 3D while it moves:

- the name becomes extruded 3D type. Its letters roll back on their own axis in a wave that starts on the side the
  row moves toward;
- each line of the message leans as a rigid plate, its leading end lifting a beat later;
- the photo becomes a thick disc that tilts with the pull. The picture sits deeper than the rim, and a glint crosses
  it. A story ring is printed on the disc's face;
- on left swipes the screen's left edge acts as the rounded rim of the surface. The disc rolls over it into the
  depth, and every letter of the name flips over once as it rolls over (a full turn about its own axis, done by
  `flipBy` = 0.68 of the way round, before it fades); all of it comes back out the same way when the row closes. The message fades into the rim. The badges
  roll over it as flat pieces: the name's icons (verified, emoji status, muted, lock) and whatever sits on the photo's
  edge (online, timer, live);
- the full-swipe moment (the haptic) spins the letters once, reel by reel, and flips the disc like a coin.

The rig runs whenever the row moves: under the finger, on the release spring, when a tap closes the row, and when an
action closes or fills it. When the row settles, everything rolls back flat and the flat text, photo and badges take
over again. The web prototype (`prototype/`) is the reference, and every Swift file below names the prototype file it
mirrors.

Drop-in module for `submodules/TelegramUI/Components/ChatList/DepthSwipe`, next to the other chat list components.
Everything is in `ios/patches/0004-depth-swipe.patch`, made against Telegram-iOS `f1dd7a2`:

```sh
git apply /path/to/tgdesign/ios/patches/0004-depth-swipe.patch
```

`ios/DepthSwipe` is the single source of truth for the module. `tools/depth-swipe-patch.sh` regenerates the patch
from it: the module part comes from `ios/DepthSwipe`, the hooks part from the current patch. The script then checks
the patch against pristine files fetched at `f1dd7a2`. No Telegram-iOS checkout is touched.

## Module

| File | Mirrors | Role |
|---|---|---|
| `Sources/DepthSwipeRig.swift` | `prototype/src/chats/depth.js` (`DepthLook`, `DepthRig.update`) | The maths, pure Swift. `DepthSwipeLook` holds every constant. `DepthSwipeRig` has `begin` / `end` / `spin` / `update(at:offset:velocity:pull:)`. Its parts: the motion lean `tanh(\|v\| / 620)` read back through the velocity history (staggers), the tension `tanh(pull / 60)`, the per-letter roll springs with the wave order, the rim mapping (hinge 36, radius 34, fade 62°–90°, each letter's flip over it) with the perspective compensation `tx = O + (cx + dx − O)·(P − dz)/P − cx`, the shade and fade values, the line leans, the disc lean / rim turn / flip, and the spin (0.56 s, 0.03 s per reel, the disc 3 reels early). It produces a plain `DepthSwipeFrame` per frame. |
| `Sources/DepthSwipeSpring.swift` | `prototype/src/core/spring.js` | Closed-form damped oscillator (`SpringParams.fromResponse`, `solveSpring`, `SpringValue` with velocity hand-off and the 0.02° rest). It does not depend on the frame rate. |
| `Sources/DepthSwipeTracker.swift` | `prototype/src/chats/chat-list.js` (`ChatRow.update` / `setOffset`) | How the row drives the rig: the velocity of the presented offset (`Δx / dt`, smoothed `vel·0.45 + v·0.55`), the start on a move of more than 0.5 pt, the pull, and the end condition (nothing moving, the row still, nothing round the rim). |
| `Sources/DepthSwipeContent.swift` | `depth.js` `units()` / `buildTitle` measuring, `chat-list.js` `meanColor` | Measures and draws the flat pieces once, when the rig starts. **The name** comes from the title TextNode's own rendered CTLines (`TextNodeLayout.enumerateRenderedLines`, truncation "…" included). These are split into grapheme clusters, or into words for scripts whose letters join, in visual order, so kerning and shaping are kept. Each letter is drawn with `CTRunDraw` into one atlas, on the flat name's pixel grid, in rows: the face, its copy in shadow, and 7 extrusion copies tinted with the day / night ramp. Colour emoji stay in colour in every row, as CSS `color` leaves them. **The message** is the TextNode drawn from its layout (`TextNode.draw`, the same drawing as the flat node) plus its inline emoji layers, cut into one band per rendered line. **The author line, the photo and the badges** are layer snapshots. The photo gives two pictures. Its picture node becomes the disc's face, with parallax. The rest of its drawing (a story ring), without the badges on its edge, is printed on the face. The disc takes the photo's own clip: round, or a forum's rounded square (`AvatarNode` sets `cornerRadius` 0.5 or 0.25 × height on its picture). The picture's mean colour tints the disc's rim. |
| `Sources/DepthSwipeLayers.swift` | `depth.js` `buildTitle` / `buildLines` / `buildAvatar` and the styles `update()` writes | The Core Animation renderer. One `SimpleTransformLayer` per letter holds its extrusion copies, its face and its shade, under a layer with `sublayerTransform.m34 = −1/330`. All of these are cells of the one atlas. The message lines are plates in a box with its own perspective: seen from the left end on a left swipe, `rotateY` about the far end, and a gradient mask fading into the rim. The disc is a transform layer holding the back (same picture, `isDoubleSided = false`), 6 rim slices, and the face with the picture (parallax), the printed ring, the rim's shadow, the glint and the dim. Badge copies sit on top of the row's content and roll over the rim. CSS transform lists map to `CATransform3DConcat` from the last function to the first. Only values that changed are written. |
| `Sources/DepthSwipeController.swift` | `chat-list.js` `depthStart` / frame loop, `reveal-options.js` haptic | The object a row owns. `updateRevealOffset(_:transition:isExtendedActionArmed:)` and `contentUpdated()` are the hooks. It builds and hides on start, runs a `SharedDisplayLinkDriver` link while anything moves, reads the offset as displayed, spins when the outer action arms, and goes back to flat at the end. |
| `BUILD` | — | `swift_library` "DepthSwipe" (`-warnings-as-errors`), deps `AsyncDisplayKit`, `Display`. |

## Hooks (`ios/patches/0004-depth-swipe.patch`)

- **`ChatListUI/BUILD`**: one dependency, `//submodules/TelegramUI/Components/ChatList/DepthSwipe`.
- **`ItemListRevealOptionsItemNode`** (`ItemListEditableItem.swift`) gets two read-only accessors for the private
  gesture state:
  - `revealGestureInitialOffset: CGFloat?`: `initialRevealOffset` while the reveal recognizer is `.began` or
    `.changed`, nil otherwise;
  - `isDisplayingExtendedRevealOption: Bool`: either reveal node `isDisplayingExtendedAction()`.
  The base class lays out the reveal nodes, which plays the haptic and updates `isExpanded`, before it calls the
  subclass's `updateRevealOffset`. So the row sees the armed state change in the same call as the haptic.
- **`ChatListItemNode`** (`ChatListItem.swift`, +41 lines):
  - `private var depthSwipe: DepthSwipeController?`, created on the first change of the reveal offset. Rows that are
    never swiped cost nothing.
  - `updateRevealOffset(offset:transition:)`. After moving `contextContainer` and the card, it calls
    `updateDepthSwipe`, which hands the controller the offset, the transition and whether the outer action is armed.
    The controller reads `revealGestureInitialOffset` every frame through a closure. A release at exactly 0 makes no
    offset update, so it must not be cached.
  - `depthSwipeParts()` passes `titleNode`, `textNode.textNode` and `authorNode`. For the photo it passes
    `avatarNode` (nil while the avatar is replaced by a media preview) and `avatarNode.contentNode`, its picture. It
    passes the badges as layers. These are the name's: secret lock, credibility, verified, emoji status, muted, title
    badge. And the photo's edge: `onlineNode`, the timer, live and count badges, the star, the community badge. It
    also passes the row's right inset and `theme.overallDarkAppearance`.
  - In `asyncLayout`'s apply, right after `updateLayout(size:leftInset:rightInset:)`, it calls
    `depthSwipe?.contentUpdated()`. While the rig runs, it rebuilds its pieces from the new content (a new message,
    the mute icon, a theme change) and the motion carries on.

## Lifecycle and performance

- **At rest the row is flat.** The rig adds layers only while the row moves. When it settles flat, they are removed
  and the flat nodes show again in the same transaction. A row resting open with pieces round the rim keeps its
  static layers but runs no display link. The next move, or the close, resumes it.
- **Start cost.** This is a one-off at the first move. It draws the letter atlas (about 1–2 MB at 3x for a typical
  name, a single texture for the whole name), one snapshot of the message, the photo and the badges, and creates
  about 10 layers per letter plus about 15 more. Everything is released when the rig ends, except the disc's two
  edge pictures, which the row keeps for its next swipe.
- **Per frame.** The display link runs at `.max` only while something moves, while the finger holds the row, or
  while the reveal spring runs. Each tick does a few dozen multiply-adds per letter and writes only the transforms and
  opacities that changed, with actions disabled. The only offscreen work is the disc's round clip, its fade on the
  rim, and the message mask while the text is at the rim.
- **Offset as displayed.** Core Animation runs the reveal spring in the render server. The controller reads
  `contextContainer`'s presentation bounds and steps one frame ahead, clamped toward the target, so the pieces held
  on the rim do not lag the row. Under the finger it uses the model offset, which is committed with the layers.
- **Hiding the flat nodes.** A finished, kept animation of `hidden` (key `DepthSwipe.flat`) hides them. It does
  not touch the `isHidden` and `alpha` values the row's layout sets, the row's own opacity animations do not override
  it, and removing it shows them in their current state.
  The badges are hidden the same way and rolled as copies placed on top of the row's content. Their own layers are
  never transformed, so the row's layout keeps setting their frames safely.

## Accessibility

- **Reduce Motion**: the rig does not start, and a running rig ends at the next frame. The row swipes flat, as
  before.
- VoiceOver: the flat nodes stay in place and keep their accessibility. The rig's layers are plain `CALayer`s and
  are not accessibility elements. The swipe actions' custom actions are unchanged.

## Verification

`.github/workflows/ios-depth-swipe.yml` runs on a macOS runner. **What CI checks:**

1. `ios/Standalone/DepthSwipeCore` runs `swift test`. `DepthSwipeRig`, `DepthSwipeSpring` and `DepthSwipeTracker`
   replay `golden-depth.json` frame by frame. `tools/golden-depth.mjs` records that file from
   `prototype/src/chats/depth.js`, driven like `chat-list.js` drives it. It covers a right swipe, a left swipe that
   rolls over the rim and back, a full swipe with the spin and the archive fill, a flick, and a swipe that reverses
   through zero. Every letter's roll, angle, lift, rim place, shade and fade must match within 1e-7, along with the
   badges, the text mask, the line leans, the disc, the smoothed velocity, the pull, and the frames where the rig
   starts, spins and ends.
2. `ios/Standalone/DepthSwipeTypeCheck` builds every module file for the iOS Simulator with `-warnings-as-errors`. It
   builds against signature stubs copied from Telegram's Display (`TextNode`, `TextNodeLayout`, `SimpleLayer` and
   friends, `SharedDisplayLinkDriver`, `ContainedViewLayoutTransition`, `UIScreenScale`) and AsyncDisplayKit
   (`ASDisplayNode`). `HookCheck` also compiles the patch's two `ChatListItemNode` hook functions, verbatim, against
   the module, on stand-ins for the row's members.
3. `tools/depth-swipe-patch.sh --check` confirms the patch applies to the pristine files at `f1dd7a2`, that the
   module it adds is exactly `ios/DepthSwipe`, and that its hook functions are the ones HookCheck compiled.

**What CI does not check:** the hooks inside the real `ChatListItemNode` and `ItemListRevealOptionsItemNode`. That
needs the full Telegram-iOS Bazel build. The hooks are small, follow the surrounding code, and were checked against
the sources at `f1dd7a2`: every member they touch exists with the type used, and the new names collide with nothing
in the repository. The real proof is building the patched app. CI also does not check the look on a device; the
renderer follows the prototype's CSS, with the differences listed under Notes.

Regenerating:

```sh
node tools/golden-depth.mjs > ios/Standalone/DepthSwipeCore/Tests/DepthSwipeCoreTests/Resources/golden-depth.json
tools/depth-swipe-patch.sh          # after changing ios/DepthSwipe
```

## Notes

- Differences from the prototype, all in drawing, none in the maths:
  - the photo's 1.14 zoom (room for the parallax) grows with the tilt, reaching 1.14 at a third of the way, instead
    of jumping on the first frame, so the flat photo hands over without a jump;
  - letters go in visual order rather than string order (the same for left-to-right names);
  - badges roll as copies on top of the row (the prototype rolls the name's icons themselves);
  - a story ring, which the prototype does not have, is printed on the disc's face.
- Spoiler dust (`InvisibleInkDustNode`), media thumbnails in the message and the date / unread badge stay flat and
  move with the row, as they do in the prototype.
- A video avatar shows its still picture on the disc. `render(in:)` cannot capture video layers.
- A name with a line break that TextNode truncates draws its "…" as an extra trailing line, which the rendered
  lines leave out. Such a name stays flat; the rest of the row still goes 3D.
