# Telegram-iOS reference — profile header, glass, motion, theme, MetalEngine

Source: `TelegramMessenger/Telegram-iOS` @ `f1dd7a2` (master, 2026-10-07, app **13.0**, Xcode 26.6, Bazel 9.2.0).
Verbatim copies of every file cited here live in [`src/`](src/) (same relative paths, GPLv2).
Machine-readable values: [`tokens.json`](tokens.json). All metrics are points; `H` = `PeerInfoHeaderNode.swift`, `S` = `PeerInfoScreen.swift` (both in `submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/`).

**Calibration against the user's own screenshots.** The formulas below reproduce `research/source/screenshots/user-01.jpg` exactly when the device is taken as **414 × 896 pt, status bar 48 pt** (iPhone 11 class, no Dynamic Island, 1.4275 px/pt in the 591‑px screenshot): avatar centre 171 px = 120 pt = 48 + 22 + 50, diameter 142.5 px = 99.8 pt, QR button spans 16…60 pt, section gap 24 pt, the crow pattern sits exactly on the LokiRng positions listed in `tokens.json → cover.pattern.items`.

---

## 1. Profile header layout (`PeerInfoHeaderNode`)

### Avatar
| what | value | ref |
|---|---|---|
| size | 100 (200 in form sheet) | H:534 |
| frame | `x = floor((w-100)/2)`, `y = statusBarHeight + 22` | H:644 |
| corner | `size/2` (forum: `floor(size*0.25)`), changes animate 0.3 s easeInOut | PeerInfoAvatarTransformContainerNode.swift:328-339 |
| placeholder letters | SF Rounded Bold `floor(100*16/37)` = 43 pt | PeerInfoAvatarTransformContainerNode.swift:61, AvatarNode.swift:30 |
| story ring | lineWidth 3, inactive 1.5; avatar shrinks by 12 pt when stories exist | PeerInfoAvatarTransformContainerNode.swift:166-171, H:1962-1966 |
| clipping node | `alpha = 0.996`, `clipsToBounds` | H:222-225 |

Node tree: `avatarClippingNode → PeerInfoAvatarListNode.containerNode → [bottomCoverNode, pinchSourceNode.contentNode → [avatarContainerNode (PeerInfoAvatarTransformContainerNode), listContainerTransformNode → listContainerNode (expanded gallery)], topCoverNode (DynamicIslandBlurNode)]` (PeerInfoAvatarListNode.swift:32-58). The collapsed avatar gets **only a tap** (`UITapGestureRecognizer`, PeerInfoAvatarTransformContainerNode.swift:71-72) and a `ContextControllerSourceNode` whose context gesture is disabled in every branch (:275-281; corrected — an earlier note said it was enabled outside Settings). Because the header's `hitTest` returns the avatar view (PeerInfoHeaderNode.swift:2776-2868), **a drag that starts on the small avatar does nothing at all — it neither scrolls nor pulls the header** — that is the empty slot the glass avatar fills (see `header-scroll.md`).

### Title / subtitle / username
- Title: `Font.medium(28)` (SF Pro 500), centred, `y = avatar.maxY + 9` (+11 if no subtitle); width `w − 72` (−20 premium/verified/fake, −60 if >1 right nav button) — H:1226, 1352-1359, 1737.
- Emoji status: 26×26 container (80×80 animation), 4 pt gap after the title — H:917-918, 1622-1660.
- Subtitle: `Font.regular(17)`; Settings shows `phone • @username`; `y = title.maxY + 1` — H:1230-1238, 1754-1758. Username `Font.regular(16)`, spacing 4 — H:1694.
- Expanded (photo) state: title scaled 0.8, left at x = 16, `y = expandedH − bottomInset − 58 − 1px` (−83 for other people) — H:1696, 1715-1729.

### Music row (profile song)
`height = 24` with profile colour/expanded else 16 (H:586). Track `Font.semibold(12)` + `" - artist"` `Font.regular(12)`; overlay colours white / white 0.7, plain colours accent / secondary; HStack spacing 4, marquee `maxWidth = w − 96`, icons `Media Editor/SmallAudio`, `Item List/InlineTextRightArrow` (H:2638-2700). Its background is a full-width 24 pt band inside `buttonsMaskView`, i.e. it shares the blurred button background.

### Action buttons (call / mute / video / search / more …)
`PeerInfoHeaderButtonNode` — height **58**, spacing 8, side inset `max(16, containerInset)`, width `(w − 2·inset + 8)/n − 8`, `y = backgroundHeight − bottomInset − 16 − 58` (H:2273-2334). Icon 40×40 at y = 1, label `Font.regular(11)` **lower-cased** at `h − textH − 9`, corner `min(16, h/2)`; highlight alpha 0.4 → back over 0.2 s; inactive 0.3 (PeerInfoHeaderButtonNode.swift:102-115, 179, 294-329). The background is a single blurred `NavigationBackgroundNode` tinted `contentButtonBackgroundColor`, masked by one white view per button (H:273-277, 2337-2342). Collapse: content drops by `h·0.5·(1−f)` and scales to `f` (`innerButtonsTransitionFraction`, step 58, inset 28 — H:2265-2269).
`PeerInfoHeaderActionButtonNode` (Message/Add): height 40, corner 11, accent fill, `Font.semibold(16)` (PeerInfoHeaderActionButtonNode.swift:27, 74, 78).

> ⚠️ The designer video (t.me/designers/266) shows **circular** buttons with the label *under* them and a **capsule** music pill — a newer, unreleased layout. Master 13.0 ships the rounded-rect tiles above.

### Navigation buttons (back / Edit / QR / Search)
Bar height **60** (68 form sheet) at `y = statusBarHeight` (S:5868-5872). Buttons are **44 pt** high, side inset 16, `y = floor((60−44)/2)+2 = 10` → centre at `statusBar + 32`. Icon buttons 44×44; text buttons `textWidth + 24`, `Font.medium(17)` (`Done` semibold). Each side is one glass capsule (`GlassContextExtractableContainer`, radius h/2, `isInteractive`). Over a profile colour the glass tint is `.custom(style: .default, color: headerButtonBackgroundColor)` and contents are white; otherwise `.panel` and `theme.chat.inputPanel.panelControlColor`. Buttons fade with `alpha = f²` and blur `(1−f²)·5 pt` (PeerInfoHeaderNavigationButtonContainerNode.swift:110-373, PeerInfoHeaderNavigationButton.swift:283-348). Settings: left `qrCode`, right `search` + `edit` (S:5884-5887).

### Collapse-on-scroll math (H:1706-1764, 1848-1867, 1926-1932)
```swift
titleLockOffset      = 16 (+8 own Saved Messages / no subtitle);  titleMaxLockOffset = 7
titleCollapseOffset  = titleFrame.midY - statusBarHeight - titleLockOffset
f                    = clamp(contentOffset / titleCollapseOffset)      // titleCollapseFraction
titleScale           = lerp(1, 0.6, f);  subtitleScale = lerp(1, 0.8, f)
avatarScale          = lerp(1, 0.55, f)  // sublayerTransform scale on avatarContainerNode
avatarOffset         = 7·f + 10·f;       titleOffset = -min(titleCollapseOffset, contentOffset)
```
The coloured banner snaps off (alpha 1→0, 0.2 s easeInOut) once `innerBackgroundTransitionFraction > 0.5` (step 50, distance `navH + 135 − 50`, −100 for Settings) — H:717, 728, 780-802.

### Dynamic Island merge (H:2035-2066, DynamicIslandBlurNode.swift)
- `maskValue = clamp(contentOffset/120)` drives the Lottie mask **`UserAvatarMask.tgs`** (512², 60 fps, 540 frames, rect + ellipse "Long Circle"; copied to `src/Telegram/Telegram-iOS/Resources/`). Mask 171×171 at `y = 48 + 85 (+overscroll)`, expanded scale `w/100`, anchor (0.5, 0.37).
- `bottomCoverNode` = black × maskValue; `topCoverNode` = dark `UIBlurEffect` driven by a paused `UIViewPropertyAnimator` (`fraction = −0.1 + v·1.1`), black fade `clamp(−0.25 + v·1.55)`, radial vignette 100×100 centred (50, 88) r = 90, stops [0 clear, 0.87 clear, 1 black].
- On Dynamic Island phones the avatar clip starts 47 pt from the top with corner `w/2.5` (0.15 s easeInOut) — H:2003-2008. (The user's iPhone has no island, so this path is off there.)

### Expanded avatar (pull-down / tap)
List height `min(w, H − 61) + 60` (Settings) or `+ 98` (H:1162-1170). Bottom shadow = `VariableBlurView` max 15 pt with an 8-step mask, height 88 (+100 for others); top shadow black 0.4→0, `navH + 20` tall; page strip `y = statusBar − 3`, 2 pt, inset 8, spacing 4, inactive alpha 0.2; paging threshold |vx| > 10 or |fraction| > 0.5, animated `.spring` 0.3 s (PeerInfoAvatarListNode module :700-781, 1073-1090, 1299-1345, 1577-1624). Expanded colours: contents white, header buttons black 0.5, content buttons white 0.1 (H:646-665).
Pull-to-expand: `offsetY ≤ −32` while dragging → `.animated(duration: 0.35, curve: .spring)` + `hapticFeedback.impact()`; collapse at `offsetY ≥ 1` + `hapticFeedback.tap()` (S:6006-6040). Tap → same 0.35 s spring (S:1506-1514).

### Colours over a profile colour (H:647-701)
```swift
secondary        = UIColor(white: 1, alpha: 0.6).blitOver(main.withMultiplied(hue: 1, saturation: 2.2, brightness: 1.5), alpha: 1)
contentButtonBg  = (dark ? black(0.25) : white(0.25)).blendOver(background: main)                       // overlay blend
headerButtonBg   = (dark ? black(0.25) : white(0.25)).blendOver(background: secondary.mixedWith(main, alpha: 0.1))
```
Colour helpers: `withMultiplied` (HSB clamp), `mixedWith` (lerp), `blitOver`, `blendOver` (= per-channel overlay, then blit) — `Display/Source/UIKitUtils.swift:246-405`. Profile palettes are **server data** (`help.getPeerProfileColors` → `PeerNameColors.profileColors`), not constants. Sampled from the user's dark screenshot: top (secondary) `#3d977d` → bottom (main) `#30697c`, glass nav button `#2b795d`.

---

## 2. Cover: gradient + emoji pattern (`PeerInfoCoverComponent`), floating gifts (`PeerInfoGiftsCoverComponent`)

- **Height** `defaultHeight` 254 (327 for a star-gift status with buttons, +60 tablet) — H:552-569.
- **Gradient**: profile colour = axial, bottom `main` → top `secondary`, background fill `secondary`; star-gift = radial from `gradientCenter (0.5, 0.5|0.45)` to (1,1) — Cover:485-531.
- **Avatar glow**: 300×300 radial white, alphas `0.4·(1−i/5)²` (6 stops), opacity `1 − avatarTransitionFraction` — Cover:242-252, 573-580.
- **Pattern**: 5 rings × 6 icons inside a 380 × defaultHeight frame centred on the avatar; ring radius `50 + 22 + 28·row`; icon `floor(26·(0.7 + 0.3·rng))` with `LokiRng(seed 123,0,0)`; angle `−π/2 + i·π/3` (+π/6 on odd rows); icons tinted black 0.8 and masked into a radial `black 0.6 → 0` layer with `overlayBlendMode`. On scroll they slide to radius 20 and fade via window `bezier(0.6,0,0.4,1)` (window 0.8, fraction ×1.6); appear from the avatar centre with a 0.4 s spring; colour change bounces `[1, 1.14, 1]` — Cover:37-62, 294-307, 360-366, 536-650. All 30 exact positions/sizes (LokiRng ported bit-exactly) are in `tokens.json`.
- **Pinned gifts** (master): up to 12 icons 32×32 placed by `PositionGenerator` (min distance 42, padding 5, scale 0.7–1.15, inner orbit 1.4–2.2 r ×4, outer 2.5–3.6 r, exclusion rects for buttons/title), idling with hover ±1–2 pt (3.5–4.5 s), wiggle ±0.025–0.05 rad (2–3 s), glow scale 1→1.2, star emitter (birth 8/s, life 2 s) — Gifts:226-361, 391-460, 600-840. **The glass bubbles in the designer video are not in master.**

---

## 3. Glass

### iOS 26 native (`GlassBackgroundView`, GlassBackgroundComponent.swift:505-826)
`UIVisualEffectView(effect: UIGlassEffect(style: .regular))`; `.panel` tint white 0.025 (dark) / 0.1 (light); `.custom` = `.regular` + tint colour; `.clear` = `UIGlassEffect(.clear)` (+ black 0.28 in dark); `isInteractive` passes through; private luma clamp dark 0…0.15, light 0.8…0.801. Neighbours merge through `UIGlassContainerEffect` (`GlassBackgroundContainerView`, :847+).

### Pre-iOS 26 fallback (`LegacyGlassView.swift:129-232`, GlassBackgroundComponent.swift:1110-1290)
Private `CABackdropLayer` (scale 1) with `colorMatrix` saturation boost (matrix in tokens) + `gaussianBlur` 2 pt (6 pt for `.clear` on weak GPUs), refracted at the edge by a private **`meshTransform`** from `generateGlassMesh` (20 pt pull, edge band `min(12, r)`, outer boost ×1.5 over 2 pt, easing bezier (0.816, 0.205, 0.581, 0.873) — MeshTransform/Sources/GenerateMesh.swift:447-483). Foreground: fill (light white 0.7) + 0.8 pt rim, white 0.6 light / 0.3 dark, drawn with **asymmetric corners** (full radius top-left/bottom-right, smaller elsewhere) → the two-corner specular; shadows 30 pt @0.045 + 20 pt @0.01.

### Touch "lift" (`TouchEffect.swift:105-315`)
`sublayerTransform` driven by `CASpringAnimation`: **lift-on** m 1.36 / k 568 / c 39.7 (ζ 0.71), **lift-off** m 2 / k 460 / c 21.8 (ζ 0.36, bouncy); pressed +20 pt; drag stretch `k = 1 − 1/((len/H)/(5·aspect)+1)`, dominant axis ×(1+t·diff), other ÷, translate `normal·24·k`; radial white highlight 300×300 @0.1 following the finger (in 0.12 s, out 0.22 s).

### Liquid-glass shapes + real refraction (`LiquidGlassShapes/`, the in-repo basis for bubbles/blobs)
1. `createBackdropLayer()` (private `CABackdropLayer`, scale 1) + `gaussianBlur(1.0)`, masked by a Metal-rendered union of the shapes (LiquidGlassBackdropLayers.swift).
2. Sibling `MetalEngineSubjectLayer` named `liquidGlassDisplacementMap` (zPosition −1); container `filters = [CAFilter "displacementMap"(inputSourceSublayerName, inputAmount −32, inputOffset (0.5,0.5))]` — **iOS 26+ only** (`makeDisplacementMapFilter`, UIKitUtils.m:285-291).
3. Map: `RG = saturate(0.5 − 0.5·s/32)`, `s = Σ inwardNormal · glassShift · (1 − d/glassBand)² · coverage` (LiquidGlassShapes.metal:499-524). With the shipped `glassBand 20, glassShift 10` content near the rim is pulled from inside; **`glassShift > band/2` folds and mirrors it** — exactly the mirrored text visible inside the video bubbles.
4. Colour = `B·multiplier + addend` split into a `multiplyBlendMode` layer and a `plusL` layer: fill under a white matte, saturation multiply, 1 pt rim (×0.45 in dark), erf-blurred soft shadow (strength 0.07, σ 6, drop 2). Shipped styles: call status-bar waves and the voice-recording blob (`tokens.json → glass.liquidGlassShapes.shippedAppearances`).

---

## 4. Motion & haptics

| curve | definition | ref |
|---|---|---|
| `.spring`, duration **0.5**, iOS < 26 | `CASpringAnimation` m 3, k 1000, c 500 (ζ 4.6) | UIKitRuntimeUtils/UIKitUtils.m:53-66 |
| `.spring`, duration 0.5 or exactly 0.3832, iOS 26 | m 1, k **555.027**, c **47.118** → ζ = 1.0, ω₀ = 23.56 rad/s (critically damped), 80–120 fps | UIKitUtils.m:68-84, CAAnimationUtils.swift:119-147 |
| `.spring`, any other duration (0.35 avatar expand, 0.3 paging, 0.4 cover) | `CABasicAnimation`, **cubic-bezier(0.380, 0.700, 0.125, 1.000)** | CAAnimationUtils.swift:176-200 |
| `makeSpringBounceAnimation` / `animateSpring` | m 5, k 900, c = damping (default 88 → ζ 0.66), duration = settlingDuration | UIKitUtils.m:86-104, CAAnimationUtils.swift:312-345 |
| `.customSpring(mass:5, stiffness:900, damping:, initialVelocity:)` | speed rescaled so it fits the requested duration | ContainedViewLayoutTransition.swift:44-55, CAAnimationUtils.swift:73-118 |
| `ComponentTransition…bounce(stiffness:damping:)` | → `animateSpring` (mass 5) | ComponentFlow/Source/Base/Transition.swift:22-35, 146-175 |
| easeInOut / easeIn / slide | (0.42,0,0.58,1) / (0.42,0,1,1) / (0.33,0.52,0.25,0.99) | ListViewAnimation.swift:112-122 |

Other durations: header colours 0.2 easeInOut, overlays fade 0.25, avatar corner 0.3 easeInOut, island clip radius 0.15, cover animate-in 0.2 delay + 0.4 spring, panel subtitle swap 0.4 spring / 0.3 alpha / 100 pt shift.
`HapticFeedback` (Display/Source/HapticFeedback.swift): `impact(_ style: .light|.medium|.heavy|.soft|.rigid|.veryLight|.click05|.click06, intensity:)`, `tap()` (selection), `success/error/warning()`, `ContinuousHaptic(duration:)`. Profile uses `impact()` when the avatar expands and `tap()` when it collapses (S:243, 6011-6034).

---

## 5. Theme, fonts, lists

| token | dark (Night) | day |
|---|---|---|
| blocks background | `#000000` | `#efeff4` |
| item block | `#1c1c1d` | `#ffffff` |
| primary / secondary text | `#ffffff` / `#98989e` | `#000000` / `#8e8e93` |
| accent | `#ffffff` (blue variant **`#3e88f7`**, as on the user's phone) | `#0088ff` |
| destructive | `#eb5545` | `#ff3b30` |
| separator | `#545458` @0.55 | `#c8c7cc` |
| disclosure arrow | white @0.28 | `#bab9be` |
| panel control (nav glyphs) | `#ffffff` | `#000000` |
Refs: DefaultDarkPresentationTheme.swift:7, 412-477; DefaultDayPresentationTheme.swift:56, 472-510.

Fonts: `Font.regular/medium/semibold` = `UIFont.systemFont` weights 400/500/600, `bold` = `boldSystemFont` (Display/Source/Font.swift:291-306). iOS adds size-dependent SF tracking automatically — a web replica must add it by hand.
Inset sections: spacing 24, inset `max(16, floor((w−674)/2))`, first gap `24 + 12`, **corner 26 (glass)** / 11 legacy (S:5411-5480, PresentationResourcesItemList.swift:362-392). Disclosure row: side 16, icon 30×30, text x 61, height `textH + 32` (≈52 pt; measured 52.2), `Font.regular(17)` (PeerInfoScreenDisclosureItem.swift:156-242).
Avatar placeholder gradients (bottom→top): `#ff516a/#ff885e`, `#ffa85c/#ffcd6a`, `#665fff/#82b1ff`, `#54cb68/#a0de7e`, `#4acccd/#00fcfd`, `#2a9ef1/#72d5fd`, `#d669ed/#e0a2f3` (AvatarNode.swift:322-345, 1004-1015).

---

## 6. MetalEngine (how a Telegram shader layer is built)
```swift
final class CoinLayer: MetalEngineSubjectLayer, MetalEngineSubject {
    var internalData: MetalEngineSubjectInternalData?
    func update(context: MetalEngineSubjectContext) {
        context.renderToLayer(spec: RenderLayerSpec(size: RenderSize(width: w, height: h), edgeInset: 2, prefersDedicatedSurface: true),
                              state: CoinRenderState.self, layer: self, commands: { encoder, placement in
            var rect = SIMD4<Float>(Float(placement.effectiveRect.minX), Float(placement.effectiveRect.minY),
                                    Float(placement.effectiveRect.width), Float(placement.effectiveRect.height))
            encoder.setVertexBytes(&rect, length: 16, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        })
    }
}
final class CoinRenderState: RenderToLayerState {          // one instance per type, cached by the engine
    let pipelineState: MTLRenderPipelineState
    init?(device: MTLDevice) { /* MetalEngine.shared.pipelineCache.makeRenderPipelineState(descriptor:) */ }
}
// drive: SharedDisplayLinkDriver.shared.add(framesPerSecond: .fps(60)) { layer.setNeedsUpdate() }
```
`context.compute(state:inputs:commands:)` returns a `Placeholder` usable as an input to later `renderToLayer` calls; shaders ship in an `apple_resource_bundle` (see `LiquidGlassShapes/BUILD`). Reference implementation: `LiquidGlassShapesLayer.swift` (4 passes into 4 sublayers per frame) — MetalEngine.swift:131-524.

---

## 7. Where a glass coin plugs in
- **Gesture**: add a `UIPanGestureRecognizer` next to the tap on `avatarContainerNode.avatarNode.view` (PeerInfoAvatarTransformContainerNode.swift:71-72); allow it only while `!isAvatarExpanded`, fail it for mostly-vertical starts so the scroll view keeps pull-to-expand, and cancel the context gesture once it begins (context fires at ~0.32 s).
- **Transform**: the header already owns `sublayerTransform` scale on `avatarContainerNode` (H:1926-1932) — put the 3D rotation on `containerNode.layer.transform` (or a new child) so both compose.
- **Photos to flip through**: `avatarListNode.listContainerNode.galleryEntries` / `items`.
- **Refraction**: reuse the `LiquidGlassBackdropLayers` recipe (backdrop + displacement map, iOS 26+) with a coin-shaped map; fall back to `LegacyGlassView`-style mesh/colour-matrix glass below 26.
- **Motion/haptics**: release with the iOS 26 spring (k 555.027, c 47.118) or `customSpring` with the gesture velocity; `HapticFeedback().impact(.light)` per face, `.tap()` on settle.
