# Research

| Folder | What's in it |
|---|---|
| `source/` | Inputs: `IMG_6025.MP4` (the Telegram iOS designer demo from t.me/designers/266, 1080², 60 fps, 76 s) and `screenshots/user-01…09.jpg` (the user's own Telegram Settings tab: rest, scrolled states, expanded avatar). |
| `video/` | The designer demo analysed frame by frame: `analysis.md` (per-second log, transition timings fitted to Telegram's iOS 26 spring, bubble physics, glass look, recording craft: framing, zoom, touch indicator), contact sheets at 2/10/60 fps in `sheets/`, crops in `keyframes/`, raw measurements in `data/`. Scripts: `tools/video-analysis/`. |
| `telegram-ios/` | Design tokens and mechanics extracted from Telegram-iOS master (13.0, f1dd7a2): `README.md` with file:line references, `header-scroll.md` (the own-profile header under scrolling: collapse, banner snap-off, pull-to-expand, avatar hit-testing), machine-readable `tokens.json`, verbatim source copies in `src/`, and Telegram's own `Telegram-iOS-CLAUDE.md` (their guide for AI-assisted contributions). |
| `screenshots-analysis/` | Measurements of the user's screenshots (header crops, the crow pattern glyph traced from the profile). |
| `compare/` | Replica vs. the real app, side by side / split / difference (`settings-final-*`). |
| `refs/` | External references: Liquid Glass (Apple + web re-implementations), thick-glass shader maths, fluid-interface physics and haptics, Telegram 2025–26 context, the @designers channel's latest 60 posts (`designers-channel.md`), OSS replicas and licences, SF Pro licence. |

Key findings that shaped the build:
- The collapsed profile avatar only has a tap; a drag on it does nothing (the header keeps the touch,
  so it doesn't even scroll).
- Telegram already ships a draggable 3D coin (`PremiumCoinComponent`, 1 pt = 1°) and a real-refraction
  liquid-glass path (`LiquidGlassShapes`: MetalEngine + `CABackdropLayer` + `displacementMap`).
- Every short transition in the designer demo is Telegram's iOS 26 spring (k 555.027, c 47.118, ζ = 1).
- The user's phone is a 414×896 pt, no-Dynamic-Island device (status bar 48 pt): the header formulas
  reproduce their screenshots to the pixel.
