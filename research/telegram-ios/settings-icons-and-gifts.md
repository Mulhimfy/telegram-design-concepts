# Settings icons that animate on return · glassy tilting gift tiles

This is the research for two new concepts in the web replica (`prototype/`). Sources:
- iOS upstream `f1dd7a2` (13.0, iOS 26 design).
- Android upstream `f2908b1`: DrKLO/Telegram 12.10.6, 2026-09-30, sparse clone in `vendor/Telegram-Android`.

Every number carries a file:line. Derived numbers say how they were computed. Conventions are as in `README.md` and `chat-list-swipe.md`:
- all values are points;
- `W` = screen width;
- `SB` = status-bar height (48 on the user's 414 × 896 phone);
- `p` = transition progress;
- Night/Day theme values are in `README.md §5`.

**iOS files** (paths under `submodules/`):
| key | file |
|---|---|
| PSI / PSA | `TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoSettingsItems.swift` / `PeerInfoScreenSettingsActions.swift` |
| PDI / PSB | `…/PeerInfoScreen/Sources/ListItems/PeerInfoScreenDisclosureItem.swift` / `PeerInfoScreenSelectableBackgroundNode.swift` |
| PS / PD / PPC | `…/PeerInfoScreen/Sources/PeerInfoScreen.swift` / `PeerInfoData.swift` / `PeerInfoPaneContainerNode.swift` |
| PRS | `TelegramPresentationData/Sources/Resources/PresentationResourcesSettings.swift` |
| NTC / NC / VC | `Display/Source/NavigationTransitionCoordinator.swift` / `Display/Source/Navigation/NavigationContainer.swift` / `Display/Source/ViewController.swift` |
| NB / NBN | `TelegramUI/Components/NavigationBarImpl/Sources/NavigationBarImpl.swift` / `NavigationButtonNode.swift` |
| ILC / ILI / ILD / ILH | `ItemListUI/Sources/ItemListControllerNode.swift` / `ItemListItem.swift` / `Items/ItemListDisclosureItem.swift` / `Items/ItemListSectionHeaderItem.swift` |
| NAS / NCI | `SettingsUI/Sources/Notifications/NotificationsAndSoundsController.swift` / `NotificationsCategoryItemListItem.swift` |
| PAS | `SettingsUI/Sources/Privacy and Security/PrivacyAndSecurityController.swift` |
| GLV / GPN / GCP | `TelegramUI/Components/PeerInfo/PeerInfoVisualMediaPaneNode/Sources/GiftsListView.swift` / `PeerInfoGiftsPaneNode.swift` / `GiftContextPreviewController.swift` |
| GIC | `TelegramUI/Components/Gifts/GiftItemComponent/Sources/GiftItemComponent.swift` |
| GCC | `TelegramUI/Components/Gifts/GiftAnimationComponent/Sources/GiftCompositionComponent.swift` |
| GVS / GPC | `TelegramUI/Components/Gifts/GiftViewScreen/Sources/GiftViewScreen.swift` / `GiftPagerComponent.swift` |
| PCC | `TelegramUI/Components/PeerInfo/PeerInfoCoverComponent/Sources/PeerInfoCoverComponent.swift` |
| WCB / WCC | `TelegramUI/Components/Wallet/WalletCardComponent/Sources/WalletCardBackgroundView.swift` / `WalletCardComponent.swift` |
| PSC | `TelegramUI/Components/Premium/PremiumStarComponent/Sources/PremiumStarComponent.swift` |
| CSV / CG | `Display/Source/ContextControllerSourceNode.swift` / `Display/Source/ContextGesture.swift` |
| ETA | `TelegramUI/Components/EmojiTextAttachmentView/Sources/EmojiTextAttachmentView.swift` |
| SC / CA / UKU | `Components/SheetComponent/Sources/SheetComponent.swift` / `Display/Source/CAAnimationUtils.swift` / `UIKitRuntimeUtils/Source/UIKitRuntimeUtils/UIKitUtils.m` |

**Android files:** `A:` = `TMessagesProj/src/main/java/org/telegram/ui/`.

---

## 0. Does it already exist?

| | iOS 13.0 | Android 12.10.6 |
|---|---|---|
| **A. A Settings-row icon animates (on tap, on coming back, or ever)** | **No.** Each icon is a static, pre-rendered 30×30 `UIImage` in a layer-backed `ASImageNode` (PRS:120-133, 174-319; PDI:99-101, 220-243). Tapping only flashes the row highlight (PSB:37-61). `viewDidAppear` never touches the rows (PS:7076-7110). Sub-page rows are static too (ILD:257-258, NCI:128). | **No.** The icon is a plain `ImageView` in a gradient tile (A:SettingsActivity.java:1160-1165). `onClick` only pushes the sub-screen. There is no `onResume`/`onBecomeFullyVisible` replay. See §A3. |
| **B. Gift tiles tilt, move, or have glass/glint** | **No.** The tile's `style: .glass` only sets corner 16 instead of 10 (GIC:466-480); there is no material. The only motion is appear scale, a sticker that plays once, and the long-press shrink (§B4). Gift UIs never use CoreMotion: its only users are the TON wallet card, Mini-App motion and the camera (§B5). | **No.** The only press feedback is a scale to 0.96 (A:Gifts/GiftSheet.java:1094). No sensor is used in gift code. Swiping between gifts in the gift sheet does a flat 10° `rotationY` (A:Stars/StarGiftSheet.java:317-331). See §B5. |

Closest existing precedents:
- **A:** the tab-bar icons play their Lottie once when selected (TabBarComponent.swift:839-840, 1039-1042).
- **A:** the profile header buttons play once on tap (PeerInfoHeaderButtonNode.swift:158-166).
- **A, Android:** the "Set Profile Photo" camera icon plays forward when its menu opens and backward when the menu closes without an upload (A:ProfileActivity.java:6941-6982).
- **B:** the TON **wallet card** tilts with pan and has device-motion lighting (WCB:11-121, WCC:868-936, 1386-1424). This is the in-repo recipe for a tilting glass card.

---

## A. Settings icons that animate when you come back

### A1. What a Settings row is (iOS)
- **Row.** `PeerInfoScreenDisclosureItem`:
  - side inset 16; icon 30×30 at x 16, centred vertically (PDI:156, 242-243);
  - text at x 16 + 29 + 16 = **61** (PDI:157), regular 17 (`itemListBaseFontSize`);
  - height = text height + 32 ≈ 52 (PDI:217; measured 52.2, `README.md §5`).
- **Card.** Width `W − 32` (16 inset), corner 26 (glass) (`README.md §5`).
- **Tap feedback.** `HighlightTrackingButton`:
  - on touch-down the background turns `itemHighlightedBackgroundColor` at once (Night `#313135`, Day `#e5e5ea`; DefaultDark…:426, DefaultDay…:486);
  - on release it fades to 0 over **0.25 s** (PSB:37-61);
  - so the highlight is gone before the pushed page has settled. Nothing is left to "deselect" on return.
- **Icon image** (`renderSettingsIcon`, PRS:8-69), drawn once at launch (static `let`s):
  1. 30×30 fill;
  2. `Item List/Icons/Gradient` drawn with `plusLighter`;
  3. `Item List/Icons/Backdrop` drawn with `overlay`;
  4. white glyph mask, centred;
  5. everything outside `UIBezierPath(roundedRect:, cornerRadius: 8)` is cleared, which gives continuous-style corners.
- **Palette** (PRS:109-117): red `#FF453A`, green `#34C759`, blue `#0079ff`, light blue `#32ADE6`, teal `#00c7be`, orange `#FF9F0A`, purple `#AF52DE`, gray `#8E8E93`, violet `#5E5CE6`.

| Settings row (iOS order) | item (PSI) | icon → glyph, colour (PRS) |
|---|---|---|
| My Profile | :165 | `myProfile` → Profile, red (:133) |
| Money *(wallet, "NEW" badge)* | :186 | `money` = asset `Settings/Gram` (:222) |
| Saved Messages · Recent Calls · Devices · Chat Folders | :238 · :241 · :256 · :259 | SavedMessages blue · Phone green · Devices orange · Folder light blue (:121-124) |
| Notifications and Sounds | :269 | Notifications, red (:126). A red "!" badge replaces the label when permission is off (:269). |
| Privacy and Security · Data and Storage · Appearance | :272 · :275 · :278 | Privacy gray · Data green · Appearance light blue (:127-129) |
| Power Saving · Language | :282 · :287 | PowerSaving orange · Language purple (:131, :130) |
| Telegram Premium | :294 | 45° 5-stop gradient `#6b93ff #6b93ff #8d77ff #b56eec #b56eec` @0/.15/.5/.85/1 + Premium glyph (:174-217) |
| Your Stars · My GRAM | :310 · :327 | `stars` gradient `#fec80f→#dd6f12` (:224-…) · `gramEarnings` blue (:220) |
| Telegram Business | :333 | Business, `#A95CE3`/`#F16B80` (:132) |
| Send a Gift | :339 | `premiumGift` 5-stop `#3ba1f2 #3ba1f2 #39b3b4 #34c27d #34c27d` + Gift glyph (:267-…) |
| Ask a Question · Telegram FAQ · Telegram Features | :358 · :361 · :364 | Support orange · Faq light blue · Tips `#ffcc02` (:317-319) |

### A2. Evidence that nothing animates (iOS)
- **The icon is a static image in a static node.** It is an `ASImageNode` with `isLayerBacked = true` (PDI:99-101), and `self.iconNode.image = icon` is set on every layout (PDI:220-243). The only async variant is `iconSignal`, used for bot apps (PSI:231). It swaps the bitmap once and never animates.
- **The resources are `static let` images.** No Lottie, no layers, no state (PRS:120-319).
- **Coming back does not touch the rows.**
  - `PeerInfoScreen.viewDidAppear` only sets `didAppear`, wires the back-button menu and refreshes personal channels (PS:7076-7110).
  - `viewWillDisappear` dismisses tooltips (PS:6913-6924).
  - `openSettings(section:)` only builds and pushes the controller (PSA:22, 98-101 Notifications, 102-… Privacy).
- **Sub-page rows are static too.**
  - `ItemListDisclosureItem` icon: `ASImageNode` layer-backed (ILD:257-258).
  - `NotificationsCategoryItemListItem`: ASImageNode (NCI:128).
  - The only animation caches in these items are for custom-emoji labels (ILD:654-655; PDI:191-197).

### A3. Android (A: = DrKLO/Telegram `f2908b1`)
- **The Settings tab is `SettingsActivity`** (A:MainTabsActivity.java:815-824).
- **Rows** use `SettingCell.Factory.of(id, top, bottom, R.drawable.settings_*, …)` (A:SettingsActivity.java:688-740).
  - Order: Account, Chat Settings, Privacy, Notifications, Data, Folders, Devices, Power Saving, Language; then Premium, Stars, TON, Business, Send a Gift; then Ask a Question, FAQ, Features, Privacy Policy.
  - There are no My Profile, Saved Messages or Recent Calls rows.
  - Colours are in A:Components/IconBackgroundColors.java:4-16:

    | colour | top → bottom |
    |---|---|
    | BLUE | `#1CA5ED→#1488E1` |
    | ORANGE | `#F09F1B→#E18A11` |
    | GREEN | `#55CA47→#27B434` |
    | RED | `#F45255→#DF3955` |
    | BLUE_DEEP | `#4F85F6→#3568E8` |
    | CYAN | `#32C0CE→#1D9CC6` |
    | ORANGE_DEEP | `#F28B31→#E26314` |
    | PURPLE | `#C46EF4→#9F55DF` |
    | GRAY | `#8699AA→#6E8397` |

- **Icon look:**
  - a 24 dp glyph `ImageView` (not Lottie) inside a **28 dp tile, corner 10 dp, vertical gradient** (A:SettingsActivity.java:1160-1165, 1233-1262);
  - in dark theme the tile adds a 1 dp gradient stroke, white `0x4d → 0 → 0x1a` (same lines);
  - the old own-profile settings list (A:ProfileActivity.java:10616-10680, 13833-13895) uses static `msg2_*` icons too.
- **No replay anywhere.**
  - `onClick` only pushes (A:SettingsActivity.java:775-889).
  - The screen has no `onResume`/`onBecomeFullyVisible`/`onTransitionAnimationEnd` hook that touches icons.
  - `TextCell.imageView` *is* an `RLottieImageView` (A:Cells/TextCell.java:56, 128, 396-405), but `setColorfulIcon` uses a static drawable (:618-631).
- **Near-misses:**
  1. **"Set Profile Photo" camera icon** (`R.raw.camera_outline`, A:ProfileActivity.java:5712-5713). It plays frames 0→43 when the photo menu opens. If the menu is dismissed without an upload it plays 43→86, i.e. "the icon reacts when you come back" (A:ProfileActivity.java:6941-6982).
  2. **Glass tab bar:** each tab icon plays fill on select and reverse on deselect (A:Components/glass/GlassTabView.java:233-237, 283-397).

### A4. Animated-icon precedents to borrow (iOS)
| where | what | ref |
|---|---|---|
| Tab bar | `playSelectionAnimation()` → `LottieComponent.playOnce()` on select. Settings uses `TabSettings` unless the tab shows the avatar or **Reduce Motion** is on. | TabBarComponent.swift:839-840, 1039-1042; PS:6707 |
| Profile header buttons | Voice chat / More / Leave play once on tap. Mute ↔ unmute play the transition and otherwise seek to the end. | PeerInfoHeaderButtonNode.swift:158-166, 229-251 |
| Sub-page header stickers | e.g. Chat Folders `ChatListFolders`: `playbackMode = .once`, plays when shown | ChatListFilterSettingsHeaderItem.swift:125-160 |
| Chat-list swipe icons | rest on `startFrame`, play once when revealed | `chat-list-swipe.md §6` |

### A5. Push/pop between Settings and a sub-page (iOS 26)
`NavigationTransitionCoordinator` drives both pages. Settings is a tab root inside `TelegramRootController`, so the tab bar belongs to the bottom page and slides and dims with it.

| | value | ref |
|---|---|---|
| mode | the root navigation is **not flat**: `TelegramRootController` uses the default `isFlat: false` | TelegramRootController.swift:106; NavigationController.swift:318 |
| position | push: `pos = 1 − p`; pop: `pos = p` | NTC:140-146 |
| top (incoming/outgoing) page | `x = floor(pos · W)` | NTC:160 |
| bottom page **parallax** | `x = (pos − 1) · W · 0.3` (flat mode would be `−(1 − pos)·W`) | NTC:161 |
| dim over the bottom page | black, **α = (1 − pos) · 0.15**, frame `x 0 … topX + 62`. The 62 pt runs under the top page so its rounded corners show dimmed content. | NTC:70, 173, 175 |
| shadow | 16-pt strip (black @0.5, blur 16, fading leftward), α `(1 − pos)·0.9`, at `topX + 46 … topX + 62`. It sits *under* the top page and the dim, so it shows only through the corner cut-outs. | NTC:10-19, 174, 176 |
| top-page corners during the transition | `screenCornerRadius`, continuous curve. That is **41.5** on the user's XR/11-class phone and 62 on the 16 Pro. Restored to 0 at the end. | NTC:110-122, 339-348; DeviceMetrics.swift:294-317 |
| navigation bars | they move with their pages. The inline bar transition is a no-op at this commit, and Settings returns no custom transition node. | NTC:194-230; PS:6716-6719 |
| button push / back pop | `animateCompletion(0)` → `.animated(duration: 0.5, curve: .spring)` | NC:515; NTC:329 |
| that curve on iOS 26 | `CASpringAnimation` m 1, k 555.027, c 47.118, `duration = 0.5`, speed 1. Critically damped (ζ 1.000, ω₀ 23.559 rad/s): **x(t) = 1 − (1 + 23.559 t)·e^(−23.559 t)** for 0 ≤ t ≤ 0.5 s. | CA:147-148; UKU:53-56, 68-84 |
| samples (t s → x) | .025→.118, .05→.329, .075→.527, .10→.682, .15→.868, .20→.949, .25→.981, .30→.993, .40→.999. 50 % at 71 ms, 90 % at 165 ms, 99 % at 282 ms. | computed from the line above |
| interactive pop | full-screen pan, not edge-only (`allowedDirections → .right`). It fails if `|vy| > 4 && |vy| > 2.5|vx|` or `vx < 4`. `p = dx / W`. | NC:141-160, 180-195, 276-280 |
| release | completes if `v > 1000` pt/s or `p > 0.2`. Completion lasts `clamp(|(1 − p)·W / v|, 0.05, 0.2)` s easeInOut; otherwise it cancels in 0.1 s easeInOut. | NC:283-305; NTC:236, 307-336 |
| status-bar style | switches at `p ≥ 0.3` | NC:260, 437-443 |
| appearance callbacks | the incoming controller gets `viewWillAppear(true)` **when the transition starts**; the completion block runs after the 0.5 s spring | NC:470-473, 515-535 |

### A6. The sub-page (iOS 26 glass style)

**Navigation bar** (`NavigationBarImpl`, glass):
- **Height and edge.** Bar height **SB + 60** (68 in a modal) (VC:263-271). There is no bar fill, only a top edge effect: height `h + 24`, edge `min(64, …)`, blurred, in the theme `edgeEffectColor` (NB:821-834). The curve is in `chat-list-swipe.md §5`.
- **Back button.**
  - A **44×44 glass circle**: `GlassContextExtractableContainer`, radius 22, tint `.panel`, `isInteractive` (NB:1006, 1017-1027).
  - Position x 16, y = SB + 2 + floor((60 − 44)/2) = **SB + 10** (NB:805-807, 880, 1006).
  - **No "Settings"/"Back" text in glass style** (NB:311-312, 327-328).
  - Arrow (NBN:8-23): a 44×44 template chevron in `theme.buttonColor`, stroke 2, round caps and joins, points (24.6, 14) → (17, 22) → (24.6, 30) (NB:639, 909).
- **Title.** SF 17 semibold with monospaced digits (NB:15), centred, y = SB + 2 + floor((60 − h)/2) (NB:1119-1124).
- **Titles used.**
  - Notifications and Sounds → **"Notifications"** (NAS:884; `Notifications.Title`, Localizable.strings:764).
  - Privacy → **"Privacy and Security"** (PAS:1617).

**List** (ItemList, `.blocks`, `systemStyle: .glass`):
- **Insets.** Side inset `max(16, floor((W − 674)/2))` = 16 (ILC:658-662). Cards have corner 26, as in Settings.
- **Spacing.** The first item without a header gets a top inset of 24 + 1 px. After another section the inset is 35 + 1 px (ILI:97-119).
- **Section header.** Regular 13 in `sectionHeaderTextColor` (Night `#8d8e93`, Day `#6d6d72`; DefaultDark…:430, DefaultDay…:490), at x 15 inside the card inset, y 7. Height = text height + 13. Top inset is 24 when first and 28 after a section (ILH:180-182, 226-233, 251).
- **Disclosure row** (ILD):
  - **Insets and height.** Text x 16 + 43 = 59 inside the card when it has an icon (ILD:418-420). Vertical inset 15 in glass (13 with a detail line), so h ≈ 30 + 20.3 ≈ 50 (ILD:519-559).
  - **Icon and label.** 30×30 icon centred in the 59-pt gutter, i.e. x 14 (ILD:607). Label right-aligned before the arrow (ILD:768, 878).
- **Category row** (`NotificationsCategoryItemListItem`):
  - Text and icon placement are the same as the disclosure row (59 and 14) (NCI:201-204, 274-275).
  - Title regular 17; subtitle regular 15 in secondary colour (NCI:206-209). Vertical inset 15, spacing 1, h = 30 + title (+1 + subtitle) (NCI:222-237).
  - Label "On" in regular 17 secondary at `W_card − 34 − w` (NCI:178, 360); arrow at the right (NCI:364).

**Notifications** (user's state: permission granted, one account, default settings):

| # | row | icon (PRS) | label | ref |
|---|---|---|---|---|
| — | header **MESSAGE NOTIFICATIONS** | — | — | NAS:562 |
| 1 | Private Chats | `privateChats` Member, blue `#0079ff` (:145) | On | NAS:451-452, 563 |
| 2 | Group Chats | `groups` Group, green (:146) | On | NAS:455-456, 564 |
| 3 | Channels | `channels` Channel, orange (:147) | On | NAS:459-460, 565 |
| 4 | Stories | `stories` Stories, violet (:148) | **Top 5** (default) | NAS:463-464, 566-577 |
| 5 | Reactions, subtitle "Messages, Stories" | `reactions` `#FF2D55` (:149) | On | NAS:467-468, 579-601 |
| — | header **IN-APP NOTIFICATIONS**: In-App Sounds / Vibrate / Preview (switches) | — | — | NAS:603-606 |

A subtitle shows only for exceptions ("3 exceptions") or for Reactions.

**Privacy and Security** (first section has no header):

| # | row | icon (PRS) | label | ref |
|---|---|---|---|---|
| 1 | Blocked Users | `block`, red (:166) | count or "None" | PAS:443, 668 |
| (2) | Active Websites, only if > 0 | `activeSessions` = Language glyph, blue (:167) | count | PAS:524, 670 |
| 3 | Passcode & Face ID | `faceId`, green (:168) | On / Off | PAS:500, 684-689 |
| 4 | Two-Step Verification | `lockOrange` = Privacy glyph, orange (:169) | On / Off | PAS:504, 695 |
| 5 | Passkey | `passkeys` Key, violet (:170) | On / Off | PAS:508, 702 |
| 6 | Auto-Delete Messages, then footer | `timer`, purple (:171) | e.g. Off | PAS:512, 718-722 |
| — | Login Email (own section) | `email`, violet (:172) | — | PAS:518, 737 |
| — | header **PRIVACY**, then rows with no icons: Phone Number, Last Seen & Online, Profile Photo, Bio, Gifts, Birthday, … | — | value | PAS:741-770 |

**Day vs Night.**
- Page `blocksBackgroundColor`: `#efeff4` / `#000000`.
- Cards `itemBlocksBackgroundColor`: `#ffffff` / `#1c1c1d`.
- Secondary text `#8e8e93` / `#98989e`.
- (DefaultDay…:473, 484; DefaultDark…:413, 417-418, 424)

On the 414 × 896 phone (SB 48):
- Notifications: header text ≈ y 139, first card ≈ 160, rows ≈ 50 pt (Reactions ≈ 69).
- Privacy: first card ≈ 132.

These are derived from the insets above, with TextNode heights 17 pt ≈ 20.3, 15 ≈ 17.9 and 13 ≈ 15.5.

### A7. Where "animate on return" plugs in

**iOS.**
- `openSettings(section:)` is the one place that knows which row was opened (PSA:22). Store it on the node.
- Fire the animation from `PeerInfoScreen.viewDidAppear` (PS:7076), which runs after the pop's 0.5 s spring. For an earlier start, use `viewWillAppear(true)` (NC:472) plus a delay.
- The row's `iconNode` would have to become a container (`ASImageNode` → view with layers or Lottie) (PDI:99-101).
- Skip the animation when Reduce Motion is on, as the tab bar does (PS:6707).

**Prototype timing (proposal, not upstream):**
- Start the icon animation about 0.2 s into the pop: the spring is at 95 % by then (§A5), so the page has just landed.
- After a swipe-back, start it when the 0.05–0.2 s completion ends.
- After a cancelled swipe, do nothing.

---

## B. Glassy, tilting gift tiles on someone's profile

### B1. Where the gifts are (another user's profile)
- **Pane order.**
  - **Stories** comes first if the user has stories.
  - **Gifts** is inserted next when `starGiftsCount > 0` (index 1, or 0 without stories) (PD:1588-1597).
  - Then Media, Files, Links, Voice, Audio, GIFs and Groups.
  - Titles are "Stories", "Gifts", "Media", "Files", "Links", "Voice", "Audio", "GIFs", "Groups" (Localizable.strings:9547, 13107, 5301-5308).
- **Tab strip.**
  - **Shape:** one glass capsule (`GlassBackgroundView`, tint `.panel`, radius h/2), **h 40, y 10**, centred, sized to its content (`layout: .fit`), max width `W − 32` (PPC:977, 1258-1261, 1366-1381).
  - **Behaviour:** the pane content starts 10 + 40 + 10 + 6 = **66** below the pane top (PPC:978); the selection lifts while switching on phones (`liftWhileSwitching`, PPC:1368).
  - The selection pill and labels (medium 15, `panelControlColor`) are as in `chat-list-swipe.md §5`.
  - Switching tabs uses `.animated(0.4, .spring)` (PPC:1339, 1352), i.e. cubic-bezier(0.38, 0.70, 0.125, 1.0) (`README.md §4`).
- **Gifts tab item** (`GiftsTabItemComponent`, PPC:54-216):
  - "Gifts" in medium 15, followed by the **first 3 gifts as 18×18 stickers**;
  - 2 pt after the text, 1 pt between stickers; each sticker plays once (`loopCount: 1`) and scales in from 0.01 over 0.2 s (PPC:95-104, 125, 150-168, 1307-1316).
- **Pane background:** `blocksBackgroundColor`, `#000` Night / `#efeff4` Day (PPC:963-964; GPN:1442).
- **Optional collections strip.** Shown only if the owner has collections: a `TabSelectorComponent` (medium 15, h 34) at the top, after which the grid starts 15 pt lower (GPN:595-725).

### B2. Grid (GiftsListView)
- **Columns:** 3 per row in portrait. Landscape or width > 480 gives 5 (4 on tablet). With fewer gifts than columns the tiles get wider, but the row height stays at the 3-column size (GLV:431-446).
- **Spacing and inset:** spacing **10**, side inset `sideInset + 16` (GLV:429-430).
- **Tile size:** square, `w = (W − 32 − 20)/3`.

| W | tile | sticker (§B3) | long-press min scale |
|---|---|---|---|
| 390 | 112.67 | 85 | 0.867 |
| 402 (16 Pro) | 116.67 | 88 | 0.871 |
| **414** (user) | **120.67** | **91** | **0.876** |
| 440 | 129.33 | 98 | 0.884 |

  Column pitch is w + 10; the first row starts at the pane top inset (GLV:449, 742-745).
- **Appear / disappear:** a tile that appears during an animated update scales 0.01 → 1 and fades in over 0.25 s. Removal is the reverse (GLV:706-712, 752-760).
- **Reorder mode:** tiles shake (`addReorderingShaking`) (GLV:729-737). This is owner-only.

### B3. Tile anatomy (`GiftItemComponent`, `style: .glass`, `mode: .profile`; GLV:541-556)

**Frame and background:**
- Size = cell size. **Corner 16** (glass) / 10 (legacy), with `cornerCurve = .circular` rather than continuous (GIC:386-391, 472-480).
- **Regular gift:** `itemBlocksBackgroundColor`, `#1c1c1d` Night / `#ffffff` Day (GIC:1305-1315).
- **Unique (collectible) gift.**
  - Fill = backdrop `outerColor`. On top sits a `PeerInfoCoverComponent(.custom(outer, inner, pattern, patternFileId))` with `avatarCenter` = tile centre and `defaultHeight` = tile height (GIC:604-623, 798-829).
  - That gives a **radial gradient inner (centre) → outer**, start (0.5, centre), end (1, 1) over a square the size of the tile height. Its radius is h/2, and outside it the fill is outer (PCC:97-106, 498-504).
  - **Pattern** = the gift's symbol (server sticker), drawn as the profile-cover rings scaled for tiles narrower than 150 pt (PCC:586-640):
    - ring radius `(50 + 22)·0.6 + 16.8·row` = 43.2, 60, 76.8, 93.6, 110.4;
    - 6 icons per ring at −90° + i·60° (+30° on odd rows);
    - size `floor(26·0.83·(0.7 + 0.3·rng))` = 15–21 pt;
    - `LokiRng(123,0,0)`, so the same random sequence as the cover (`tokens.json → cover.pattern.items`).
  - **Pattern colour:** pattern colour @0.6 at the centre fading to 0 along an ellipse with radii 190 × h/2. Each icon mask is black @0.8 (PCC:536-548, 637; mask at :270).
  - **Pattern effect:** icons at the left/right (dx ±60) are the most visible (≈0.33), the ones at the top/bottom almost vanish (dy ±52 → ≈0.06). On a 120.67 tile 16 icons fall inside: all of rings 0 and 1, plus 4 corner icons of ring 2 (computed).
- **Unique ribbon colour.** `ribbonColor = .custom(outerColor, innerColor)` (GLV:517-522).

**Sticker** (`InlineStickerItemLayer`, GIC:767-793):
- **Size:** `side = floor(88 · h / 116)`, centred both ways. It is rendered at 2× (`pointSize = 2·side`).
- **Placeholder:** `mediaPlaceholderColor`, or the backdrop colour for unique gifts.
- **Playback:** `loopCount: 1`, so it plays once when it enters the hierarchy and becomes visible. Leaving and re-entering resets the count, so **scrolling a tile back into view replays it** (ETA:632-653, 862-867, 953-958).

**Ribbon** (top-right corner; GIC:1204-1280). `Premium/GiftRibbon` (`giftline_cell.pdf`) is a **58×58** image (MediaBox).
- **Placement.** Drawn at `(w − 56, −2)`, i.e. offset (+2, −2), so it overhangs the tile's top and right edges by 2 pt (GIC:1259-1266).
- **Shape (image coordinates, y down).** A 45° band between the lines `y = x − 28` and `y = x`, about 19.8 pt wide. It runs from the top edge (x 7.7…20.0) to the right edge (y 38.0…50.3), with rounded tucks where it meets the edges. The corner triangle beyond the band is empty.
- **Fill.** A gradient along the band: `colors[0]` at the bottom-right end, `colors[1]` at the top-left end (`generateGradientTintedImage(.mirroredDiagonal)`, GenerateImage.swift:372-374 + flip). Colours by ribbon type (GIC:43-91):

  | ribbon | Day | Night |
  |---|---|---|
  | blue (limited gifts, "1 of 10K") | `#34a4fc → #6fd3ff` | `#142e42 → #354f5b` |
  | red | `#ed1c26 → #ff5c55` | `#522124 → #653634` |
  | green (sale) | `#4bb121 → #53d654` | same |
  | purple | `#747bf6 → #e367d8` | same |
  | orange | `#ea8b01 → #fab625` | same |

  Unique: both stops come from `outer`, multiplied (hue, sat, bri) by (0.97, 1.45, 0.89) and (1.01, 1.22, 1.04) (`withMultiplied`, README §1).
- **Text.** White, rotated **45°**, centred at **(w − 20, 20)** (GIC:1271-1272). Content by ribbon type (GLV:493-525):

  | ribbon | text | font |
  |---|---|---|
  | limited | `"1 of %@"` with a compact count ("1 of 10K", Localizable.strings:13111) | semibold **9** in profile (10 elsewhere) |
  | unique | `"#1234"` | SF Mono semibold 10 |
  | on sale | "sale" | semibold 10, **green**, plus a cut-out outline |

  Fonts: GIC:1205-1219. The sale outline is the ribbon image scaled +8 pt, tinted `blocksBackgroundColor`, 2 pt lower (GIC:1239-1249, 1267-1268, 1910-1915).

**Badges:**
- **Sender avatar:** 20×20 at (5, 5).
  - Regular gifts always show it; an anonymous sender shows the coloured "anonymous" avatar.
  - Unique gifts show it only when there is a message and the name isn't hidden.
  - Hidden when the gift is pinned (GLV:490-505; GIC:1282-1303).
- **Pinned:** `Peer Info/PinnedIcon` 24×24 at (3, 3). White on unique gifts, secondary-text colour on regular ones (GIC:1369-1398).
- **Unique on resale:** a "★ 1,234" price at y = h − 20, white semibold 11 with a tinted star, on a `BlurredBackgroundView` black @0.3 capsule (−6/−4 inset) (GIC:1441-1500).
- **No price is shown for regular gifts in a profile.** The stars/price button exists only in `.generic` (shop) mode (GIC:997-1163).
- **Hidden gift (owner only):** a 30 pt eye-slash in a 30 pt dark-blur circle (GIC:1322-1367, 1416-1439).

### B4. What plays, when (iOS)
| moment | what happens | ref |
|---|---|---|
| tile appears | scale 0.01→1 + fade, 0.25 s. Sticker plays once. | GLV:706-712; ETA:632-653 |
| touch-down / quick tap | **no visual feedback on the tile.** The `HighlightTrackingButton` has no highlight handler. | GIC:323, 402 |
| hold ≥ 0.12 s | context gesture: the tile **shrinks linearly** to `max(0.7, (w − 15)/w)` (≈0.876) over 0.2 s, then opens the context menu (≈0.32 s total). Released early, it springs back with 0.2 s easeOut. | CG:77, 136-178; CSV:202-283 |
| long-press menu | `GiftContextPreviewController`: preview `GiftCompositionComponent` sized `minSide × 0.66·minSide` (unique) or `minSide × 180`, plus an action list, in the global overlay | GPN:960, 1428-1435; GCP:70-97, 263-268 |
| tap | pushes **`GiftViewScreen`** (`.flatModal`, glass sheet) with all profile gifts. There is **no hero transition** from the tile. | GLV:600-691; GVS:6807 |
| sheet in | dim black @0.4 fades in 0.3 s; the sheet slides up `.animated(0.4, .spring)` | SC:204, 325-345 |
| sheet look | glass style: top corner 38, side inset 6 in portrait, bottom corner `max(24, screenCornerRadius) − 2`. Background `actionSheet.opaqueItemBackgroundColor` (`#1c1c1d` Night / `#fff` Day). | GVS:6440-6451; SC:420-430; DefaultDark…:746, DefaultDay…:1023 |
| sheet header | height 210 (regular) / 240 (unique; +58 + 16 with owner buttons). `GiftCompositionComponent`: sticker **136×136** at x centre, **y 88**, rendered at 1.6×, **plays once**. Unique: cover gradient + pattern with `avatarCenter` y 104, `defaultHeight` 300. | GVS:3245-3272, 3412-3433; GCC:820-835, 861, 966-998 |
| tap the header | replays the sticker if it isn't playing | GCC:172-189 |
| swipe in the sheet | horizontal paging between all profile gifts (`isPagingEnabled`), flat | GVS:6775-6790; GPC:87 |
| upgrade reveal (owner) | the only 3D in gift UIs: a model carousel with **edge yaw up to 25°**, scale to 0.7 past 25 % of the half-width from the centre, smoothstep | GCC:542-585 |

Android for comparison (A:, from the sparse clone):
- **Grid:** 3 columns, side padding 9 dp (A:Gifts/ProfileGiftsContainer.java:214, 224, 607).
- **Card:** corner 11 dp; sticker 80 dp that plays once (`setAutoRepeat(0)`) (A:Gifts/GiftSheet.java:1104-1106, 2624).
- **Unique background:** a radial gradient with radius `lerp(min, max, 0.35)/2`, centred at (cx, min(50 dp, cy)) (A:…:2694-2699).
- **Ribbon:** 48 dp path, default `#F55951`, text at 45° (A:…:2128-2148, 2220-2248).
- **Press:** scale 0.96 over 80 ms, back over 350 ms with overshoot 1.5 (A:…:1094; A:Components/ScaleStateListAnimator.java:15-40).
- **Tap:** opens `StarGiftSheet` with a **160 dp looping header sticker** (A:Stars/StarGiftSheet.java:2230).
- **Paging in the sheet:** `rotationY = t·10°`, scale `1 − 0.25|t|`, camera distance 3.4·h (A:Stars/StarGiftSheet.java:317-331).

### B5. Tilt / motion / glass: what exists (iOS), with the numbers to reuse

**Users of motion APIs** (GitHub code search on master = `f1dd7a2` for `CMMotionManager`, `CMAttitude`, `startDeviceMotionUpdates`, `deviceMotion`, `UIInterpolatingMotionEffect`, `addMotionEffect` and `gyro`; plus a local grep of every gift and profile component):

| user | what | ref |
|---|---|---|
| **TON wallet card** | device motion moves the lighting; pan tilts the card | WCB:11-121; WCC:107-114, 868-936, 1386-1424, 1597-1613 |
| TON transfer bubble in chat | the same shared motion source drives the card reflection | ChatMessageTransferBubbleContentNode.swift:821-826 |
| Mini Apps | `web_app_start_accelerometer`, `web_app_start_device_orientation` (`need_absolute`), `web_app_start_gyroscope` with `refresh_rate` | WebAppController.swift:1717-1735, 2740-2821 |
| chat wallpaper "Motion" | `UIInterpolatingMotionEffect` ±**32 pt**, plus scale (W + 64)/W | WallpaperBackgroundNode.swift:22, 1147-1161, 1192-1193 |
| camera | device-angle sampler | LegacyComponents PGCameraDeviceAngleSampler.m |
| **gift components** | **none.** There is no `m34`, tilt, motion or shimmer except the upgrade carousel yaw (GCC:584) and the loading shimmer. | grep of Gifts/*, PeerInfoVisualMediaPaneNode, PeerInfoCoverComponent |

**Wallet-card recipe** (WCC, WCB). This is the closest thing to "a glassy card that tilts a little":
- **Limits:** max pitch **0.20 rad** (11.5°), max yaw **0.30 rad** (17.2°), slab thickness 9, lift shadow ≤ 0.16 (WCC:107-114).
- **Pan:**
  - travel = 240·(w/361); `roll = clamp(dx/travel·0.30)`, `pitch = clamp(−dy/travel·0.20)` (WCC:1602-1607);
  - while panning, target scale **1.01** (WCC:1601);
  - on release the pan offset decays by `e^(−4·dt)` per frame (WCC:877-882).
- **Smoothing:** card and depth angles follow their targets with `1 − e^(−8·dt)`, scale with `1 − e^(−12·dt)` (WCC:913-918).
- **Transform:** `m34 = −1/650`; translate (−yaw·3, pitch·2.5); scale; rotate X by pitch, Y by yaw, Z by yaw·0.05 (WCC:1386-1424).
- **What device motion does:** **device motion never rotates the card.** It moves the "surface"/light only (`surfaceTilt`) (WCC:903-917, 1520-1523).
  - Gyro pitch/roll = `surfaceTilt × 0.9`, clamped to 0.85·maxPitch and 0.8·maxYaw (WCC:934-935).
- **Motion source** (`WalletCardBackgroundMotion`):
  - 60 Hz `.xArbitraryZVertical` (WCB:37-41); the first attitude is the reference;
  - light direction `normalize(−0.5, 0.5, 1)` fixed in that frame (WCB:19, 84-87);
  - `surfaceTilt = (atan2(−n.y, max(n.z, .15)), atan2(n.x, max(n.z, .15)))` (WCB:100-103);
  - reflection rotation smoothed with `1 − e^(−dt/0.1)` (WCB:118), and eased back in over 0.22 s cubic on resume (WCB:132-147);
  - stopped when Reduce Motion is on, the app is inactive or the card is off-screen (WCC:938-973).
- **Shading:** `WalletCardBackground.metal`, a brushed-metal radial wedge rotated by the device yaw.

**Other in-repo interaction precedents:**
- **Premium star** (SceneKit, Premium screen):
  - **tap** within 60 pt of the centre tilts it yaw ±0.6 / pitch ±0.3 rad toward the touch (20 pt dead zone) over 0.25 s easeOut, then springs back (m 1, k 21, c 5.8, `settlingDuration·0.8`) with a `tap()` haptic (PSC:171-239);
  - **pan:** yaw = dx in degrees, pitch rubber-banded (range 60, coefficient 0.4) (PSC:243-293).
- **Glass touch "lift"** (`TouchEffect`, used by interactive `GlassBackgroundView`): spring lift and a 300 pt radial highlight that follows the finger. See `README.md §3` (TouchEffect.swift:105-315).
- **Android equivalent of the star:** the Premium/Stars GL star tilts toward a tap by (40–70°)·offset/r over 220 ms easeOutQuint, then back over 600 ms with overshoot. Drag: `angleX += dx·0.5` (A:Components/Premium/GLIcon/GLIconTextureView.java:115-152). Android gift code uses no sensors. All sensor users are wallpaper parallax, Mini App sensors, raise-to-listen and VoIP proximity (A:Components/WallpaperParallaxEffect.java:33-120; A:bots/BotSensors.java:46-85).

### B6. Gift artwork we can ship (copied to `gift-assets/`)

**Licence.**
- **iOS repo:** Telegram-iOS has **no LICENSE file** at `f1dd7a2`. GitHub reports `license: null` and no commit ever touched `LICENSE`. The README only says "publish your code too in order to comply with the licences" (README.md:12).
- **Telegram's statement:** telegram.org/apps says Telegram for iOS (and Android) is "Licensed under GNU GPL v. 2 or later".
- **Android repo:** ships `LICENSE` = GNU GPL v2 (GitHub: GPL-2.0).
- **Same artwork in both repos:** several iOS files are byte-identical, once gunzipped, to Android's GPL files (marked ≡ below).
- **Correction:** `src/SOURCE.txt` says "see upstream LICENSE"; there is no such file.
- **Not included (server-side):** real profile gifts (`StarGift.file`), collectible models/patterns and the premium-gift boxes **Gift3/Gift6/Gift12** are **server stickers**. The `premiumGifts` pack is fetched at runtime (GIC:577, 593); none are in either repo, and none were downloaded.

All files are Lottie at 512², 60 fps, with no expressions. `.tgs` is gzipped JSON (`gzip -dc`). Provenance and sha1s are in `gift-assets/SOURCES.txt`.

| file (copied) | upstream path · bytes | what (layers) | frames | colour | notes |
|---|---|---|---|---|---|
| `ios/anim_gift.tgs` | TelegramUI/Resources/Animations · 30 563 | **gift box with lid** (Cap, Base, Subtract; masks) | 0–180 (3 s) | mono `#000` (tint) | ≈ `android/gift.json`, which differs only in a white fill. Used by GlobalControlPanelsContext. |
| `android/gift.json` | res/raw · 201 259 | same gift box, white fill | 0–180 | mono `#fff` | GPL file; Android uses it for upgrade toasts |
| `ios/TabGift.tgs` | Animations · 3 650 | gift box (Patch, Bow, Cover, Bottom) | 0–35 (0.58 s) | mono | attachment-menu Gift tab |
| `android/premium_gift.json` | res/raw · 323 541 | **colour star + confetti** (58 layers) | 0–180 | full colour | Android-only; premium-gift chat action |
| `ios/Cake.tgs` | Telegram/Telegram-iOS/Resources · 19 679 | **birthday cake**, 70 layers, 10 precomps | 0–180 | full colour | ≡ android `cake.json` |
| `ios/Celebrate.tgs` | Resources · 14 103 | **party popper** with confetti cubes ("boomstick") | 0–180 | full colour | ≡ android `giveaway_results.json` |
| `ios/Diamond.tgs` | Resources · 47 932 | **blue crystal** with blinks, 47 layers | 0–180 | full colour | identical to `TonLogo.tgs` |
| `ios/GramDiamond.tgs` | Resources · 13 340 | gradient diamond with "blicks" (glints) | 0–180 | blue gradient | |
| `ios/StarsBuy.tgs` | Animations · 11 142 | **gold Telegram Star** appearing | 0–56 (0.93 s) | `#ffd967` + gradient | |
| `ios/star_reaction_appear.tgs` | Animations/star_up · 5 796 | gold star appear | 0–46 | gold | |
| `ios/star_reaction_activate.tgs` | star_up · 5 659 | gold star + circle/lines/flash | 0–125 (2.08 s) | gold | ≡ `star_reaction_center/select` |
| `ios/star_reaction_effect.tgs` | star_up · 8 420 | "star eyes" burst effect | 0–90 | gold/orange | 4 precomps |
| `ios/SparklesEmoji.tgs` | Animations · 8 368 | **sparkles**, 23 layers | 0–180 | gradients | glint overlay candidate |
| `ios/GiftUpgraded.tgs` | Resources · 2 580 | "gift upgraded" icon | 0–42 | mono white | ≡ android `gift_upgrade.json` |
| `ios/PremiumStar.tgs` | Animations · 1 675 | premium star icon | 0–50 | mono white | ≡ android `star_premium_2.json` |

Not copied:
- small UI icons: `GiftUnpack.tgs` (60², 1 212), `GiftUpgrade.json` (90², 7 525), `GiftFilter{Date,Number,Price,MenuOpen,MenuClose}.tgs` (0.5–1 KB);
- `anim_collectible_generic.tgs` (≡ android `fragment.json`), `BoostReplace.tgs`;
- `PremiumUI/Resources/premium_{addone,x2,unlock}.json` (30² icons);
- `TonLogo.tgs` (duplicate of Diamond);
- `PremiumUI/Resources/gift2` (27 317), a compressed **SceneKit** particle scene used by `GiftAvatarComponent`, not Lottie.

---

## C. Build checklist

**Concept A: Settings icon animates on return**
1. **Rows as upstream.** 52-pt rows; 30×30 icon at x 16, text at x 61; cards inset 16, radius 26 (§A1). The icon is static at rest: fill + Gradient (plus-lighter) + Backdrop (overlay) + white glyph, corner 8.
2. **Tap.** Highlight `#313135`/`#e5e5ea` on at touch-down, fading over 0.25 s on release. Record the row id (the `openSettings(section:)` analogue).
3. **Push.** Animate p from 0 to 1 over 0.5 s with `x(t) = 1 − (1 + 23.559t)e^(−23.559t)`.
   - Sub-page x = W·(1 − x), Settings and tab bar x = −0.3·W·x.
   - Dim black α 0.15·x over Settings, out to subX + 62.
   - Sub-page corners = 41.5 (device radius) during the move, 0 after.
4. **Sub-page.**
   - Bar SB + 60 with no fill, only the top edge fade.
   - 44 glass back circle at (16, SB + 10) with the 2-pt chevron.
   - Title semibold 17, centred at SB + 2 + (60 − h)/2.
   - Rows: 50-pt glass rows with the icon at x 14 and text at x 59 inside the card. Headers regular 13 at x 15, y 7, top 24/28.
   - Notifications and Privacy row lists as in §A6.
5. **Pop.**
   - **Back tap:** the mirror of the push (same spring).
   - **Swipe:** anywhere on the page, horizontal-dominant, `p = dx/W`. Release completes if v > 1000 or p > 0.2, in `clamp((1 − p)W/v, 0.05, 0.2)` s easeInOut; otherwise it cancels in 0.1 s.
6. **Trigger.** About 0.2 s into a button pop, or at the end of a completed swipe, play the remembered row's icon animation once, one icon at a time.
   - Keep it inside the 30-pt tile.
   - Skip it if the swipe was cancelled or reduced motion is on.
   - End on the exact static frame.

**Concept B: glassy, tilting gift tiles**
1. **Profile.** Header from `README.md`. Glass tab capsule h 40 at y 10 (`.fit`). The Gifts tab label is followed by 3 mini stickers (18 pt). The pane background is `blocksBackgroundColor`, and the grid starts 66 pt below the pane top.
2. **Grid.** 3 columns, gap 10, inset 16, square tiles `(W − 52)/3` (120.67 on 414). Tiles appear with scale 0.01→1 + fade over 0.25 s.
3. **Tile.**
   - Radius 16 (circular).
   - Regular: `#1c1c1d`/`#fff` with the sender avatar 20 at (5, 5).
   - Unique: radial inner→outer + 16 pattern icons per §B3, pattern colour @0.6 fading on a 190 × h/2 ellipse.
   - Sticker `floor(88h/116)`, centred, plays once on appear and again after scrolling back into view.
4. **Ribbon.** The 58×58 band image at (w − 56, −2) with the per-type gradient (§B3). Text white, rotated 45° at (w − 20, 20): semibold 9 "1 of 10K", SF Mono 10 "#1234", or green "sale" with an outline.
5. **Existing interactions to keep.**
   - Quick tap opens the gift sheet with no tile feedback: dim 0.4 over 0.3 s, sheet 0.4 s, 136-pt sticker at y 88 that plays once and replays on tap, paging between gifts.
   - Holding ≥ 0.12 s shrinks the tile to `(w − 15)/w` over 0.2 s, then opens the context preview.
6. **New tilt.** The proposal below borrows the wallet-card recipe (§B5).
   - **Touch tilt.** Perspective 650 and smoothing `1 − e^(−8dt)` toward targets from the finger offset, `rx = −dy/travel·maxPitch`, `ry = dx/travel·maxYaw`, with travel scaled by tile width (wallet: 240 pt per 361 pt of width).
   - **Small limits suit a 120-pt tile.** For example ≤ 8° yaw / 6° pitch, below the wallet's 17°/11.5°. These are design choices, not upstream values.
   - **Scale and release.** Scale to 1.01 while touched. On release decay with `e^(−4dt)`.
   - **Interplay with existing gestures.** A drag must not block the grid's vertical scroll. Cancel the tilt once the long-press preview opens.
7. **New glints.** Move a specular highlight with device tilt rather than rotating the tile, as the wallet card does (`surfaceTilt × 0.9`, light `(−0.5, 0.5, 1)`), plus an optional ≤ 2–3° whole-tile tilt.
   - **Event source.** Web: `DeviceOrientationEvent`, which on iOS needs `requestPermission()` from a user gesture over HTTPS. In Telegram Mini-App mode, `Telegram.WebApp.DeviceOrientation.start({refresh_rate})` instead (WebAppController.swift:1717-1735).
   - **Reference and smoothing.** Use the first reading as the reference and smooth over 0.1 s.
   - **Gating.** Pause off-screen and when reduced motion is set.
8. **Artwork.** From `gift-assets/`: gunzip the `.tgs` files for lottie-web. The colour stand-ins are Cake, Celebrate, Diamond, GramDiamond, StarsBuy, premium_gift. The box glyphs (anim_gift, TabGift) are mono and need a tint or recolouring. Keep the GPL notice and `SOURCES.txt` with any shipped copy.

---

## D. Notes
- **Prototype.** `prototype/src/settings/living-icons.js` already exists (Concept A work in progress). It was not touched.
- **Notification label.** The "Notifications and Sounds" row gets `.badge("!", destructive)` instead of a label when notification permission is denied (PSI:269). The sub-page then starts with a permission card (NAS:540-560).
- **Tile corners.** Upstream gift tiles use `cornerCurve = .circular`, while Settings icons use continuous corners. Match each separately on the web.
- **Measurements.** Layout numbers marked ≈ use TextNode line heights (17 → 20.3, 15 → 17.9, 13 → 15.5) and were not measured on screenshots.
- **Unverified Android detail.** The fork's Android figures (ribbon geometry, StarGiftSheet roller `rotateY(−30°·t)` at A:Stars/StarGiftSheet.java:1796, 1880-1918) were spot-checked where cited above, but not the roller.
