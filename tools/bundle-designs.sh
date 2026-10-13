#!/usr/bin/env bash
# One self-contained zip per design for the submission: its README (spec + submission text), its demo
# video, its native code (module + patch) and the web prototype that runs it.
#   tools/bundle-designs.sh            → dist/<n>-<Name>.zip
set -euo pipefail
cd "$(dirname "$0")/.."
out=dist
rm -rf "$out" && mkdir -p "$out"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

bundle() {  # n key Name "native paths…"
  local n=$1 key=$2 name=$3; shift 3
  local d="$work/$n-$name"
  mkdir -p "$d"
  cp -r "designs/$n-"*/. "$d/"
  [ -f "renders/designs/$n-$key.mp4" ] && cp "renders/designs/$n-$key.mp4" "$d/$name-demo.mp4"
  mkdir -p "$d/native"
  for p in "$@"; do
    [ -e "$p" ] || { echo "missing $p" >&2; exit 1; }
    mkdir -p "$d/native/$(dirname "${p#ios/}")"
    cp -r "$p" "$d/native/${p#ios/}"
  done
  # The web prototype (one app with every design; SF Pro is not included: Apple's licence).
  mkdir -p "$d/prototype"
  cp -r prototype/. "$d/prototype/"
  rm -f "$d/prototype/artifact.html"
  printf '%s\n' "Open prototype/index.html through any static server, e.g.:" "  npx serve prototype   or   python3 -m http.server -d prototype" \
    "Try it in Telegram: https://t.me/Tgdesignbot?start=$key" > "$d/HOW-TO-RUN.txt"
  (cd "$work" && python3 -m zipfile -c "$OLDPWD/$out/$n-$name.zip" "$n-$name")
  echo "$out/$n-$name.zip $(du -h "$out/$n-$name.zip" | cut -f1)"
}

bundle 1 glass Glass-Avatar ios/GlassCoinAvatar ios/patches/0001-glass-avatar.patch ios/README.md
bundle 2 back Back-Photo ios/GlassCoinAvatar ios/patches/0001-glass-avatar.patch ios/patches/0002-back-photo.patch ios/README.md
bundle 3 icons Living-Icons ios/LivingSettingsIcons ios/patches/0003-living-icons.patch
bundle 4 swipe Depth-Swipe ios/DepthSwipe ios/patches/0004-depth-swipe.patch
bundle 5 gifts Glass-Gifts ios/GlassGifts ios/patches/0005-glass-gifts.patch
