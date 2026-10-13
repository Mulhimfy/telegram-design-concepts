# Five Telegram iOS design concepts

Each concept runs for real in a pixel-accurate replica of Telegram iOS 13.0 (the iOS 26 design), has its
own demo video, and comes with ready-to-implement native code for Telegram-iOS (Swift, on Telegram's own
components, as a patch against Telegram-iOS `f1dd7a2`). Every number is traced to Telegram's source.

| # | Design | In one line | Video | Try it |
|---|---|---|---|---|
| 1 | [Glass Avatar](1-glass-avatar/) | Your photo turns into a sheet of glass under your finger; a glass colour lights the profile and your name | `renders/designs/1-glass.mp4` | [t.me/Tgdesignbot?start=glass](https://t.me/Tgdesignbot?start=glass) |
| 2 | [Back Photo](2-back-photo/) | Your profile photo gets a back side that anyone can turn it over to see | `renders/designs/2-back.mp4` | [t.me/Tgdesignbot?start=back](https://t.me/Tgdesignbot?start=back) |
| 3 | [Living Icons](3-living-icons/) | Come back from a Settings page and its icon comes alive, every part of it moving | `renders/designs/3-icons.mp4` | [t.me/Tgdesignbot?start=icons](https://t.me/Tgdesignbot?start=icons) |
| 4 | [Depth Swipe](4-depth-swipe/) | Swipe a chat and its name, message and photo move in 3D; to the left they roll over the screen's edge | `renders/designs/4-swipe.mp4` | [t.me/Tgdesignbot?start=swipe](https://t.me/Tgdesignbot?start=swipe) |
| 5 | [Glass Gifts](5-glass-gifts/) | Every gift is a pane of glass: it leans to your finger, light runs across it, tilting the phone moves the light | `renders/designs/5-gifts.mp4` | [t.me/Tgdesignbot?start=gifts](https://t.me/Tgdesignbot?start=gifts) |

## Try them

Open **[@Tgdesignbot](https://t.me/Tgdesignbot)** in Telegram and press Start: one button per design opens it as
a Mini App (Telegram's own haptics, your theme), ▶️ sends its demo video. The menu button opens the whole app.
The bot and the app are served by Cloudflare Pages (`tools/bot/`), so they keep working with no server of ours.
On a computer: <https://tgdesign-601.pages.dev/> (`?tab=chats` opens the chat list, `?tab=chats&open=alex` a profile with gifts).

## What is in this repository

- `prototype/` — the replica and the five designs (one web app; the files of each design are listed in its README).
- `ios/` — the native code: one module per design plus the patches that wire them into Telegram-iOS, verified by
  CI on a macOS runner (Metal shader compiled, every module typechecked for iOS against Telegram's APIs, the
  maths replayed against golden data recorded from the web prototype).
- `renders/designs/` — the demo videos (1080×1080, 60 fps, rendered frame-exactly from the prototype:
  `?composition=square&record=1&demo=<key>` + `tools/record.mjs`; the scripts are `prototype/src/scripts/*-demo.js`).
- `research/` — Telegram-iOS / Android source notes with file:line references, measurements.
