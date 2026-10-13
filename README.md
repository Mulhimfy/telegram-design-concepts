# Telegram iOS design concepts

Five concepts for Telegram iOS, built for Telegram's [@designers](https://t.me/designers/266) call ("working,
ready-to-implement code + a demo video"). Each runs for real in a pixel-accurate web replica of Telegram iOS
13.0 (the iOS 26 design), has its own demo video, and comes with native code for Telegram-iOS.

| # | Design | What it is | Docs |
|---|---|---|---|
| 1 | **Glass Avatar** | Your profile photo turns into a sheet of glass under your finger: it tilts any way, turns over, spins; a glass colour sends its light across the profile and over your name as it turns | [designs/1-glass-avatar](designs/1-glass-avatar/) |
| 2 | **Back Photo** | Your profile photo gets a back side; it turns over by itself to show it | [designs/2-back-photo](designs/2-back-photo/) |
| 3 | **Living Icons** | Come back from a Settings page and its icon comes alive, every part of it moving | [designs/3-living-icons](designs/3-living-icons/) |
| 4 | **Depth Swipe** | Swipe a chat and its name, message and photo move in 3D; to the left they roll over the screen's edge | [designs/4-depth-swipe](designs/4-depth-swipe/) |
| 5 | **Glass Gifts** | Every gift is a pane of glass: it leans to your finger, light runs across it, tilting the phone moves the light | [designs/5-glass-gifts](designs/5-glass-gifts/) |

Each design's README has the behaviour, the numbers and their sources, the files, and a ready-to-paste
submission text. Videos: `renders/designs/<n>-<key>.mp4` (1080×1080, 60 fps). One zip per design
(docs + video + native code + prototype): `tools/bundle-designs.sh`.

## Try them

- **In Telegram: [@Tgdesignbot](https://t.me/Tgdesignbot)** — Start, then a design opens as a Mini App (Telegram's
  haptics and colours); ▶️ sends its video. Direct links: `t.me/Tgdesignbot?start=glass|back|icons|swipe|gifts`.
  The bot and the app are on Cloudflare Pages (`tools/bot/`: the static prototype + a `_worker.js` webhook), so
  nothing depends on a server of ours. Redeploy with `tools/bot/deploy.sh`.
- **In a browser**: <https://tgdesign-601.pages.dev/> (Settings) · `?tab=chats` (chat list) ·
  `?tab=chats&open=alex` (a profile with gifts). On a phone it uses the real viewport and the system theme.
- **Locally**: `node tools/serve.mjs` → <http://127.0.0.1:8737/prototype/> (`?theme=light`, `?device=iphone16pro`,
  `?composition=square&record=1&demo=<key>` for the video stage).

## Repository

- **`prototype/`** — the replica and the designs (one web app): Settings with the own profile and the full menu
  (`src/ui/`), the glass avatar (`src/coin/`, `src/ui/light.js`, `src/ui/turn-light.js`), Settings pages and Living
  Icons (`src/settings/`), the Chats tab with Telegram's iOS 26 swipe actions and Depth Swipe (`src/chats/`), another
  user's profile with Glass Gifts (`src/profile/`), the video stage and demo scripts (`src/stage.js`, `src/demo.js`,
  `src/scripts/`).
- **`ios/`** — native code for Telegram-iOS, one module per design and the patches that wire them in (below).
- **`renders/designs/`** — the demo videos.
- **`research/`** — Telegram-iOS / Android source notes with file:line references (`research/telegram-ios/`),
  measurements of the designer reference video and of Telegram's own clips, the user's screenshots against the replica.
- **`tools/`** — `serve.mjs` (static/live server), `record.mjs` (frame-exact video recorder), `render-designs.sh`,
  `compose.sh`, `ui-check.mjs` (scripted UI checks), `golden*.mjs` (golden data for the Swift parity tests),
  `bot/` (the test bot), `phone/` (the live test build behind Caddy).

## Native implementation (Telegram-iOS `f1dd7a2`)

| Design | Module (drop-in) | Patch | CI (macOS runner) |
|---|---|---|---|
| Glass Avatar | `ios/GlassCoinAvatar/` → `submodules/TelegramUI/Components/PeerInfo/GlassCoinAvatar` (Swift + Metal on MetalEngine) | `ios/patches/0001-glass-avatar.patch` | `ios-verify.yml` |
| Back Photo | (uses the Glass Avatar module) | `ios/patches/0002-back-photo.patch` (on top of 0001) | `ios-verify.yml` |
| Living Icons | `ios/LivingSettingsIcons/` | `ios/patches/0003-living-icons.patch` | `ios-living-icons.yml` |
| Depth Swipe | `ios/DepthSwipe/` | `ios/patches/0004-depth-swipe.patch` | `ios-depth-swipe.yml` |
| Glass Gifts | `ios/GlassGifts/` | `ios/patches/0005-glass-gifts.patch` | `ios-glass-gifts.yml` |

Apply on a Telegram-iOS checkout at `f1dd7a2` with `git apply ios/patches/000N-….patch`. Every module is the
native twin of its prototype files (each Swift file names the web file it mirrors). CI compiles the Metal shader,
builds every module for the iOS Simulator with `-warnings-as-errors` against signature stubs copied from
Telegram's Display / AsyncDisplayKit / MetalEngine / SwiftSignalKit / ComponentFlow…, replays golden data recorded
from the web code (physics trajectories, icon rigs, the swipe rig, the gift tiles) through the Swift maths, and checks
that the patches apply. The hooks inside Telegram's own screens need the full Bazel build and are not compiled by
CI; they are kept small and follow the surrounding code. Details per module: `ios/README.md` (Glass Avatar, Back
Photo) and each module's README.

## Render the videos

```sh
node tools/serve.mjs &                 # the whole repo on :8737 (SF Pro from assets/fonts for Linux renders)
tools/render-designs.sh                # all five, or e.g. `tools/render-designs.sh swipe`
```

The page runs on a virtual clock: every frame is rendered at its exact time and the finger goes through the
same input paths as real touches, so the videos show the interaction model itself, not an animation. Slow
motion slows the page clock (`{ rate }` in a script), captions and the slow-motion badge are part of the stage,
and the phone itself can tilt (the gifts' gyroscope). `record.mjs --sheet DIR --every N` writes contact frames
instead of a video.

SF Pro is not included (Apple's licence forbids redistribution). On Apple devices the system font is used; to
render videos on Linux, `tools/fetch-sf-pro.sh` downloads Apple's DMG into `assets/fonts/` (ignored by git).

## Where the numbers come from

Every metric, colour, spring and curve comes from Telegram-iOS source (`research/telegram-ios/README.md`,
`tokens.json`, `header-scroll.md`, `chat-list-swipe.md`, `settings-icons-and-gifts.md`, verbatim copies in
`research/telegram-ios/src/`): the profile header (`PeerInfoHeaderNode`, `PeerInfoCoverComponent`), glass
(`GlassBackgroundComponent`, `TouchEffect`, `LiquidGlassShapes`), springs (`UIKitUtils.m`, `CAAnimationUtils.swift`),
haptics (`HapticFeedback`), the coin gesture (`PremiumCoinComponent`), the chat list and its swipe actions
(`ChatListItem`, `ItemListRevealOptionsNode`), navigation (`NavigationTransitionCoordinator`), Settings icons
(`PresentationResourcesSettings`), gifts (`GiftItemComponent`, `PeerInfoGiftsPaneNode`) and the TON wallet card's
tilt (`WalletCardComponent`).

## Credits & licence

- Telegram-iOS is GPL v2 or later (telegram.org/apps); the native modules, the patches, the ported formulas and
  the assets derived from Telegram (icons, gift and action animations) are under the same terms. Everything else
  here is released under GPL-2.0-or-later.
- Back-photo picker and chat photos: Unsplash License (`prototype/assets/photos/CREDITS.md`); none shows a person.
- SF Pro © Apple, not redistributed.
