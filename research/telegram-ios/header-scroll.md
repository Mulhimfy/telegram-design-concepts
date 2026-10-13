# Own-profile header under scrolling (Settings tab)

How Telegram-iOS lays out the own-profile header as the list scrolls, collapses and expands —
the spec `prototype/src/ui/profile-scroll.js` implements. Own profile, profile colour, dark
theme, one photo. Upstream f1dd7a2.

Files: **H** `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoHeaderNode.swift`,
**Scr** `…/PeerInfoScreen/Sources/PeerInfoScreen.swift`, **AL**
`submodules/PeerInfoAvatarListNode/Sources/PeerInfoAvatarListNode.swift`, **Cov**
`…/PeerInfoCoverComponent.swift`, **NB** `…/PeerInfoHeaderNavigationButtonContainerNode.swift`.
`co` = scroll offset, `S` = status bar height, `N` = S + 60, `W` = screen width.
`transitionFraction` is hard-coded to 0 (H:638-642).

## 1. Scroll-up collapse (co > 0, not expanded)

- **Master fraction** (H:1706-1744, 1766): `T = titleFrame.midY − S − 24` (lock 16 + 8 for the own
  account in Settings) ≈ 107 + th/2 ≈ 123.5 with th ≈ 33; `f = clamp(co / T)`; `lockY = 7f`.
- **Avatar** (H:1863-1867, 1926-1932, 1967): scale `1 − 0.45f` (100 → 55 pt); centre
  `(W/2, S + 72 − co + 17f)`, not clamped (keeps scrolling); alpha constant. Without a Dynamic
  Island the only clip is at y = 0 (H:2003-2006); with one, a clip at y = 47 (radius W/2.5) plus a
  Lottie mask, blur and black cover driven by `clamp(co/120)` (H:2003-2008, 2035-2066).
- **Title** (H:1737, 2168, 2174, 2186): centre y `titleFrame.midY − min(co, T) + 7f`, locking at
  **S + 31**; scale `1 − 0.4f` → 0.6 (16.8 pt). Text + 4 pt + 26 pt emoji stays centred at W/2.
- **Status emoji** (H:246-250, 1623-1640): inside the title, scales and moves with it.
- **Subtitle** (H:1754, 1802-1804, 2169-2197): centre `(titleFrame.maxY + 1 + h/2) − min(co, T) − f`
  (another −f·scale inside), scale `1 − 0.2f`, alpha `1 − f`.
- **Banner** (H:780-801, 2087-2103, 2486-2512): from the top to `N + max(0, 155 − co)`; the 254 pt
  gradient (main bottom → secondary top) is anchored to the banner's bottom with a solid secondary
  fill above (Cov:497-534). The 380 × 254 pattern is centred on the moving avatar; each item:
  `t = min(1, (72 + 28·row)/144)`, `s = 1 − bez(.6,0,.4,1)(clamp((t + 0.8 − 2.88f)/0.8))`,
  `dist = lerp(base, 20, s)`, `alpha = 1 − s` (Cov:37-62, 600-638). The 300 pt glow has alpha `1 − f`.
- **Snap-off**: `g = clamp((co − (N − 15))/50)`; when g > 0.5 (co > **S + 70**) the banner fades
  1 → 0 over **0.2 s ease-in-out** (back in when scrolling back). At the same point the title,
  subtitle and navigation colours step to the collapsed set (H:846-861).
- **Navigation background** (H:2583-2599; Scr:1266, 5989; EdgeEffect.swift:36-88):
  `headerEdgeEffectView`, inside the scroll view pinned at the top, above the list and below the
  header; frame y −50 … N + 18, plain background (#000 dark) at **0.75**, opaque to N − 42 then
  fading over 60 pt (mask 1, .98, .94, .85, .69, .48, .29, .14, .05, .03, 0 every 6 pt); a very light
  backdrop blur. No separator. It is revealed when the banner fades.
- **Navigation buttons** (H:1127-1130, NB:76-105, 356-373): fixed frames; at the colour step the
  glass tint changes from the header button colour to `.panel` over 0.2 s; glyphs stay white in dark.

## 2. Pull-down and expansion

- **Before the trigger** (−32 < co < 0): avatar, title and subtitle move down 1:1; the banner grows
  to N + 155 + |co|; gradient bottom-anchored; pattern and glow follow the avatar.
- **Trigger** (Scr:6006-6040): expand when `co ≤ −32 && isDragging && isTracking` (has a photo, no
  upload, portrait), haptic `impact()`; collapse when `co ≥ 1` at any time, haptic `tap()`.
  Animation `.animated(0.35, .spring)` = CABasicAnimation **0.35 s, cubic-bezier(0.38, 0.70, 0.125, 1.0)**
  (CAAnimationUtils.swift:119-186), applied additively over the live layout.
- **Expanded layout** (H:1162-1170, 1941-1995, 2005): height `He = min(W, screenH − 61) + 60`
  (W + 60 on phones); container centre `(W/2, W/2 − co/2)`, scaled by `s = 1 + max(0, −co)/W` with the
  bottom glued to He + |co|. Corner radius 50 → 0 (H:1904-1905).
- **Photo**: a W × W square on top (AL:570-576, 1678-1682); the 60 pt below it is the photo's
  bottom ~21 pt mirrored and stretched ×3 (CAReplicatorLayer, AL:809-818).
- **Shadows**: bottom He − 88 … He, variable blur (max 15) + black 0 → 0.4 at alpha 0.8
  (H:1698-1704, AL:683-783, 1066-1110); top 0 … N + 20, black 0.4 → 0 (H:2024-2027).
- **Text**: title scale 0.8, left edge 16, visual top He − 58 − 1 px (+|co| when pulled), white
  (H:1714-1720, 2163-2182); subtitle crossfades to a 16 pt regular line, left 16, 2 pt under the title
  (H:1236-1237, 1451, 1729-1731). Navigation buttons: glass tint black 0.5 (H:831-840).
- **List**: first section moves to He + 15, animated additively (H:2613-2615).

## 3. Scrolling

- The header node is a full-screen sibling above the UIScrollView, re-laid out on every
  `scrollViewDidScroll` (Scr:1264-1271, 5984-6046). The list starts at **N + 171** (Scr:5442-5445).
  `contentInset.top = 0`; content height ≥ screenH + 140 − bottom inset (Scr:1259, 5745-5749).
- Releases whose target is between 0 and 140 snap to 0 (< 70) or 140 (Scr:6097-6125).

## 4. Avatar gestures

- The collapsed avatar has only a tap recognizer (PeerInfoAvatarTransformContainerNode.swift:71-72,
  174-178): stories if any, otherwise it expands with the same 0.35 s curve, no haptic
  (Scr:1496-1516). The long-press context gesture is disabled in every branch (same file :275-281).
- The header's `hitTest` returns the avatar view for touches on the avatar, so **a drag that starts
  on the avatar never reaches the scroll view** — it neither scrolls nor pulls (H:2776-2868). The glass
  avatar therefore owns drags in every direction without taking anything away from scrolling.
