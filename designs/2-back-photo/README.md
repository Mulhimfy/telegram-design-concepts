# 2 · Back Photo

**Surprise your followers with a hidden photo — shown only when your profile photo is turned over.** Add a
back photo in Settings and your photo turns over by itself to show it; anyone who turns your photo over
(design 1's gesture) finds it. One photo, two sides.

- Videos: `renders/designs/2-back-after.mp4` (the design) and `2-back-before.mp4` (Telegram today) · Try it: <https://t.me/Tgdesignbot?start=back> (Settings → Add Back Photo)

## Today in Telegram
A profile has one current photo (plus the gallery of older ones, `personal_photo` and `fallback_photo`); the
photo has no reverse side.

## The design
- **Add Back Photo** — a new row under *Change Profile Photo* (NEW badge). It opens a photo picker (Telegram's
  media-picker grid in an iOS 26 sheet; the first tile is *None*). Pick a photo → the sheet closes and the
  avatar **turns over by itself** (0.75 s later, on the flip spring) to show its new back. The row becomes
  *Change Back Photo*.
- Without a back photo the reverse is the same photo, so nothing changes for people who don't use it.
- **Turning it**: drag past edge-on (or flick to spin) and the photo turns between front and back; the back
  lands like the front, flat in 0.2–0.45 s.
- **Changing it while the back shows**: the photo turns and the new back is put on as it passes edge-on, so a
  side never changes in view; choosing *None* turns it back to the photo.
- A side only ever changes while it faces away (`GlassCoin.turnBy`): no pops.
- Needs one new profile field (`back_photo`, like `personal_photo` / `fallback_photo`); until the server has it
  the native code stores the choice on the device (marked `TODO(server)`).

## Code
- **Web prototype**: `prototype/src/app.js` (`chooseBack`, `applyBack`, the pending swap at edge-on),
  `prototype/src/ui/glass-sheets.js` (`backPhotoSheet`), `prototype/src/coin/coin-physics.js` (`setBack`,
  `turnBy`), picker photos `prototype/assets/photos/pick-*.jpg` (Unsplash licence, no people).
- **Native (Telegram-iOS)**: `ios/patches/0002-back-photo.patch` (applies on top of 0001): the row, the picker
  through the avatar's own media picker and editor (round crop; a video gives its cover; the emoji avatar maker
  its picture), the on-device store, and `setGlassBackPhoto` wiring into the glass avatar
  (`GlassCoinAvatarNode.setBackPhoto(_:animated:)` in `ios/GlassCoinAvatar/`). Details: `ios/README.md`.

## Submission text
> **Back Photo — your profile photo gets a back side**
> Surprise your followers with a hidden photo, shown only when your profile photo is turned over. Add a back
> photo in Settings (new row) and your profile photo turns over by itself to show it. Anyone who
> turns your photo over sees the back; without one, the back is the same photo. Changing it while the back is
> showing turns the photo and swaps the side as it passes edge-on, so nothing ever pops. Needs one new profile
> field (`back_photo`). Code: a Telegram-iOS patch (row, picker, store) on top of the Glass Avatar module, plus
> the web prototype. Try it: t.me/Tgdesignbot?start=back
