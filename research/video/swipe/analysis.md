# Telegram iOS chat-list swipe actions: reference footage, frame by frame

Measured 2026-10-12 from pixels unless marked **source**. `n` is the decode index of a 60 fps constant-frame-rate file, so `t = n/60`.
Frames in `frames/` are cropped to the phone screen. Crop x=0 is source x=184 (106) or x=189 (213), so
**pt = x_crop / 1.899** (106) or **/ 1.795** (213).

## 0. Status: the newest design (iOS 26, round 50-pt actions) has NO footage here
- The round design landed in Telegram-iOS on 2026-05-14 (`91eb779ae`). The animation rework followed on 2026-07-09 (`2247ce7aa`).
  It most likely first shipped in **12.8 (2026-06-09)**. It was never announced, so no promo, blog post, Tips post or changelog shows it.
- Sources tried:
  - telegram.org/blog MP4s: the 2019 archive clip is Android. The Oct 2025, Jan 2026, Jul 2026 and Aug 2026 iOS 26 promos show no row swipe.
  - Channels: TelegramTips, telegram, durov, designers, tginfo, tgbeta, TBetaLeak.
  - bugs.telegram.org: only low-res 24–30 fps clips, none filming the swipe.
  - Reddit: no swipe clip. Bluesky, cobalt and TikTok: blocked or empty.
  - **YouTube: "Sign in to confirm you're not a bot"**, both for yt-dlp (every player client) and in the VPS Chrome (`LOGIN_REQUIRED`). Invidious and Piped are down.
- **Next step:** a 60 fps iPhone screen recording (iOS 26, Telegram ≥ 12.8) covering a slow left swipe, a slow right swipe, one long swipe and one tap → `src/`, then rerun §6.
  Alternatively, sign YouTube in on the VPS Chrome via noVNC.

## 1. Clips (old design: rectangular full-height buttons)
| Clip | Source | Device / era | Format |
|---|---|---|---|
| `src/tips106-ios-mute-swipe-2021.mp4` | https://t.me/TelegramTips/106 (2021-01-11) | iOS Telegram 7.x, no folders. Screen 712 px = **375 pt** (X/XS/11 Pro/12 mini). **1.899 px/pt**. Row 144.25 px = 76.0 pt; open width 420 px = 3 × 74 pt | 1080², **60 fps CFR**, 16.0 s. iOS part at 8.45–10.6 s. **Lottie icons animate** |
| `src/tips213-ios-archive-swipe-2021.mp4` | https://t.me/TelegramTips/213 (2021-01-12) | iOS 7.x with folders. Screen 700 px = **390 pt** (iPhone 12). **1.795 px/pt**. Row 136.7 px = 76.1 pt; avatar 108 px = 60 pt | 1080², 60 fps CFR, 11.3 s. Long swipes A (0.4–1.7 s), B (2.8–4.1 s), C = Unarchive (9.0–10.2 s). **Icons static** |

- Both are promo edits: static zoom with a composited light-blue **touch ring**. The ring biases colour boundaries where it overlaps.
- The 213 gesture is synthetic: A, B and C have identical offsets, a constant 13.07 pt/frame = 784 pt/s.
- Method: content offset by NCC on the row timestamp (±0.5 pt); buttons by per-column median colour inside the row band; icons by white-pixel bounding box.
- Colours (video, approximate): Mute ≈ #F59D2D (theme #FF9500); Delete ≈ #FC3728 (#FF3B30); Archive ≈ #BEBCC4 (#BDBDC2).

## 2. tips106: partial swipe → open → tap Mute → close (t₀ = n534 = 8.900 s)
- **Touch down:** n522. The row starts moving 200 ms later.
- **Drag:** 10–15.3 pt/frame (peak 918 pt/s).
- **Slots during the drag:** all three appear at once. Delete and Archive then widen **ahead of the content edge**, and Mute is uncovered last.
  Slot widths and icons redraw at **40 Hz**: frame pairs 540/541, 543/544 and 546/547 repeat. The content updates every frame.
- **Icon pop:** all three trigger at n540–541, at reveal ≈ 0.38–0.45 of 222 pt:
  - Archive: 2.6×3.2 → peak 28.4×29.5 pt at +200 ms → settles at 25.8×24.7 pt at **+300 ms**.
  - Delete: peak 23.2×32.6 → settles at 17.9×27.9 pt at **+380 ms**.
  - Mute: peak 26.3×26.3 → settles at 23.2×23.7 pt at +380 ms.
  - The box and bin lids lift and drop back. The shipped Lottie files match: anim_archive keyframes 0–20, anim_delete and anim_mute 0–25, all at 60 fps.
- **Release:** remaining distance per frame 52.6 → 41.0 → 30.0 → 20.5 → 12.1 → 5.7 → 1.5 → 0: constant deceleration, **stopped in about 0.12 s, no overshoot**. Open offset −222.7 pt.
- **Open state:** 74 / 73.7 / 73.7 pt wide, full 76-pt row height, square corners. Icon centre 11.3 pt above the row centre, title below.
- **Tap Mute:** finger lifts at about n601, **close starts at n604**; the muted glyph and grey badge appear at n605–606.
- **Close:** n603→623 = **0.33 s**, no overshoot (easeInOut over 0.395 s: 3.2 pt rms — use the table). The content slides **over** the buttons.

Every frame: `data/tips106_frames.csv`.

## 3. tips213 A: long swipe → expand → archive (t₀ = n36 = 0.600 s)
- Constant 13.07 pt/frame drag. Fixed 67.4-pt buttons attached to the content edge (Delete appears at dx −78.6, Archive at −143.7).
- **Expand:** Archive grows over 15 frames = **0.25 s** to cover the row; its icon and title move to the left (icon 26.7×25.6 pt, centred 34.8 pt from the left).
- **Collapse:** n81→100 = 0.33 s; best fit easeOut(0,0,.58,1) over 0.34 s (0.71 pt rms). The next row slides up over the grey row.
- "Chat archived" toast rises at n94–99 (≈ 0.23 s after the collapse starts).

## 4. Row content (old design)
Slides rigidly — no fade, scale, blur or rounding; the separator moves with it; buttons beneath, full row height.

## 5. **source** (Telegram-iOS f1dd7a2, ItemListRevealOptionsNode.swift): the new design
See `research/telegram-ios/chat-list-swipe.md` — 50 pt circles, pop-in p = 1−(1−x)^2.7 over 20 pt, visual follower k 420 / c 40,
Lottie at progress ≥ 0.3 (start frames 3/5), overswipe stretch, arm at 100 pt, one 0.6 s overdamped spring.

## 6. Rerun on new footage
- `tools/video-analysis/swipe_track.py VIDEO OUT.json --n0 --n1 --nrest --sx0 --sx1 --y0 --y1 --scale --tpl x0,y0,x1,y1`
- Then `swipe_icon_track.py` and `swipe_fit_easing.py`.
- Contact sheets: `ffmpeg … select=between(n,a,b),crop=…,drawtext,tile`, as in `sheets/`.
