# 5 · Glass Gifts

**On a profile's Gifts, every gift is a pane of glass with the gift floating inside.** Touch one and it leans
toward your finger while a burst of light runs across the glass; hold and slide, and every gift you cross
follows your finger; tilt the phone and the light moves across all of them. It works like hover: a tap still
opens the gift's info sheet, exactly as Telegram does today.

- Video: `renders/designs/5-gifts.mp4` · Try it: <https://t.me/Tgdesignbot?start=gifts> (a profile's Gifts tab)

## Today in Telegram
Gift tiles are flat: `style: .glass` only sets the corner radius (GiftItemComponent:466-480); the only motion
is the appear scale, a sticker that plays once and the long-press shrink. No gift UI uses CoreMotion — only the
TON wallet card tilts, with device-motion lighting (WalletCardComponent:868-936, 1386-1424).
(`research/telegram-ios/settings-icons-and-gifts.md` §B.)

## The design
- **Touch** (like hover; the tap is untouched): the tile leans toward the finger (≤ 9° yaw / 7° pitch), lifts a
  hair (×1.01), its gift, ribbon and badges float above the glass (14 / 18 / 10 pt), the shadow shifts away;
  a burst of light fragments runs across the glass and sparkles catch at its corners.
- **Hold and slide** (0.12 s, Telegram's context-gesture threshold, within 10 pt): every tile under the finger
  leans after it, with a selection haptic per tile; the pane doesn't scroll meanwhile. A plain vertical drag
  still scrolls.
- **Tilt the phone**: the light moves across every tile — a specular sheen, a faint prismatic streak and the lit
  edge slide over the glass — with only a hint of lean (≤ 2.5°). The first reading is the reference, smoothed
  over 0.1 s and slowly re-centred (~4 s), so a held pose turns neutral.
- **Release**: everything eases home.
- The motion is Telegram's own wallet card: angles follow their targets with 1 − e^(−8 dt), scale with
  1 − e^(−12 dt), targets decay e^(−4 dt) after release; device motion moves the light, not the card;
  perspective m34 = −1/650. Reduce Motion: no lean, light only.

## Code
- **Web prototype**: `prototype/src/profile/glass-gifts.js` (GlassTile, MotionSource),
  `prototype/src/profile/profile-page.js` (another user's profile on iOS 26 with the Gifts grid in Telegram's
  metrics, the touch handling), gift stickers `prototype/assets/gifts/` (Telegram's own animations, GPL).
- **Native (Telegram-iOS)**: module `ios/GlassGifts/` (the tile model, the glass layers, the motion source, the
  interaction) and `ios/patches/0005-glass-gifts.patch` (GiftItemComponent + PeerInfoGiftsPaneNode hooks).
  Details and verification: `ios/GlassGifts/README.md`.

## Submission text
> **Glass Gifts — every gift is a pane of glass**
> On a profile's Gifts, each tile becomes glass with the gift floating inside. Touch one and it leans toward
> your finger while light runs across it; hold and slide and every gift you cross follows; tilt the phone and the
> light moves across all of them. It behaves like hover: a tap still opens the gift's info, as today. The motion
> is Telegram's own TON wallet card (same follow rates, same perspective, device motion moving the light).
> Code: a Telegram-iOS module and a small GiftItemComponent / PeerInfoGiftsPaneNode patch, plus the web
> prototype. Try it: t.me/Tgdesignbot?start=gifts
