#!/usr/bin/env bash
# Verifies every native module on a Mac (any CI: codemagic.yaml runs it; the GitHub workflows run the same
# steps per module). Each check runs even if an earlier one failed; the summary lists them all.
#   1. pure-Swift maths replays golden data recorded from the web prototype (swift test),
#   2. the Metal shader compiles for iOS,
#   3. every module builds for the iOS Simulator with -warnings-as-errors against Telegram API stubs,
#   4. the patches apply on Telegram-iOS f1dd7a2, alone and in order 0001…0005.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d)
cd "$ROOT"
results=()
step() {  # name, then a command string run in a subshell from the repo root
  local name=$1; shift
  echo
  echo "════ $name"
  if (cd "$ROOT" && bash -euo pipefail -c "$*") > "$TMP/log" 2>&1; then
    grep -vE "^\[[0-9]+/[0-9]+\]" "$TMP/log" | tail -15
    results+=("PASS  $name")
  else
    grep -vE "^\[[0-9]+/[0-9]+\]" "$TMP/log" | tail -120
    results+=("FAIL  $name")
  fi
}
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
IOS="--sdk $SDK --triple arm64-apple-ios15.0-simulator -Xswiftc -warnings-as-errors"
xcodebuild -version
swift --version

# ---------------------------------------------------------------- 1 · 2 Glass Avatar + Back Photo
if [ -d ios/GlassCoinAvatar ]; then
  step "Glass Avatar · physics replays the web golden trajectories" '
    cd ios/Standalone/Core && mkdir -p Sources/GlassCoinCore
    cp ../../GlassCoinAvatar/Sources/GlassCoinPhysics.swift Sources/GlassCoinCore/
    swift test'
  step "Glass Avatar · Metal shader compiles for iOS" "
    xcrun -sdk iphoneos metal -c ios/GlassCoinAvatar/Metal/GlassCoin.metal -o $TMP/GlassCoin.air
    xcrun -sdk iphoneos metallib $TMP/GlassCoin.air -o $TMP/GlassCoin.metallib && ls -la $TMP/GlassCoin.metallib"
  step "Glass Avatar · module builds for iOS (-warnings-as-errors)" "
    cd ios/Standalone/TypeCheck && mkdir -p Sources/GlassCoinAvatar
    cp ../../GlassCoinAvatar/Sources/*.swift Sources/GlassCoinAvatar/
    swift build $IOS"
fi

# ---------------------------------------------------------------- 3 Living Icons
if [ -d ios/LivingSettingsIcons ]; then
  step "Living Icons · every rig replays the web golden frames; icons at rest are Telegram's glyphs" '
    cd ios/Standalone/LivingIconsCore && mkdir -p Sources/LivingIconsCore
    cp ../../LivingSettingsIcons/Sources/LivingIcon*.swift Sources/LivingIconsCore/
    swift test'
  step "Living Icons · module builds for iOS (-warnings-as-errors)" "
    cd ios/Standalone/LivingIconsTypeCheck && mkdir -p Sources/LivingSettingsIcons
    cp ../../LivingSettingsIcons/Sources/*.swift Sources/LivingSettingsIcons/
    swift build $IOS"
fi

# ---------------------------------------------------------------- 4 Depth Swipe
if [ -d ios/DepthSwipe ]; then
  step "Depth Swipe · the rig replays the web golden frames" '
    cd ios/Standalone/DepthSwipeCore && mkdir -p Sources/DepthSwipeCore
    cp ../../DepthSwipe/Sources/DepthSwipeSpring.swift ../../DepthSwipe/Sources/DepthSwipeRig.swift ../../DepthSwipe/Sources/DepthSwipeTracker.swift Sources/DepthSwipeCore/
    swift test -Xswiftc -warnings-as-errors'
  step "Depth Swipe · module and hooks build for iOS (-warnings-as-errors)" "
    cd ios/Standalone/DepthSwipeTypeCheck && mkdir -p Sources/DepthSwipe
    cp ../../DepthSwipe/Sources/*.swift Sources/DepthSwipe/
    swift build $IOS"
fi

# ---------------------------------------------------------------- 5 Glass Gifts
if [ -d ios/GlassGifts ]; then
  step "Glass Gifts · tile model and motion filter replay the web golden frames" '
    cd ios/Standalone/GlassGiftsCore && mkdir -p Sources/GlassGiftsCore
    cp ../../GlassGifts/Sources/GlassTileModel.swift ../../GlassGifts/Sources/GlassGiftMotionFilter.swift Sources/GlassGiftsCore/
    swift test -Xswiftc -warnings-as-errors'
  step "Glass Gifts · module and hooks build for iOS (-warnings-as-errors)" "
    cd ios/Standalone/GlassGiftsTypeCheck && mkdir -p Sources/GlassGifts
    cp ../../GlassGifts/Sources/*.swift Sources/GlassGifts/
    swift build $IOS"
fi

# ---------------------------------------------------------------- patches on Telegram-iOS f1dd7a2
patches=(ios/patches/0*.patch)
if [ -e "${patches[0]}" ]; then
  TG="$TMP/Telegram-iOS"
  dirs=$(grep -h '^diff --git' "${patches[@]}" | awk '{print $3}' | sed 's|^a/||' | xargs -n1 dirname | sort -u)
  step "Patches · sparse checkout of Telegram-iOS f1dd7a2" "
    git init -q $TG && git -C $TG remote add origin https://github.com/TelegramMessenger/Telegram-iOS.git
    git -C $TG config core.sparseCheckout true
    printf '%s/\n' $dirs | sed 's|^|/|' > $TG/.git/info/sparse-checkout
    git -C $TG fetch -q --depth 1 --filter=blob:none origin f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838
    git -C $TG checkout -q FETCH_HEAD && git -C $TG log --oneline -1"
  for p in "${patches[@]}"; do
    n=$(basename "$p" .patch)
    case "$n" in 0002-*) continue ;; esac   # 0002 applies on top of 0001 only (checked below)
    step "Patch $n applies alone on f1dd7a2" "git -C $TG apply --check $ROOT/$p"
  done
  step "Patches 0001…0005 apply in order (and carry the modules unchanged)" "
    for p in ${patches[*]}; do git -C $TG apply --whitespace=nowarn $ROOT/\$p && echo \"applied \$(basename \$p)\"; done
    diff -r $TG/submodules/TelegramUI/Components/PeerInfo/GlassCoinAvatar ios/GlassCoinAvatar
    git -C $TG status --short | head -40"
fi

echo
echo "════ summary"
printf '%s\n' "${results[@]}"
rm -rf "$TMP"
! printf '%s\n' "${results[@]}" | grep -q '^FAIL'
