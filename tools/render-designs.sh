#!/usr/bin/env bash
# Renders the five design demos (prototype/src/scripts/*-demo.js) frame-exactly, each twice — after (the
# design) and before (the same moments in Telegram today, ?before=1) — and gives them the fade in / fade out
# of the submission cut: renders/designs/<n>-<key>-after.mp4 and -before.mp4 (1080×1080, 60 fps, BT.709).
# Needs `node tools/serve.mjs` (the whole repo on :8737, so SF Pro loads from assets/fonts).
#   tools/render-designs.sh [key[:after|:before] …]      (default: all ten, one at a time)
set -euo pipefail
cd "$(dirname "$0")"
declare -A N=([glass]=1 [back]=2 [icons]=3 [swipe]=4 [gifts]=5)
declare -A Q=([glass]="" [back]="" [icons]="" [swipe]="&tab=chats" [gifts]="&tab=chats")
jobs=("$@")
[ ${#jobs[@]} -eq 0 ] && jobs=(swipe:after swipe:before icons:after icons:before gifts:after gifts:before back:after back:before glass:after glass:before)
mkdir -p ../renders/takes ../renders/designs
for job in "${jobs[@]}"; do
  k=${job%%:*}
  modes=${job#*:}
  [ "$modes" = "$job" ] && modes="after before"
  for mode in $modes; do
    echo "== $k $mode"
    extra=""
    [ "$mode" = before ] && extra="&before=1"
    node record.mjs --url "http://127.0.0.1:8737/prototype/?composition=square&record=1&theme=dark&demo=$k${Q[$k]}$extra" \
      --out "../renders/takes/$k-$mode.mp4"
    ./compose.sh "../renders/designs/${N[$k]}-$k-$mode.mp4" "../renders/takes/$k-$mode.mp4"
  done
done
echo ALL-DONE
