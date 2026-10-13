#!/usr/bin/env bash
# Downloads Apple's SF Pro into assets/fonts/ for rendering UI mock-ups on Linux (allowed by
# Apple's SF Pro licence for mock-ups of Apple-platform UIs; never commit or redistribute the files).
# Needs: curl, 7z (p7zip / 7zip), cpio, gzip.
set -euo pipefail
cd "$(dirname "$0")/../assets/fonts"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -sSL -o "$tmp/SF-Pro.dmg" https://devimages-cdn.apple.com/design/resources/download/SF-Pro.dmg
7z e -y -o"$tmp" "$tmp/SF-Pro.dmg" SFProFonts.pkg >/dev/null
7z e -y -o"$tmp" "$tmp/SFProFonts.pkg" 'SFProFontsPackage.pkg/Payload' >/dev/null
( cd "$tmp" && zcat Payload | cpio -idm --quiet \
  './Library/Fonts/SF-Pro-Text-Regular.otf' './Library/Fonts/SF-Pro-Text-Medium.otf' './Library/Fonts/SF-Pro-Text-Semibold.otf' './Library/Fonts/SF-Pro-Text-Bold.otf' \
  './Library/Fonts/SF-Pro-Display-Regular.otf' './Library/Fonts/SF-Pro-Display-Medium.otf' './Library/Fonts/SF-Pro-Display-Semibold.otf' './Library/Fonts/SF-Pro-Display-Bold.otf' \
  './Library/Fonts/SF-Pro-Rounded-Semibold.otf' './Library/Fonts/SF-Pro-Rounded-Bold.otf' )
mv "$tmp"/Library/Fonts/*.otf .
ls -1 *.otf
