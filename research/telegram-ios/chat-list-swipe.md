# Chat list rows and swipe actions (Chats tab)

How Telegram-iOS lays out a chat-list row and animates its swipe actions — the spec for a web
rebuild of the Chats tab. Upstream `f1dd7a2` (13.0, iOS 26 design). Every number carries file:line.

Files: **E** `submodules/ItemListUI/Sources/Items/ItemListEditableItem.swift` (gesture, offset,
springs), **R** `submodules/ItemListUI/Sources/ItemListRevealOptionsNode.swift` (the action
buttons), **C** `submodules/ChatListUI/Sources/Node/ChatListItem.swift` (the row), **N**
`submodules/ChatListUI/Sources/Node/ChatListNode.swift`, **CC** `submodules/ChatListUI/Sources/ChatListController.swift`,
**TN** `submodules/Display/Source/TextNode.swift`, **CA** `submodules/Display/Source/CAAnimationUtils.swift`,
**LV** `submodules/Display/Source/ListView.swift`, **Dk**/**Dy**
`submodules/TelegramPresentationData/Sources/DefaultDark|DayPresentationTheme.swift`, **MAN**
`submodules/ManagedAnimationNode/Sources/ManagedAnimationNode.swift`.

Conventions: portrait iPhone, `params.leftInset = rightInset = 0`, default text size (`.regular`,
base 17). `W` = screen width, `H` = row height (76), `offset` = `revealOffset` (< 0: content moved
left, right-side actions; > 0: left-side actions), `d = |offset|`, `k` = action slot counted from
the screen edge (0 = outermost = "primary"). `px` = 1/screen scale. `floor_px(x)` =
`floor(x·scale)/scale`.

## 0. The look in one paragraph

Dragging a row turns it into a **rounded card** (corner 26, the highlight colour) that follows the
finger 1:1 — no rubber band (E:391-409). The avatar and text move with it; nothing scales or fades
(C:5604-5612). The strip uncovered behind the card shows the plain list background with
**fixed-position 50 pt circles** and an 11 pt label under each (R:180-189). Each circle stays
invisible until about 40 of its 50 pt are uncovered, then pops in over the next 20 pt of drag:
scale 0.3→1 and alpha 0→1, eased (R:224-227, 495-505). Its Lottie icon plays once (R:550-556).
Dragging past the full width stretches the outermost action into a capsule. The other circles ride
along with the card edge and dim to 70 %. Past 100 pt of over-swipe the capsule "arms" with a
medium haptic, and releasing then runs that action (R:822-856, E:444-447).

---

## 1. Gesture and motion (E, R)

### 1.1 Recognizer — `ItemListRevealOptionsGestureRecognizer` (E:6-59)
- `UIPanGestureRecognizer`, `maximumNumberOfTouches = 1` (E:20), also trackpad scroll (E:16-18).
- Until validated, all `touchesMoved` are swallowed (E:54-57). `t` = translation from the touch-down point:
  - **fail** if `!allowAnyDirection && t.x > 0`: a rightward move on a row with no left actions that is closed (E:45-46);
  - **fail** if `|t.y| > 4 && |t.y| > 2.5·|t.x|` (vertical, so the list scrolls) (E:47-48);
  - **validate** if `|t.x| > 4 && 2.5·|t.y| < |t.x|` (E:49-50). In between, it keeps waiting.
- `allowAnyDirection = !left.isEmpty || offset ≠ 0` (E:317, 628-633). Ordinary root-list rows have
  left actions, so both directions work there. The Archive folder, communities and the Archived
  Chats row have none, so they only swipe left (§2.2).
- Only one recognizer runs at a time (E:339-345). The folder pager's pan must wait for it to fail
  (`ChatListControllerNode.swift:594-602`), so a horizontal drag on a row always opens actions.
- `.began`: if actions are already open and the touch starts on the action strip
  (`x < leftWidth`, or `x > W − rightWidth`), the drag is cancelled. Taps on the buttons still work
  (E:369-384). Otherwise `initialOffset = offset` (E:375-389).

### 1.2 Translation → offset (E:391-412)
```
x = t.x + initialOffset
if left.isEmpty: x = min(0, x)          // E:394-396 — the only clamp; no resistance, no max
offset = x                               // applied .immediate every move (E:409)
```
The action node for a side is created the first time `x` crosses 0 toward it (E:397-405). It is
removed when the offset returns to 0 or crosses to the other side (E:589-596, 613-620). A drag can
pass from open-right through 0 into the left actions in one gesture.

### 1.3 Release (E:413-495)
`R_side` = width of that side's strip (§2.1); `v` = `velocity.x` in pt/s.

| | slow (`|v| < 100`) | fast |
|---|---|---|
| right strip | open if `initialOffset == 0 && offset < 0` (**any** distance from closed) or `offset < −R` | open iff `v < 0` |
| left strip | open if `initialOffset == 0 && offset > 0` or `offset > R` | open iff `v > 0` |
(E:427-441, 462-476)

- If it would open **and** the primary action is armed (`isDisplayingExtendedAction`, R:946-948), the
  row does not snap. It fires `right.last` / `left.first` via `revealOptionSelected(_, animated: true)`
  (E:444-452, 479-487), and that action drives the motion (§1.7).
- Otherwise it animates to `±R` (open) or 0 (closed) with the reveal spring (E:448, 483). Closing also
  reports `revealOptionsInteractivelyClosed` (E:454-456, 489-491).
- The gesture velocity is **not** passed on: `initialVelocity: 0.0` everywhere (E:353, 448, 483, 667, 689).

### 1.4 Springs and durations
| use | curve | ref |
|---|---|---|
| open/close on release, tap-to-close, programmatic close, full-swipe fill | `.animated(duration: 0.6, curve: .customSpring(mass: 2, stiffness: 200, damping: 100, initialVelocity: 0))` | E:353, 358-360, 448, 483, 667, 689 |
| how CA runs it | `CASpringAnimation` m 2, k 200, c 100; `duration = settlingDuration`; `speed = settlingDuration / 0.6`, so the whole settle is squeezed into 0.6 s | CA:73-116, ContainedViewLayoutTransition.swift:49, 87-88 |
| visual reveal follower (drives the buttons' alpha/scale while dragging) | per-frame spring, k 420, c 40, m 1, semi-implicit Euler, `dt ≤ 0.05`; never above the target; snaps when `|Δ| ≤ 0.25` and `|v| ≤ 12` | R:102-111, 756-812 |
| icon/label glide when the primary arms or disarms | exponential, `p = 1 − e^(−18·dt)`, snaps at ≤ 0.5 pt | R:87-88, 389-439 |
| actions cleared while open | `.animated(0.3, .spring)` = CABasicAnimation cubic-bezier(0.38, 0.70, 0.125, 1.0) | E:293, 305; CA:174-186 |
| row relayout (item updates) | `.animated(0.4, .spring)`, same bezier | C:4117-4122 |
| row removed from the list (archive/delete) | height → 0 over 0.4 s, list "system" curve (iOS 26 spring m1 k555.027 c47.118) | LV:7, 2528-2545; ListViewAnimation.swift:91-110 |

The reveal spring is overdamped: ω₀ = 10 rad/s, ζ = 2.5, roots −2.087 / −47.913. With v₀ = 0:
`x(τ) = 1 − 1.0455·e^(−2.087τ) + 0.0455·e^(−47.913τ)`. CA's `settlingDuration` threshold is not
public. Calibrate it on Telegram's own constant: the iOS 26 spring (k 555.027, c 47.118) settles in
exactly the hard-coded **0.3832 s** (CA:120) at |1 − x| = 0.0012. That threshold gives the reveal
spring `settlingDuration` ≈ **3.244 s**, so `speed` = 5.406. Squeezed into 0.6 s, with `t` in
seconds:

`progress(t) = 1 − 1.0455·e^(−11.28·t) + 0.0455·e^(−259.0·t)`, snap to 1 at t = 0.6.

Samples (t/0.6 → value): .05 → .255, .10 → .469, .15 → .621, .20 → .730, .25 → .808, .30 → .863,
.40 → .930, .50 → .965, .70 → .991, 1 → .999. It reaches 50 % at 65 ms, 90 % at 208 ms and 99 % at
412 ms: a fast exponential ease-out with no overshoot. (Computed numerically. With ε = 0.001 the
exponent is 11.58; with 0.01, 7.8 — the shape is the same, only the tail length changes.)

Visual follower step response, 0 → 190 pt: 50 % at 67/75 ms, 90 % at 200/192 ms, snap at
517/475 ms (60/120 Hz). ω₀ = 20.49 rad/s, ζ = 0.976.

**Animated transitions animate the values, not the offset.** On release every layer property
(content x, card x/alpha/radius, clip width, each button's alpha/scale/frame, icon position)
springs from its current presentation value to the target value (CA). The follower is reset to
the target first (R:761-764). For example, a button that was at alpha 0 starts fading in at the
moment of release, rather than popping when the offset reaches it. A web port must tween each
derived value with `progress(t)`. Recomputing the layout from an animated offset is not faithful.

### 1.5 Haptics
`tapticAction` fires `HapticFeedback().impact(.medium)` = `UIImpactFeedbackGenerator(style: .medium)`
(E:505-507, 709-714; HapticFeedback.swift:50-51). Its only trigger is the primary action's
**armed state changing** (over-swipe crossing 100 pt, either direction) during an interactive,
non-animated layout (R:851-856). Opening, closing and tapping are silent.

### 1.6 Active state (C, E)
`isRevealOptionsActive = offset ≠ 0`, set on every offset update (E:98-104, 566). It changes
**immediately** on the first move. When closing it changes **at the start** of the close animation,
because the target offset is already 0.
- **Card** = `highlightedBackgroundNode`. It is inserted above the separator and below the content
  (C:2186-2189) whenever `reallyHighlighted = isHighlighted || isRevealOptionsActive` (C:2163-2178):
  - frame `(leftInset + offset, −1px, W, H + 1px)`, so it covers the previous row's hairline (C:5461, 5608-5611);
  - corner radius **26** while active, 0 otherwise (C:2182, 5462). The generic default `activeCornerRadius` is also 26 (E:197);
  - colour `chatList.itemHighlightedBackgroundColor`, or `pinnedItemHighlightedBackgroundColor` on
    pinned rows (C:5424-5446, 5459);
  - opening: alpha → 1, radius → 26 and position all happen at once (transition `.immediate`, C:2190-2192).
    Closing: alpha 1→0, radius 26→0 and x→0 run together on the 0.6 s spring, and the node is removed
    when done (C:2203-2210). So the card fades out *while* it slides home.
- **Content**: the context container (avatar, title, text, date, badges) moves by `offset` through
  its bounds origin (C:4130, 5604-5606). No scale, alpha or clip. The row's own background stays put:
  clear, or `pinnedItemBackgroundColor` on pinned rows (C:5424-5446).
- **Separators**: this row's separator alpha → 0. The previous row's separator also → 0
  (`isNextRevealOptionsActive`), and so does the separator of a row whose next neighbour is open
  (`nextHasActiveRevealControls`) (C:2247-2255, 5620-5624; E:113-165).
- The online-dot ring and the live badge outline change to the highlight colour (C:2198-2199, 4447-4466).
- The row cannot be selected while it is open (E:238-240).
- **One open row at a time**: on open, `setPeerIdWithRevealedOptions(peer)` (C:5633-5642, N:1540-1555)
  makes every other row's `hasActiveRevealControls = false`, and those rows animate closed
  (`setRevealOptionsOpened(false, animated: true)`, C:5475-5477; E:660-684). List scrolling also closes it (N:3099-3104).

### 1.7 Full-swipe fill (`animateRevealOptionsFill`, E:686-694)
`allowsGroupOpacity = true`, then the offset animates to **`−W − 74`** on the 0.6 s spring. The
card leaves the left edge with 74 pt to spare. In the strip, `d = W + 74` and
`o = W + 74 − 190`. The primary capsule spans `[56, W − 10]` and its icon sits 20 pt from the
capsule's left end, at x ≈ 76. The other circles keep riding the edge: Delete ends at x −4…46 at
alpha 0.7, Mute is off-screen (R:887-907). Used by archive, unarchive, Hide (archive row), PSA hide
and forum Hide (C:5703-5743, 5769-5776). Archive also sets `skipFadeout` (the removed row is not
faded, C:5577-5584). The list then collapses the row in 0.4 s (§1.4), shows the "Chat archived"
toast, and plays the Archived Chats avatar animation (CC:6087-6158; strings "Chat archived",
"Hide the archive by swiping left on it.").

### 1.8 Closing rules
- A tap on an open row (not on the buttons) closes it on the 0.6 s spring. The tap recognizer only
  begins when `offset ≠ 0` and the pan never validated (E:263-266, 327-330, 351-356).
- Touching **another** row closes the open one at touch-down. That touch skips the list's
  selection handling, but the new row can still be swiped (LV:4942-4953, E:699-707, C:5626-5631).
- Taps on buttons hit-test the whole slot (60 × H), not just the circle (R:670-685, 922-944). The
  press-highlight call is commented out, so buttons do not dim on press (R:677).

### 1.9 Per-frame pseudo-code (one row, a side with `n` actions)
```js
const EDGE = 10, GAP = 10, SHAPE = 50, SLOT = 60, STRIDE = SHAPE + GAP;           // R:80-81, 180-189
const R = n ? 2*EDGE + n*SHAPE + (n-1)*GAP : 0;                                   // R:208-213 (n=3 → 190, n=2 → 130)
const curve = v => 1 - Math.pow(1 - clamp01(v), 2.7);                            // R:105, 224-227
// called on every pointermove (.immediate) and every follower tick
function layout() {
  const right = offset < 0, d = Math.abs(offset);
  content.x = offset; card.x = offset; card.radius = 26; card.alpha = 1;          // C:5604-5611, 2182
  sepSelf.alpha = sepPrev.alpha = 0;                                              // C:2248
  const dB = Math.min(d, R), o = Math.max(0, d - R), oP = clamp01(o / 16);        // R:821-825
  dVis = follow(dVis, d);                       // k 420, c 40, clamp ≤ d (R:756-812)
  const dV = Math.min(dVis, d, R);
  clip = right ? [W - d, W] : [0, d];                                             // E:584/609 + R:830-845
  for (let i = 0; i < n; i++) {
    const k = right ? n - 1 - i : i, primary = k === 0;                           // R:827, 850
    const p  = curve((dV - SHAPE - STRIDE*k) / 20);                               // visual   R:866-868, 889-890
    const pa = curve((dB - SHAPE - STRIDE*k) / 20);                               // actual → Lottie R:869-870, 891-892
    let L, Rt;                                                                    // capsule extent, row coords
    if (right) { Rt = W - EDGE - STRIDE*k; L = Rt - SHAPE; if (primary && o > 0) L -= o; else if (!primary) { L -= o; Rt -= o; } }
    else       { L = EDGE + STRIDE*k; Rt = L + SHAPE; if (primary && o > 0) Rt += o; else if (!primary) { L += o; Rt += o; } }
    const stretched = primary && o > 0, armed = primary && o > 100;               // R:826, 851-853
    if (armed !== btn[i].armed && !animating) haptic('medium');                   // R:854-856
    btn[i].armed = armed;
    btn[i].alpha = primary ? p : p * (1 - 0.3*oP);                                // R:496-500
    btn[i].scale = 0.3 + 0.7*p;          // about the slot centre (x = capsule centre, y = H/2)  R:503-505
    btn[i].capsule = { x: L, w: Rt - L, y: shapeY, h: 50, r: 25 };                // R:473-490
    btn[i].labelAlpha = primary ? (armed ? 0 : 1) : 1;                            // R:507
    btn[i].iconX = primary && armed ? (right ? L + 20 : Rt - 20) : (L + Rt) / 2;  // glides with e^(−18t) R:510-522
    if (pa >= 0.3) btn[i].lottie.playOnce();                                      // R:550-552
    else if (!animating && p <= 0.1) btn[i].lottie.resetToStill();               // R:553-554
  }
}
```
`shapeY`, label and icon offsets are in §2.1. On a fully completed close every Lottie is reset to
its still frame (R:837-844).

---

## 2. The actions

### 2.1 Button metrics (R)
| | value | ref |
|---|---|---|
| metric set | regular when `H ≥ 50 + 4 + ceil(lineHeight(11 pt))` = 68 and an icon exists, else compact | R:180-189 |
| regular | shape **50×50**, radius 25, slot 60, icon max side 40, armed-icon inset 20 | R:187 |
| compact (icon-less text pills, e.g. quick replies "Edit/Delete") | 60×32, radius 16, slot 70, max 24, inset 16; title `Font.regular(13)` in `iconColor` inside the pill | R:78, 185, 276-283, 584-610 |
| group widening | if any title is wider than `shape − 8` (42 pt), **all** shapes become `ceil(maxTitle + 8)` wide (slot = shape + 10) | R:191-206, 713-725 |
| strip width | `20 + 50n + 10(n−1)` → n=1: 70, n=2: 130, n=3: 190 | R:208-213, 727-733 |
| vertical (H = 76) | content = 50 + 4 + 13 (11 pt label, `floor(13.13)`, ImmediateTextNode line spacing 0) = 67 → `shapeY = floor_px(4.5)` = **4.333** @3x (4.5 @2x); circle centre y 29.33; label top 58.33 | R:464-471, 616; ImmediateTextNode.swift:22 |
| label | `Font.regular(11)` (tracking +0.064), colour `chatList.dateTextColor`, centred under the shape, `shape.maxY + 4` | R:77, 283, 615-617; C:751… |
| icon box | Lottie rendered at 66×66 (`SimpleAnimationNode`), shown at `66·scale`; if that is > 40 it is capped at 40·1.5 = **60**: `y = floor_px(cy − s/2) + (6 + offset)·s/56` | R:303, 526-533 |
| fill colour / pressed | `backgroundNode.backgroundColor = option.color`; highlight = brightness ×0.9 (unused) | R:330-331, 338-347 |
| z-order | primary on top (left side added reversed) | R:699-707 |

Label widths at 11 pt (SF Pro Text Regular with its `trak` table, no kerning): Mute 26.6, Unmute
41.2, Delete 34.0, Archive 39.6, **Unarchive 53.0**, Read 26.6, Unread 38.2, Pin 16.3, Unpin 30.7,
Hide 24.2, Remove 42.2. Inside the Archive folder, "Unarchive" therefore widens all three shapes
to **61×50** capsules (slot 71, strip 223). In the root list every label fits the 50 pt circle,
though "Unmute" ceils to 42, exactly the limit.

### 2.2 Which actions appear (C)
Right strip, left → right (the last one is the full-swipe action). Left strip, left → right (the
first one is the full-swipe action).

| row / location | left strip | right strip | ref |
|---|---|---|---|
| private, group, channel, bot — **root "All Chats"** | **Read** (if unread) or **Unread**, then **Pin**/**Unpin** | **Mute**/**Unmute**, **Delete**, **Archive** | C:746-800, 874-906, 3995-3999 |
| … custom folder | same | Archive only if the folder excludes archived chats | C:779-783 |
| Saved Messages (own chat) | Read/Unread, Pin/Unpin | **Delete** only (no mute: `isMuted` nil for the own account; no archive) | C:712-720, 3995 |
| Telegram notifications (777000) | as root | Mute, Delete (no Archive) | C:712-716 |
| forum / monoforum channel, read | **Pin** only (cannot mark unread) | as root | C:889-893 |
| community | none | Mute/Unmute, **Ungroup** (destructive) | C:879-885, 3990-3993 |
| **Archive folder** | none | **Pin**/**Unpin**, Delete, **Unarchive** | C:755-760, 787-797, 876-908 |
| "Archived Chats" row | none | **Hide** (or **Pin** = unhide when hidden) | C:804-814, 4038-4039 |
| PSA / proxy sponsor | none | Hide (delete icon); proxy: none | C:3973-3980 |
| editing mode | none | none (`setRevealOptions([],[])`) | C:5470-5474 |
| forum topic list | none | Mute/Unmute, Delete, Close/Start; General topic: Mute, Start, Hide/Unhide | C:816-872, 3948-3971 |

Pinned/unpinned only changes the left strip (Pin↔Unpin) and the row background. Muted changes
Mute↔Unmute and the badge colour. Read/unread changes Read↔Unread. Channel vs group vs private
differs only in the delete confirmation sheet ("Delete" / "Leave Channel" / "Delete Group",
CC:5453-5470).

### 2.3 Each action: title, colour, icon (C:676-691, 746-910)
Colours come from **`theme.list.itemDisclosureActions`**. There is no `chatList.itemDisclosureActions`.
| key | title (en) | fill (`list.itemDisclosureActions.*`) | Lottie | scale → box | offset → icon dy | replaceColors → fill | start frame | ref |
|---|---|---|---|---|---|---|---|---|
| pin | Pin | constructive | `anim_pin` | 1 → 60 | 0 → +6.43 | – | 3 | C:676 |
| unpin | Unpin | constructive | `anim_unpin` | 1 → 60 | 0 → +6.43 | `0x1993fa` | 5 | C:677 |
| mute | Mute | neutral2 | `anim_mute` | 1 → 60 | 0 → +6.43 | `0xff9500` | 3 | C:678 |
| unmute | Unmute | neutral2 | `anim_unmute` | 1 → 60 | 0 → +6.43 | – | 3 | C:679 |
| delete | Delete (Remove in custom lists) | destructive | `anim_delete` | 1 → 60 | 0 → +6.43 | – | 3 | C:680 |
| read | Read | **inactive** fill, neutral1 fg | `anim_read` | 1 → 60 | 0 → +6.43 | – | 5 | C:683, 887 |
| unread | Unread | **accent** | `anim_unread` | 1 → 60 | 0 → +6.43 | `0x2194fa` | 5 | C:684, 895 |
| archive | Archive | inactive | `anim_archive` | 1 → 60 | 2 → +8.57 | `0xa9a9ad` | 5 | C:685 |
| unarchive | Unarchive | inactive | `anim_unarchive` | 0.52 → 34.32 | −6 → 0 | `0xa9a9ad` | 5 | C:686 |
| hide | Hide | inactive fill, neutral1 fg | `anim_hide` | 1.1 → 60 | 2 → +8.57 | `0xbdbdc2` | 5 | C:687 |
| unhide | Pin (archive row) / Unhide (topic) | constructive | `anim_hide`, **flipped vertically** | 1 → 60 | −15 → −9.64 | `0xbdbdc2` | 5 | C:688 |
| ungroup (community) | Ungroup | destructive | `anim_ungroupcom` | 0.5 → 33 | −4 → +1.18 | – | 0 | C:691 |
| start / close (topics) | Start / Close | constructive / inactive | `anim_play` / `anim_pause` | 1 → 60 | 0 | `0xbdbdc2` (matches nothing in either file) | 5 | C:689-690 |

- `replaceColors` maps each listed RGB in the Lottie to the button's **fill** colour, so the
  cut-outs (the slash gap, box seams) are drawn in the fill (R:296-302; rlottie exact-RGB
  replacement, `RLottieInstance.mm:39-42`). `iconColor` is **not** applied to Lottie icons; they are
  white in the files. It only tints image icons and pill titles (R:283, 290).
- `flip` = `CATransform3DMakeScale(1, −1, 1)` on the icon (R:307-309).
- The icon's centre x is the circle centre, or the capsule centre while stretched. Its centre y is
  the circle centre plus the dy above (R:510-533).

### 2.4 Positions, frame by frame (H 76, root list)
- **Right strip (n = 3, R = 190)**, with circles fixed in row coordinates (E:609 + R:887-888):
  Mute `[W−180, W−130]`, Delete `[W−120, W−70]`, Archive `[W−60, W−10]`; label centres at W−155 / W−95 / W−35.
- **Left strip (n = 2, R = 130)** (E:584 + R:864-865): Read/Unread `[10, 60]`, Pin `[70, 120]`.
- Pop-in windows (actual = visual on a slow drag): slot k fades and scales over `d ∈ [50 + 60k, 70 + 60k]`:
  Archive / Read 50→70, Delete / Pin 110→130, Mute 170→190. The Lottie starts at
  `d ≥ 52.47 + 60k` (pa ≥ 0.3) and rewinds if dragged back to `dV ≤ 50.77 + 60k` (p ≤ 0.1) (R:89-90).
  Example: at d = 60, Archive has p = 0.846 (alpha .85, scale .89).
- At scale s, the circle's centre y = `38 + (29.33 − 38)·s` (the slot scales about the row's
  vertical centre), so it drifts up ~6 pt as it grows (R:455, 503-505).
- At full open the card's edge sits 10 pt from the nearest circle (`R = 20 + …`).
- Over-swipe `o = d − R`: the primary becomes a capsule `[W−60−o, W−10]` (right) or `[10, 60+o]` (left).
  The others shift by `o` and keep a 10 pt gap to the card edge, at alpha ×(1 − 0.3·min(1, o/16)).
  At `o > 100` the primary arms: haptic, label hidden, icon glides to 20 pt from the capsule's
  inner end (R:510-523, 872-907).
- Release while armed → the primary action fires (E:444-452).

### 2.5 What each action does next (C:5655-5790)
| action | row motion | then | ref |
|---|---|---|---|
| Pin / Unpin | closes (0.6 s) | the row moves to/from the pinned block (list reorder) | C:5663-5682, 5784-5787 |
| Mute / Unmute | **stays open** | after the mute toggles, `peerIdWithRevealedOptions = nil` closes it; the strip keeps its old title until then (E:307-313) | C:5683-5688; N:1647-1659 |
| Read / Unread (also the left full swipe) | stays at its offset | closes after the toggle (`togglePeersUnreadMarkInteractively`) | C:5719-5721; N:1684-1699 |
| Delete | closes | action-sheet confirmation | C:5689-5698; CC:5432-5470 |
| Archive (also the right full swipe) | **fill** to −W−74 | row removed (0.4 s collapse, no fade), "Chat archived" toast with Undo, archive avatar animation | C:5703-5711; CC:1609-1624, 6087-6158 |
| Unarchive | fill | row removed | C:5712-5718 |
| Hide (archive row) | fill | archive becomes hidden | C:5722-5730 |

---

## 3. Row layout (C, default text size)

| element | value | ref |
|---|---|---|
| row height | **76** = 17 − 21 + title 21 + 3 × measure 21 − 1 − 3. A one-line TextNode is `floor(asc+desc) + floor(lh·0.12)`; SF 16: `floor(19.09) + 2` = 21 | C:4053-4066; TN:284, 1778-1781, 1936-1947, 2146-2147 |
| top inset | 29 only above the first row of a header section | C:2151-2153 |
| avatar | **60×60 at (16, 8)**; round (forum: rounded rect, monoforum: bubble); letters SF Rounded Bold 26; story ring 2.33 / inactive 1.33 | C:2026-2044, 2565-2580, 4223; C:1691, 1897-1899; AvatarNode.swift:30-32 |
| text column | x 86, width `W − 102` (right edge **W − 16**), content rect y 8 … 63 | C:2580, 2590, 3688, 4069, 4221 |
| title | `Font.semibold(16)` (tracking −0.312), `titleColor` (secret chats `secretTitleColor`), 1 line (topics 2), frame `(86, 8 + 1px)`, **baseline 23.33**; max width `W − 102 − dateW − 10 − (24 if checks) − titleIconsW` | C:2295, 3847-3870, 4778 |
| date | `Font.regular(14)` (−0.150), `dateTextColor`, right-aligned to W − 16, y 10, **baseline 23.0**. Today `HH:mm`, last 6 days short weekday, else a date | C:2298, 4571; PresenceStrings.swift:370-393 |
| read checks | 24×24 box at `x = W−16−dateW−24`, `y = 10 − 1px + floor((17−24)/2)` = 5.67; stroke 1 + 1px, round caps; `checkmarkColor` | C:4625-4631; ChatListStatusNode.swift:282-345 |
| message | `Font.regular(15)` (−0.234), `messageTextColor`, **2 lines** (1 if an author line, tags or a topic is shown), line spacing 0.2 → pitch 20; frame `(85, 27)`, insets 2/1/2/1; **baselines 43.0 / 63.0** | C:2296, 3834-3845, 4783 |
| author line (groups) | `Font.regular(15)`, `authorNameColor`, frame (85, 27), height 23 → message moves to y 47 (baseline 63.0) | C:2842, 4781-4783 |
| unread badge | height **20**, width `max(20, textW(digits→"8") + 10)`, right edge W − 16, **y 39** (`63 − 20 − 4`); `Font semibold 12` tabular digits; active colours when unmuted, inactive when muted; scale-pop 0→1.2→1 on appear | C:2299, 2584, 3419-3446, 4635-4643; ChatListBadgeNode.swift:27-34, 87, 127-150 |
| mention / reaction badge | 20×20 icon, 6 pt left of the unread badge | C:3478-3498, 4649-4659 |
| pinned glyph | 20×20 `PeerPinnedIcon` (pin) tinted `pinnedBadgeColor`, same slot as the badge (pinned row with no unread) | C:3499-3501, 4661-4669 |
| muted glyph | 24×24 `PeerMutedIcon` (speaker-slash, PDF 24 pt box) tinted `muteIconColor`, x = title end + 3 − 5, y = 6.67 (centre on 18.83) | C:5207-5212, 5340-5347; PresentationResourcesChatList.swift:273-277 |
| emoji status / verified | 20×20 / 16×16 after the title (+3, then +4 between icons), centred on y 18.83 − 1px | C:5236-5290 |
| online dot | 14×14 at avatar-local (44, 44): a 2 pt ring in the row background colour around a 10 pt `onlineDotColor` dot | C:4443-4446; PeerOnlineMarkerNode.swift:145-150; PresentationResourcesChatList.swift:149-182 |
| separator | 1px at y `76 − 1px`, x 86 … **W − 16**; full width (0 … W) after the last pinned row and after the last row; `itemSeparatorColor` | C:927, 5387-5409 |
| row background | clear (pinned: `pinnedItemBackgroundColor`) over `chatList.backgroundColor` | C:5424-5446; ChatListControllerNode.swift:528 |
| tap highlight | the same card node, full-bleed, radius 0, shown after the list's 0.08 s delay, fades out 0.3 s easeInOut | C:2155-2161; LV:4977 |
| bottom edge effect | `list.plainBackgroundColor` @0.6, height `bottomInset + 8`, fade band `min(h, 40)` | ChatListContainerItemNode.swift:452-456 |

Tracking from the SF Pro Text `trak` table (CoreText applies it automatically; the web must set
`letter-spacing`): 11 pt +0.064, 12 pt 0, 13 pt −0.076, 14 pt −0.150, 15 pt −0.234, 16 pt −0.312,
17 pt −0.390 (`assets/fonts/SF-Pro-Text-*.otf`, trak track 0). Font metrics: ascender 1950,
descender 494, gap 0 per 2048 → `asc+desc = 1.19336 em`; a baseline sits at
`frame.y + insets.top + floor_px(0.95215·size)` (TN:1839, 2384-2396, 2544-2565).

---

## 4. Theme colours

`theme.list.itemDisclosureActions` (fill / foreground):
| key | Night (Dk:436-444) | Day (Dy:496-504) |
|---|---|---|
| neutral1 | #666666 / #ffffff | #4892f2 / #ffffff |
| neutral2 (Mute) | #cd7800 / #ffffff | #f09a37 / #ffffff |
| destructive (Delete) | #c70c0c / #ffffff | #ff3824 / #ffffff |
| constructive (Pin) | #08a723 / #ffffff | #00c900 / #ffffff |
| accent (Unread) | #666666 / #ffffff — the dark accent customisation does **not** touch it (Dk:98-104) | accent (#0088ff, re-tinted to a custom accent, Dy:118-121) / #ffffff |
| warning | #cd7800 / #ffffff | #ff9500 / #ffffff |
| inactive (Archive, Read, Hide) | #666666 / #ffffff | #bcbcc3 / #ffffff |

`theme.chatList`:
| key | Night (Dk:479-517) | Night blue (#3e88f7, Dk:7, 79-114) | Day (default is dayClassic, Dy:55, 539-577) |
|---|---|---|---|
| backgroundColor | #000000 | – | #ffffff |
| itemSeparatorColor | #545458 @0.55 | – | #c8c7cc |
| itemBackgroundColor | #000000 | – | #ffffff |
| pinnedItemBackgroundColor | #1c1c1d | – | #f7f7f7 |
| itemHighlightedBackgroundColor (**swipe card**) | **#121212** | – | **#e5e5ea** |
| pinnedItemHighlightedBackgroundColor | #2b2b2c | – | #e5e5ea |
| itemSelectedBackgroundColor | #191919 | – | #e9f0fa |
| titleColor / authorNameColor | #ffffff | – | #000000 |
| dateTextColor (also action labels) | #8d8e93 | – | #8e8e93 |
| messageTextColor | #8d8e93 | – | #8e8e93 |
| messageDraftTextColor | #dd4b39 | – | #dd4b39 |
| checkmarkColor | #ffffff | #3e88f7 | #21c004 (dayClassic) / accent (day) |
| muteIconColor | #8d8e93 | – | #a7a7ad |
| unreadBadgeActive bg / text | #ffffff / #000000 | #3e88f7 / #ffffff | #0088ff / #ffffff |
| unreadBadgeInactive bg / text | #666666 / #000000 | – | #b6b6bb / #ffffff |
| pinnedBadgeColor | #767677 | – | #b6b6bb |
| failedFillColor | #eb5545 | – | #ff3b30 |
| onlineDotColor | #4cc91f | – | #4cc91f |
| secretTitleColor | #00b12c | – | #00b12c |
| story ring unseen / seen | #34c76f→#3da1fd / #48484a | – | #34c76f→#3da1fd / #d8d8e1 |
Day `list.plainBackgroundColor` is #ffffff, Night #000000 (Dy:475, Dk:415).

---

## 5. The Chats screen around the list

Files: **CNB** `TelegramUI/Components/ChatListHeaderComponent/Sources/ChatListNavigationBar.swift`,
**CHC** `…/ChatListHeaderComponent.swift`, **NBC** `…/NavigationButtonComponent.swift`, **CLCN**
`ChatListUI/Sources/ChatListControllerNode.swift`, **NBSC** `SearchUI/Sources/NavigationBarSearchContentNode.swift`,
**SBP** `SearchBarNode/Sources/SearchBarPlaceholderNode.swift`, **SPL**/**SPLI**
`TelegramUI/Components/Stories/StoryPeerListComponent/Sources/StoryPeerList{,Item}Component.swift`,
**HPC**/**HTC** `TelegramUI/Components/{HeaderPanelContainerComponent,HorizontalTabsComponent}`, **TBC**
`TelegramUI/Components/TabBarComponent/Sources/TabBarComponent.swift`, **TBCN**
`TabBarUI/Sources/TabBarContollerNode.swift`, **LLV** `TelegramUI/Components/LiquidLens/Sources/LiquidLensView.swift`,
**EE** `TelegramUI/Components/EdgeEffect/Sources/EdgeEffect.swift`, **GBC** `TelegramUI/Components/GlassBackgroundComponent/Sources/GlassBackgroundComponent.swift`, **DM** `Display/Source/DeviceMetrics.swift`.
SB = status bar height: 48 on the user's 414×896 phone, 54 on the 16 Pro.

**Header — no large title on iOS 26.** One fixed 44 pt row plus a search row that scrolls away.
| item | value | ref |
|---|---|---|
| bar height | `SB + 3 + 44 + 9 + (60 + 2) + 3` = **SB + 121**; search collapsed **SB + 67** (it scrolls away over 54 pt); folder tabs add 40 | CNB:15-17, 797-812, 858; HPC:150 |
| launch state | the list starts scrolled down by 54 (+ stories inset), so search starts hidden | CLCN:1872 |
| button row | y = SB + 10, h 44, side insets 16 | CNB:534-542 |
| Edit | glass capsule `.panel`, x 16, h 44, w = max(44, text + 24) ≈ 57, radius 22; `Font.medium(17)` in `chat.inputPanel.panelControlColor`; pressed alpha 0.6, back over 0.2 s | CHC:1167-1169; NBC:78-89, 122, 147-148 |
| right capsule | one `.panel` capsule, 44 per button, no spacing: [new story `Chat List/AddStoryIcon`] [compose `Chat List/ComposeIcon`] = 88 × 44, right edge W − 16; icons 30×30 | CHC:476, 1185-1199; NBC:168-174; CC:6801-6811, 7244, 7278 |
| title | "Chats", `Font.semibold(17)`, `navigationBar.primaryTextColor`, centred on the row (x = (W − w)/2 + 4 with no stories). It is drawn by the story list: with stories, up to 3 avatars of 24 pt (14 pt step) + 8 pt gap + title, centred as a group | SPL:775-780, 896-900, 1390, 1443, 1691-1697; CHC:897-907 |
| stories expanded (pull down) | strip 46 pt below the row top, 79 tall; items 60×77, spacing 14; avatar 52, ring 2.33 / 1.33; name `Font.regular(11)`; fraction = −offset/96, locks open at ≤ −65 | CHC:1104-1109; SPL:1745-1755; SPLI:697-719, 1011; CNB:19-21, 461-481 |
| header background | no bar, only a fade: `list.plainBackgroundColor` @0.85 from y 0 to barH + 14, fading over the last min(54, h) pt (opacity 1, .92, .74, .51, .25, .11, 0 at 0, .23, .38, .49, .62, .73, 1), blur radius 1 | CNB:443-454; EE:51-79, 287-484 |

**Search field** (NavigationBarSearchContentNode + SearchBarPlaceholderNode `.glass`)
| item | value | ref |
|---|---|---|
| geometry | node 60 tall; field x 16, w W − 32, **h 44**, 8 pt into the node → y SB+64…SB+108 (112–156 on the user's phone) | NBSC:14, 134-137, 167; CNB:401-402 |
| look at rest | plain capsule (r = 22) filled with `navigationSearchBar.inputFillColor` (Day black @6 %, Night white @10 %); no glass until tapped | SBP:229, 293, 344; CLCN:1713 |
| placeholder | loupe 24×24 + 4 pt + "Search" `Font.regular(17)`, centred as a group, text 1 pt lower, colour `inputPlaceholderTextColor` (Day #8e8e93, Night #8f8f8f) | SBP:11, 241-264; NBSC:13, 148 |
| collapse | f = clamp(scroll/54); node y −8f; vp = clamp((1 − f − 0.267)/0.733); field h = 44·vp, bottom-anchored; text alpha (vp − 0.77)/0.23; fill alpha min(0.3, vp)/0.3 | CNB:417-423; NBSC:137-146; SBP:218, 271, 292 |

**Folder tabs** (only if the user has folders): `.panel` glass capsule x 16, w W − 32, h 40, r 20,
under the search row. Selected pill inset 3 (34 tall, r 17). Labels `Font.medium(15)` in
`panelControlColor`, 16 pt padding (HPC:130-150, 248-268; HTC:151, 346, 998-1003, 1189-1216).

**Tab bar** (iOS 26 glass, TabBarComponent)
| item | value | ref |
|---|---|---|
| frame | bottom inset **20** on iOS 26 for notched iPhones (34 before), side inset 20 (12 if the bottom inset is > 28); w = min(500, W − 40), centred, y = H − 64 − 20 → 414-pt phone: x 20, y 812, w 374 | DM:334-340; TBCN:196-216, 289-291; TBC:657 |
| capsule | h **64** (56 + 2×4), radius 32, glass `.panel` | TBC:656-665, 730; LLV:440 |
| items | Contacts, Calls (on by default), Chats, Settings; equal width `floor_px((w − 8)/n)`, h 56, from x 4 | TBC:709-733, 1340; TelegramUIPreferences/Sources/CallListSettings.swift:12-18 |
| icon / label | Lottie `TabChats…` drawn 48×48 at y −4; label `Font.semibold(10)`, bottom at 48; colours `tabBar.textColor` / `selectedTextColor` | TBC:1139-1183, 1285-1290 |
| selection | lens pill = item width × 56, r 28; on iOS 26 the native liquid lens with resting fill black @10 %; an accent-coloured copy of the icon+label shows only inside the pill; 0.4 s spring on change | TBC:795-810, 873-888; LLV:198-257, 376, 482; TBCN:224-225 |
| badge | `Font.regular(13)`, insets 0/5/1/5, right edge at item centre + 24, y 5 | TBC:1313-1322 |
| list bottom fade | `list.plainBackgroundColor` @0.6, height bottom inset + 8, 40 pt band | ChatListContainerItemNode.swift:452-456 |
Glass `.panel` on iOS 26 = `UIGlassEffect` tinted white @10 % (Day) / @2.5 % (Night). As a CSS
fallback model: fill white @70 % / #1c1c1c @85 %, shadows 30 pt @4.5 % + 20 pt @1 % (GBC:501,
720-722, 754-760, 1179-1180; see README §3).

---

## 6. Lottie icons (`submodules/TelegramUI/Resources/Animations/`)

All are Bodymovin JSON at 60 fps. `op` is the file length; "motion" is the last keyframe.
Values were read from the files.
| file | canvas | op (s) | motion ends | colours in file |
|---|---|---|---|---|
| anim_pin | 228² | 180 (3.0) | 24 | #ffffff |
| anim_unpin | 228² | 180 | 24 | #ffffff, stroke #1993fa |
| anim_mute | 228² | 180 | 25 | #ffffff, stroke #ff9500 |
| anim_unmute | 228² | 180 | 29 | #ffffff |
| anim_delete | 228² | 180 | 25 | #ffffff |
| anim_read | 228² | 30 (0.5) | 20 | #ffffff |
| anim_unread | 228² | 30 | 24 | #ffffff, stroke #2194fa |
| anim_archive | 228² | 30 | 20 | #ffffff, #a9a9ad |
| anim_unarchive | 288² | 60 (1.0) | 20 | #ffffff, #a9a9ad |
| anim_hide | 228² | 30 | 20 | #ffffff, #bdbdc2 |
| anim_ungroupcom | 512² | 29 | 28 | #ffffff |
| anim_play / anim_pause | 228² | 30 | 20 | #00c900 / #b9b9bb + #ffffff |
(`anim_archiveAvatar` 288², op 60, is the Archived Chats avatar animation, AvatarNode.swift:520.
`anim_archiveswipe` is not used by the swipe actions.)

Playback (`SimpleAnimationNode`, MAN:343-392; R:303-306, 354-364):
- Rendered by rlottie into a **66×66** bitmap at screen scale (`.noAccountFallback` → rlottie,
  LottieRenderingSettings.swift:21). The whole canvas fits that box, which is then shown scaled in
  the icon box (60 or 34.3 pt) (MAN:64-71, 335-340).
- At rest it shows the still frame **`startFrame`** (MAN:357, 363). On trigger
  `play(immediately: true)` runs frames `startFrame → op−1` once over `(op − startFrame)/fps`
  seconds at real-time speed. The pin/delete/mute files therefore move for about 0.37 s and then
  hold for about 2.6 s on their last frame (MAN:364-373, 376-381, 232-310).
- `playOnce`: it does not replay until `reset` (back to the still frame), which happens below
  p 0.1 or after a full close (R:349-364, 553-554, 837-844). With reduced translucency
  (`enableAnimations == false`) it jumps to the last frame and never animates (R:304-306;
  C:5471-5473 `energyUsageSettings.fullTranslucency`).
- Web: lottie-web with the JSON colour pre-replaced (exact RGB → fill), `goToAndStop(startFrame)`,
  then `playSegments([startFrame, op], true)`. Render into a 60×60 box (34.32 for unarchive),
  flipped vertically for unhide.

---

## 7. Notes and ambiguities

- **The designer demo is a different (prerelease) build.** The chat-list frame of the demo video
  (`video/keyframes/crop-11-chat-list-light.jpg`, 1.72–1.727 px/pt, 402 pt device) agrees with
  the code on the 76 pt pitch, the 60 pt avatar at (16, 8), the title x of about 88 and the badge
  top at y 39. But the title baseline sits about 3 pt lower (26.6 vs 23.33), the message about
  3.5 pt lower and the date about 1.7 pt lower. The separator there also runs to the screen edge,
  while the code's note says content separators stop 16 pt short (C:5390-5393). This spec follows
  the code.
- `updateLayout` places the right strip at `W + max(offset, −R)` but the offset path uses
  `min(W, W + offset)`. A relayout during an over-swipe therefore snaps the strip until the next
  move (E:557-561 vs 609).
- CA's `settlingDuration` threshold is not public. It is calibrated to 0.0012 from Telegram's 0.3832 s constant (§1.4).
- The `startIcon`/`closeIcon` `replaceColors` (`0xbdbdc2`) match no colour in `anim_play` or
  `anim_pause`, so those icons keep their own colours.
- `ItemListRevealOptionsAnimationSettingsStore` is a mutable debug store; the defaults are listed
  above (R:134-151).

## 8. Build checklist

1. Row 76 pt: avatar 60 at (16, 8), title semibold 16 at baseline 23.33, date regular 14 right
   at W − 16 with baseline 23.0, message regular 15 with baselines 43/63, badge 20 tall at y 39,
   separator from x 86 to W − 16 at y 76 − 1px. Apply SF tracking by hand.
2. Pointer handling: lock the axis at 4 pt with a 2.5:1 ratio, one row at a time, offset = dx
   1:1 with no resistance. A row without left actions clamps to ≤ 0. Touching another row closes
   the open one.
3. On the first move, show the card: highlight colour, radius 26, x = offset, height H + 1px from
   −1px. Hide this row's separator and the previous row's.
4. Action strip: a clip `[W−d, W]` (or `[0, d]`), circles fixed at `W − 60 − 60k` (right) or
   `10 + 60k` (left), p = `1 − (1 − clamp((dV − 50 − 60k)/20))^2.7` → alpha p, scale `0.3 + 0.7p`
   about (slot centre x, H/2). dV = the k 420 / c 40 follower that never overshoots d. 11 pt
   labels in `dateTextColor`.
5. Lottie: 60 pt box offset +6.43 (archive/hide +8.57, unhide −9.64 flipped, unarchive 34 pt), rest
   at startFrame, play once at pa ≥ 0.3, rewind below p 0.1 or on full close. Pre-replace the
   cut-out colour with the fill.
6. Over-swipe: the primary capsule stretches toward the card, the others ride the edge at
   alpha ×0.7 (ramped over 16 pt). Above 100 pt: medium haptic and the label hides. The icon
   glides (τ 56 ms) to 20 pt from the inner end; the haptic fires again on disarm.
7. Release: |v| < 100 → open if started closed (any distance) or beyond R; otherwise follow
   the direction. If armed, fire the primary action instead. Animate every derived value with
   `1 − 1.0455e^(−11.28t) + 0.0455e^(−259t)` over 0.6 s; on close the card also fades and its
   radius goes to 0. Do not carry finger velocity.
8. Actions: Archive = fill to −W−74, then collapse the row in 0.4 s and show the toast;
   Mute/Read = stay open until the toggle lands, then close; Pin/Delete = close at once (Delete
   opens its sheet). Tapping the open card closes it.
9. Colours from §4: Night card #121212 on #000, Day #e5e5ea on #fff. The swipe actions use
   `list.itemDisclosureActions`.
