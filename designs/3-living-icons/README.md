# 3 · Living Icons

**Come back from a Settings page and its icon tells you where you were: it comes alive, every part of it
moving.** The padlock's shackle springs open and slams shut, the bell rings while its clapper swings, the
battery's charge jolts… then it is the same still icon again.

- Video: `renders/designs/3-icons.mp4` · Try it: <https://t.me/Tgdesignbot?start=icons> (Settings → open any row, come back)

## Today in Telegram
Every Settings icon is a static, pre-rendered 30×30 image in its coloured tile (PresentationResourcesSettings
:120-133; PeerInfoScreenDisclosureItem:99-101, 220-243). Tapping a row only flashes its highlight; coming back
never touches the rows (PeerInfoScreen:7076-7110). Telegram already animates icons elsewhere (tab-bar icons
play once when selected, the profile header buttons play once on tap) — never in Settings.
(`research/telegram-ios/settings-icons-and-gifts.md` §A.)

## The design
- **When**: as you come back to Settings from a row's page — ~0.2 s into a back-button pop (the page has nearly
  landed: the iOS 26 nav spring is at 95 %), or when a swipe-back completes. One icon, once; nothing runs at rest.
- **How**: every icon is Telegram's own artwork (the glyphs of Telegram-iOS `f1dd7a2`, same tiles), cut along its
  own sub-shapes into parts (where the file merges them, rebuilt part by part so it is pixel-identical at rest;
  cut-outs move inside masks). Each part has its
  own small physics (damped rings, springs with overshoot, drops with bounces), the tile pops on a spring
  (0.88 → 1) and a sheen crosses it. ~1–1.2 s per icon; it ends exactly on the static icon.
- **Every row**:

| Row | Motion |
|---|---|
| Notifications and Sounds | the bell rings, its clapper swings behind it, the badge swells; sound waves |
| Privacy and Security | the lock hops; its shackle springs up, swings open on its long leg, swings back and slams shut — a click (body squashes) and a glint |
| Data and Storage | the three storage disks hop one after another and land with a squash |
| Power Saving | raised, the battery strikes; its charge jolts out of place and snaps back (twice) |
| Appearance | a brush stroke: wind up, paint, settle — the dial swings, its filled half trailing inside the ring; a stroke of paint under it |
| Language | the globe turns, its meridians sweeping round, and settles back into Telegram's banded globe |
| Saved Messages | the bookmark lifts and drops in with bounces; its ribbon end flaps as it lands |
| Recent Calls | the handset buzzes; earpiece and mouthpiece rattle against each other |
| Devices | the laptop's lid shuts and springs open; the phone hops beside it |
| Chat Folders | the folder's flap swings open and falls back with a bounce, a page peeking out |
| My Profile | the person ducks inside the ring and pops back up, the head a beat later, then nods |
| Proxy | the two arrows run through the shield, out one side and back in from the other |
| Money | the gem turns and the sparkle inside it flares |
| Telegram Premium | the star spins in 3D while its five rounded arms fly out from its core and snap back |
| My Stars | the star turns a full circle inside its disc, which gives under it |
| Telegram Business | at the top of a hop the shop's awning pops open a crack and snaps shut as it lands |
| Send a Gift | the lid and its bow lift off the box and fall back, the bow wobbling; confetti |
| Ask a Question | the bubble lands with a jelly wobble; its own three dots bounce in turn, typing |
| Telegram FAQ | the question mark is rubbed out and writes itself again, then wobbles; its dot hops back in |
| Telegram Features | the lamp swings, its bulb swells as it lights and its base screws in; the glass catches a highlight, rays shine |
| Change Emoji Status | the smile widens with a wink, the pencil scribbles |
| Change Profile Photo | the lens zooms, the flash fires, the plus spins in |
| Change Profile Color | the photo pops, the name bar slides out, the sparkles twinkle in turn |

- Reduce Motion: off (the icon stays still).

## Code
- **Web prototype**: `prototype/src/settings/living-icons.js` (artwork cut into parts, every rig, the player),
  `prototype/src/settings/nav.js` (iOS 26 push/pop, when the icon plays), `prototype/src/settings/subpages.js`,
  icons `prototype/assets/icons/*.svg` (Telegram's Settings/Menu artwork).
- **Native (Telegram-iOS)**: module `ios/LivingSettingsIcons/` (vector parts as CAShapeLayers, every rig ported,
  played on Display's display link only while an icon moves) and `ios/patches/0003-living-icons.patch`
  (PeerInfoScreen remembers the row that opened a page and plays its icon on return). Details and
  verification: `ios/LivingSettingsIcons/README.md`.

## Submission text
> **Living Icons — Settings icons come alive**
> Today every Settings icon is a still image. Here, when you come back from a row's page, its icon tells you
> where you were: Telegram's own artwork, cut into its parts, each moving with its own little physics — the
> padlock's shackle springs open and slams shut, the bell rings and its clapper swings, the battery's charge
> jolts, the Premium star's arms fly out as it spins, the shop's awning pops open… 23 icons, ~1 s each,
> once, and then the same still icon again. Nothing runs at rest. Code: a Telegram-iOS module (CAShapeLayer
> parts, every rig ported) and a small PeerInfoScreen patch, plus the web prototype. Try it:
> t.me/Tgdesignbot?start=icons
