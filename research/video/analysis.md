# IMG_6025 — frame-accurate analysis of the Telegram iOS designer demo (t.me/designers/266)

Source: `research/source/IMG_6025.MP4` — HEVC 1080×1080, 60 fps CFR, 75.95 s, 4557 frames; AAC stereo (silent until 28.6 s, music to 70.3 s). Method: ffmpeg → numpy pipelines (`tools/video-analysis/*.py`); every frame of each transition inspected on 60 fps sheets; pt values use **1.727 canvas-px/pt at base framing** (402-pt device, iPhone 16/17 Pro class); times are video seconds. Files: `sheets/s60-*`, `sheets/s10-*`, `sheets/plot-*.png`, `keyframes/crop-*.jpg`, `data/`.

**Feature demoed:** collectible gifts in *liquid-glass bubbles* orbiting the avatar. They are born from the avatar, drift and collide, and bend the UI behind them. Grab one and it grows about 2.5×, lifts above the finger and refracts what is under it; let go and it is thrown back. Horizontal swipes under the avatar spin the orbit. Tapping the profile-music pill plays *Stayin' Alive* and switches to a dark "party" mode: bubbles glow, nearby glass rims pick up their colour, the glow pulses each beat, and the profile colour auto-cycles about every 2.6 s.

## 1. Per-second log
"TG-26 spring" means Telegram's iOS-26 spring: mass 1, stiffness 555.027, damping 47.118 (ω 23.56 rad/s, ζ 1.0), from `UIKitRuntimeUtils/UIKitUtils.m make26SpringAnimationImpl`.

| s | On screen | Finger | Camera |
|---|---|---|---|
|0|Chat list, light, iOS 26 glass chrome (Edit capsule, "Chats ★", story+ and compose circles, search, rows Alicia/John(1)/Study Group/Thomas/Jessica/Telegram). Backdrop blue diagonal.|—|base 1.0×|
|1|Alicia row highlight ~1.45|tap row|base|
|2|1.50–1.80 push into chat (slide-in, list parallax). Green doodle wallpaper; glass back circle, title capsule "Alicia Brown / last seen just now", avatar right.|—|base|
|3|2.85–3.13 title pressed; **3.13–3.45 morph open**: capsule inflates into a glass blob, then a white card grows to full screen (card edge = TG-26, rms 0.014). Avatar flies from the header to the centre while scaling up; content fades in over the last ~40 %.|press title|base|
|4|Profile light: 121-pt avatar, 28-pt semibold name + gift emoji status, status line, music capsule, 4 round glass actions, info card, back circle + Edit capsule.|—|base|
|5|5.10–5.33 back pressed; **5.35–5.68 reverse morph** (card shrinks into the capsule, S-curve).|tap back|base|
|6|Chat static|—|base|
|7|6.95–7.03 header avatar pressed; **7.06–7.47 morph into profile with expanded avatar**: two stages, photo becomes a rounded rect, then full-bleed.|tap avatar|base|
|8|Expanded: full-bleed photo dissolving into the page (progressive blur), white text over the photo, dark-tinted glass buttons.|—|base|
|9|9.0–9.35 finger on the left edge; **9.35–10.07 interactive swipe-back**: the profile becomes a rounded card at ~0.85× and tracks the finger 1:1.|edge-swipe|base|
|10|**10.07–10.45 release**: card flies into the header avatar (~0.35 s).|lift|base|
|11|11.27–11.33 title pressed; **11.35–11.60 morph open**|tap|base|
|12|Profile static|—|base|
|13|**12.93–13.40 edit dissolve** to a second take: purple profile with cat pattern, "◀ Feed"; backdrop blue→purple to 13.77. **13.6–14.1 bubbles born** from the avatar rim (pop to 45–62 pt in ~0.2–0.25 s, 2 % overshoot).|—|base|
|14|3–4 bubbles drift; in front of the avatar and pattern, behind the title text.|—|base|
|15|15.0–15.9 sweep R→L under the avatar; bubbles swirl.|sweep|base|
|16|Orbit spins, then calms (~30–65 pt/s).|—|base|
|17|**17.08–18.05 zoom to 1.64×** (≈1 s, ease-in-out). 17.25 touches the frog bubble; **17.50–17.75 inflates 67→165 pt and lifts above the finger**.|grab|zoom in|
|18|Dragged down over the title, pill and mute button; egg shape up to 1.37, refracting what is beneath.|drag|1.64× follow-pan|
|19|Loop 18.7–19.8; bubble trails 70–100 ms behind with squash/stretch.|loop|1.64×|
|20|±25 pt wiggles at 2.5 Hz; bubble moves only ±10 pt.|wiggle|1.64×|
|21|21.3–21.6 fast move down; **21.63 release → 21.65–21.80 collapse (0.15 s) and fly back (~0.2 s)**.|flick/lift|1.64×|
|22|22.03–23.25 zoom out (~1.2 s)|—|zoom out|
|23|Drift|—|base|
|24|24.0–24.3 overscroll; bubbles vanish as the avatar starts growing; **24.30–24.55 expand to full-bleed** (TG-26, rms 0.031). Ambient backdrop takes the photo's colours.|pull down|base|
|25|Expanded state|—|base|
|26|**26.48–26.72 collapse** (scroll-driven); **26.73–27.0 bubbles re-emerge** (50–70 ms pop, 2–4 % overshoot, staggered, ease-out glide).|scroll up|base|
|27|Drift; finger on the music pill 27.6–28.3|pill|base|
|28|Pill pressed 28.1–28.2; music starts 28.6; **28.4–29.2 crossfade to dark appearance**; bubbles become emissive.|tap pill|base|
|29|**29.13–30.05 zoom in**; 29.6 grabs the pink bubble (instant ×3, ~195 pt).|grab|zoom in|
|30|Dragged down; hot-pink tint, "Stayin' Alive" bent on an arc inside, unicorn particles.|drag|1.64× follow|
|31|Circling, aspect 1.3–1.4|circles|1.64×|
|32|Circling, then 32.6–32.85 move down|circles|1.64×|
|33|**32.87 release → collapse 0.15 s, fly back**; 33.45–34.42 zoom out|lift|zoom out|
|34|Dark purple, neon bubbles|—|base|
|35|**35.07–35.85 auto colour change** purple→navy|—|base|
|36|Navy, 5–7 neon bubbles, beat pulse|—|base|
|37|37.60–38.32 navy→teal|—|base|
|38|Teal|—|base|
|39|Teal, drift ~45 pt/s|—|base|
|40|40.23–41.20 teal→green|—|base|
|41|Green|—|base|
|42|Green, collisions at the avatar rim|—|base|
|43|42.78–43.68 green→olive|—|base|
|44|Olive; strong light spill on the avatar rim and Edit/back buttons|—|base|
|45|45.45–46.30 olive→graphite|—|base|
|46|46.47–47.37 zoom in; 46.9 grabs the gold helmet bubble (~0.5 s inflate)|grab|zoom in|
|47|Dragged onto the action row|drag|1.64× follow|
|48|Call/search buttons get golden rim light on the side facing the bubble; mute button seen magnified behind it.|circles|1.64×|
|49|Circling|circles|1.64×|
|50|**50.17 release → collapse 0.13 s**; 50.75–51.75 zoom out to 1.33×|lift|→1.33×|
|51|Medium framing, neon orbit|—|1.33×|
|52|52.0–53.4 sweep R→L along the name line; **orbit spins clockwise** ≤140 °/s.|sweep|1.33×|
|53|Decays to 5–15 °/s|—|1.33×|
|54|54.1–55.1 sweep; ~200 °/s|sweep|1.33×|
|55|Decay; bubbles bunch lower-left|—|1.33×|
|56|56.1–56.8 fastest sweep (~400 pt/s); 250–360 °/s|sweep|1.33×|
|57|Decay with collisions|—|1.33×|
|58|58.6–59.78 zoom out|—|zoom out|
|59|59.18–60.35 graphite→crimson|—|base|
|60|Crimson|—|base|
|61|61.98–62.98 crimson→blue|—|base|
|62|Blue|—|base|
|63|Blue|—|base|
|64|64.57–65.55 blue→violet|—|base|
|65|Violet, 2–3 bubbles|—|base|
|66|Violet|—|base|
|67|Violet|—|base|
|68|Violet|—|base|
|69|~69.5 taps the pill; music stops 70.3; 69.60–70.52 back to light purple, bubbles back to tinted glass.|tap pill|base|
|70|Light purple, 2 bubbles|—|base|
|71|71.4 edge; **71.75–72.48 interactive swipe-back**; backdrop purple→blue|edge-swipe|base|
|72|**72.50–72.73 card morphs into the chat title capsule**|lift|base|
|73|Chat; 73.85–73.92 back pressed|tap back|base|
|74|**73.91–74.20 pop to chat list** (parallax, nav crossfade, Edit appears 74.2)|—|base|
|75|Chat list to the end (75.95)|—|base|

## 2. Transition timings

| Transition | Start → 98 % | Duration | Fit | rms vs TG-26 |
|---|---|---|---|---|
|Chat→profile morph|3.127→3.383|0.27 s|ω 22.6–25.6, ζ 1.0–1.1|0.014|
|Profile→chat|5.358→5.683|0.33 s|ζ 0.75, ω 11.6, 3 % overshoot|0.084|
|Open with expanded avatar|7.06→7.40 (settled 7.47)|0.35–0.40 s|ω 11.8–14.4, ζ 0.85–1.0|0.090|
|Swipe-back tracking|9.35→10.07|finger-driven|card ≈0.85×, 1:1 x tracking|—|
|Swipe-back release|10.09→10.38 (settled 10.45)|0.30–0.35 s|ω 13–15, ζ 0.85–1.0|0.082|
|Second morph open|11.33→~11.60|0.27 s|same as first|—|
|Edit dissolve|12.93→13.40|0.45 s|linear|—|
|Pull-to-expand|24.298→24.55|0.26 s|ω 22.4–25.6|0.031|
|Collapse (scroll-driven)|26.49→26.72|0.23 s|ω 16, ζ 0.73|0.038|
|Bubble pop-in|13.85→14.08; 26.86→26.93|0.07–0.25 s|2–4 % overshoot|—|
|Light→dark (music)|28.4→29.2|0.8 s|linear|—|
|Colour cycle ×9|e.g. 35.07→35.85|0.72–1.17 s|≈linear; period 2.6 s ≈ 4.5 beats|—|
|Release→chat title capsule|72.50→72.70|0.2 s|fast ease-out|—|
|Pop to chat list|73.91→74.18|0.28 s|over-damped (fast start, long tail)|0.029|

The short transitions are the TG-26 spring, not a bouncy one. The longer moves have ζ≈0.75–0.85 (about UIKit response 0.45–0.5, damping 0.85). Overshoot is never more than about 3 %.

## 3. Bubble physics
- **Idle size:** about 44–67 pt (glowing core in neon mode 32–82 pt, median 49 pt); soft jelly ovals.
- **Held size:** frog 164 pt (183×148), pink ~195 pt (221×169), gold ~155 pt (177×138), about 2.5–3× idle. Inflate takes 0.15–0.5 s.
- **Grab offset:** centre at (−38, −112) pt from the touch (|o| 119 pt, sd 13/10 pt). The bubble floats above-left of the finger, like a loupe.
- **Following:** velocity lag 67 ms in x and 100 ms in y. Spring follower fit: ω≈23.6 (= TG-26 stiffness 555), ζ 1.2–1.5, rms 2.5–4.3 pt (pure TG-26 gives rms 6 pt). Gains x 0.7, y 0.9: a heavier, slightly tethered body.
- **Shape:** aspect 1.09–1.37 (mean 1.24); correlates with distance to the finger (r 0.58), not speed (r 0.10). Long axis points toward the finger (mean deviation 27°); egg-shaped, wider toward the finger; fast lateral moves momentarily make it rounder (damped squash/stretch).
- **Release:** shrinks back in 0.13–0.15 s (no undershoot) and returns to its slot in 0.2–0.25 s.
- **Orbit:** 70–125 pt from the avatar centre (avatar radius ~60 pt); drift median 45 pt/s (p25 30, p75 66, p95 108). Soft collisions; may overlap the avatar rim by 20–30 % of the bubble radius.
- **Swipe spin:** clockwise up to 140→200→250–360 °/s for sweeps of 240–400 pt/s; decays to under 15 °/s within 0.8–1.0 s.
- **Avatar expand/collapse:** bubbles hide within 2 frames of expand; re-emerge 0.15–0.3 s after collapse, staggered 50–100 ms.
- **Beat:** brightness repeats every 0.567–0.583 s, matching the 0.579 s beat. Rises 50–100 ms after each beat, fades over ~350 ms, about 5.5 % swing (14/255 luma).

## 4. Glass look
- **Refraction:** Telegram's LiquidGlass displacement approach. The centre acts as a thin lens (1.0–1.15×, ~7 pt upward shift). An edge band of 15–20 % of the radius folds and mirrors content: outside text shows as a ghost at the top edge, "Stayin' Alive" bends on an arc, "mute" appears near the bottom edge, and the button behind shows as a ring at ~1.2×.
- **Tint (light mode):** gift colour at ~50–60 %, denser toward the rim (frog ≈#5F5ADC, pink ≈#F04CC4, gold ≈#F5B03C). Content inside drops to 40–60 % contrast.
- **Tint (dark mode):** emissive, cores clip to full brightness.
- **Rim:** 1–2 pt bright edge plus a 4–6 pt denser inner band; a faint highlight crescent upper-left; no hard specular dot.
- **Inside:** the animated sticker (~45–55 % of the bubble width, not refracted). The gift's pattern symbols float as ~50 % white particles along the inner rim.
- **Glow:** additive blur of the bubble colour, fading to 1/e about 30 pt past the edge and reaching 2.5–3× the bubble radius.
- **Light spill:** nearby glass rims tint on the side facing each bubble (buttons, Edit/back, music pill, avatar rim).
- **Avatar:** in the bubbles take it has a ~2 pt glass rim that reflects bubble colours; it is a flat photo in the first take.
- **Shadow:** minimal.
- **Layering:** pattern < avatar < idle bubbles < text < nav glass; a held bubble sits above everything.
- **Backdrop:** a darkened (×0.55–0.7), huge blur of the screen.

## 5. Demo-video craft
- **Format:** 1080×1080, 60 fps, HEVC ~3 Mb/s, AAC 144 kb/s.
- **Phone mockup:** frame x 171–909, top y 74; bezel 13 px. Screen x 193–886 (694 px = 402 pt), top y 97, corner radius ≈57 px. Island pill 163×63 px at (541, 153). Status bar 09:41, charging battery. The bottom of the phone is cropped (~65 % visible).
- **Camera:** zoom in 1.0→1.64× in ≈1.0 s, ease-in-out (0.75×/s in the middle); zoom out over 1.0–1.2 s; 1.33× centred medium shot; follow-cam pans ±30–60 px lagging 0.1–0.2 s; about 40 % of the runtime is zoomed.
- **Touch indicator:** part of the recording, so it scales with zoom. Ø 56 px (≈32 pt); fill black ~30 %; ring 2 px white ~80 %; no ripple.
- **Story:** 0–12.9 real navigation; 12.9–28.4 the feature in light mode; 28.4–70.3 music party mode with 2 zoomed drags and spins; 70.3–76 bookend back to the chat list. A beat every 2–4 s, no captions, one hidden dissolve.

## 6. UI metrics (light profile, designer's unreleased layout)
- **Avatar:** Ø 121 pt, top 75 pt (centre y 135.5).
- **Nav buttons:** 44 pt back circle; Edit 62×44 pt; insets 16/15 pt; top 64 pt.
- **Text:** name 28 pt semibold (cap height 19.7 pt); status ≈17 pt.
- **Music capsule:** 180×29.5 pt at y 278 pt.
- **Action circles:** 54–56 pt, labels centred at y 384 pt.
- **Info card:** inset 16 pt, width 370 pt, top 417 pt.
