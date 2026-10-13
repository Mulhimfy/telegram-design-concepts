# 4 · Depth Swipe

**Swipe a chat and its row comes off the surface in 3D.** The name becomes extruded type whose letters roll
back in a wave, the message leans, the photo becomes a coin. Swipe to the left and the screen's edge becomes
the rounded rim of the surface: the photo, then the name letter by letter, roll over it into the depth — and
roll back out as the row closes.

- Video: `renders/designs/4-swipe.mp4` (every swipe at full speed, then in slow motion)
- Try it: <https://t.me/Tgdesignbot?start=swipe> (Chats tab)

## Today in Telegram
The iOS 26 swipe actions (round 50 pt buttons, one 0.6 s spring) move the row's content as one flat piece
(ChatListItem + ItemListRevealOptionsNode, ported exactly: `research/telegram-ios/chat-list-swipe.md`).

## The design
- **Right swipe** (Read, Pin): the name is 3D type (7 extrusion layers, 6 pt deep, lit next to the face and
  darker toward the back); its letters roll back on their own axis (top away) in a wave that starts on the side
  the row moves toward (22 ms between letters), widths unchanged so the name stays one word; each message line
  leans as a rigid plate about its leading end, line 2 a beat after line 1; the photo becomes a 6 pt thick disc
  that tilts with the pull, its picture set deeper than the rim (parallax 7 pt) with a glint crossing it.
- **Left swipe** (Mute, Delete, Archive): nothing is cut by the screen edge. The edge is a rim (radius 34 pt,
  hinge 36 pt in): a piece whose flat centre goes d pt past the hinge is d/34 rad round it — it turns away on the
  rim (its thickness and extrusion showing, the light leaving its face), fades between 62° and 90°, and is behind
  the rim after. The disc reaches the rim after ~10 pt of swipe and takes ~55 pt more to go over; each letter the
  same as it gets there. The message text fades into the rim. Swiped back, everything rolls out of the edge the
  same way.
- **All the way** (the full-swipe haptic): the letters spin once, reel by reel (0.56 s, 30 ms stagger), and the
  disc flips like a coin.
- **Speed**: the lean comes from the row's velocity (`max · tanh(|v| / 620 pt/s)`) plus a hold "tension" from how
  far the finger has pulled (60 pt for most of it); springs answer in 0.17–0.22 s, so the first 20–30 pt of a
  swipe already show it. Flicks lean hard, slow pulls lean gently.
- **Every move**: finger, release spring, a tap closing the row, an action closing it.
- **At rest**: everything rolls back flat with one soft overshoot and the flat text takes over again (crisp,
  nothing 3D left). Reduce Motion: off.

## Code
- **Web prototype**: `prototype/src/chats/depth.js` (the rig), `prototype/src/chats/chat-list.js` (the chat list
  and swipe actions ported from Telegram-iOS, driving the rig), `prototype/src/chats/reveal-options.js` (the
  round actions and their Lottie icons), `prototype/src/chats/chats-page.js`.
- **Native (Telegram-iOS)**: module `ios/DepthSwipe/` (the rig maths + a CoreAnimation renderer: per-glyph layers
  from CoreText runs, line snapshots, the avatar disc) and `ios/patches/0004-depth-swipe.patch` (ChatListItemNode
  feeds it the reveal offset, velocity and pull, and the full-swipe haptic). Details and verification:
  `ios/DepthSwipe/README.md`.

## Submission text
> **Depth Swipe — chats move in 3D as you swipe**
> Swipe a chat and its row comes off the surface: the name becomes 3D type whose letters roll back in a wave,
> the message lines lean, the photo becomes a coin with a glint. Swipe left and the screen's edge becomes the
> rounded rim of the surface — the photo and then the name roll over it letter by letter, and roll back out as
> the row closes. Swipe all the way and the letters spin, the photo flips. It follows the finger's speed, runs
> on every move of the row, and leaves the flat row untouched at rest. Built on Telegram's own iOS 26 swipe
> actions (ported exactly). Code: a Telegram-iOS module and a ChatListItemNode patch, plus the web prototype.
> Try it: t.me/Tgdesignbot?start=swipe
