#!/usr/bin/env bash
# Renders the five design demos (prototype/src/scripts/*-demo.js) frame-exactly and gives each the
# fade in / fade out of the submission cut: renders/designs/<n>-<key>.mp4 (1080×1080, 60 fps, BT.709).
# Needs `node tools/serve.mjs` (the whole repo on :8737, so SF Pro loads from assets/fonts).
#   tools/render-designs.sh [key …]      (default: all five, one at a time)
set -euo pipefail
cd "$(dirname "$0")"
declare -A N=([glass]=1 [back]=2 [icons]=3 [swipe]=4 [gifts]=5)
declare -A Q=([glass]="" [back]="" [icons]="" [swipe]="&tab=chats" [gifts]="&tab=chats")
keys=("$@")
[ ${#keys[@]} -eq 0 ] && keys=(swipe gifts icons back glass)
mkdir -p ../renders/takes ../renders/designs
for k in "${keys[@]}"; do
  echo "== $k"
  node record.mjs --url "http://127.0.0.1:8737/prototype/?composition=square&record=1&theme=dark&demo=$k${Q[$k]}" \
    --out "../renders/takes/$k.mp4"
  ./compose.sh "../renders/designs/${N[$k]}-$k.mp4" "../renders/takes/$k.mp4"
done
echo ALL-DONE
