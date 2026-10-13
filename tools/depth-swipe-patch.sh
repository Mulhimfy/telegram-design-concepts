#!/bin/bash
# ios/patches/0004-depth-swipe.patch — Depth Swipe for Telegram-iOS f1dd7a2.
#
#   tools/depth-swipe-patch.sh           regenerates the patch: the module part from ios/DepthSwipe
#                                        (the single source of truth), the hooks part (ChatListUI,
#                                        ItemListUI) from the current patch; then checks it
#   tools/depth-swipe-patch.sh --check   only checks: the patch applies to the pristine files and
#                                        the module it adds is exactly ios/DepthSwipe
#
# The pristine files are fetched from the public repository at f1dd7a2 into a temporary git repo
# (nothing touches a Telegram-iOS checkout). Needs curl and git.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SHA=f1dd7a2dbd02cbbf513e75d5695d8d36d1cf5838
PATCH="$ROOT/ios/patches/0004-depth-swipe.patch"
MODULE=submodules/TelegramUI/Components/ChatList/DepthSwipe
HOOKED=(
  submodules/ChatListUI/BUILD
  submodules/ChatListUI/Sources/Node/ChatListItem.swift
  submodules/ItemListUI/Sources/Items/ItemListEditableItem.swift
)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

git_() {
  git -c user.name=depth-swipe -c user.email=depth-swipe@localhost -c core.quotepath=off -c diff.noprefix=false "$@"
}

# A git repo holding the pristine files the patch touches, at their paths.
pristine() {
  mkdir -p "$1"
  cd "$1"
  git_ init -q .
  for f in "${HOOKED[@]}"; do
    mkdir -p "$(dirname "$f")"
    curl -sSfL "https://raw.githubusercontent.com/TelegramMessenger/Telegram-iOS/$SHA/$f" -o "$f"
  done
  git_ add -A
  git_ commit -qm "Telegram-iOS ${SHA:0:7}"
}

if [ "${1:-}" != "--check" ]; then
  pristine "$WORK/build"
  git_ apply --include='submodules/ChatListUI/*' --include='submodules/ItemListUI/*' "$PATCH"
  mkdir -p "$MODULE/Sources"
  cp "$ROOT/ios/DepthSwipe/BUILD" "$MODULE/BUILD"
  cp "$ROOT/ios/DepthSwipe/Sources/"*.swift "$MODULE/Sources/"
  git_ add -A
  git_ diff --cached --no-color --no-ext-diff > "$PATCH"
  echo "wrote ios/patches/0004-depth-swipe.patch"
fi

pristine "$WORK/check"
git_ apply --check "$PATCH"
git_ apply "$PATCH"
diff -r "$MODULE/Sources" "$ROOT/ios/DepthSwipe/Sources"
diff "$MODULE/BUILD" "$ROOT/ios/DepthSwipe/BUILD"
echo "the patch applies to Telegram-iOS ${SHA:0:7}; its module is ios/DepthSwipe"

# The hook functions the typecheck compiles (ios/Standalone/DepthSwipeTypeCheck/HookCheck) are the
# patch's, verbatim, and they are called where the patch says.
ITEM=submodules/ChatListUI/Sources/Node/ChatListItem.swift
STANDIN="$ROOT/ios/Standalone/DepthSwipeTypeCheck/HookCheck/ChatListItemHooks.swift"
trim() { awk 'NF { for (i = 0; i < blank; i++) print ""; blank = 0; print; next } { blank++ }'; }
diff \
  <(awk '/^    private func updateDepthSwipe\(/ { p = 1 } /^    override public func revealOptionsActiveStateUpdated\(/ { p = 0 } p' "$ITEM" | trim) \
  <(awk '/\/\/ END ChatListItem.swift hooks/ { p = 0 } p; /\/\/ BEGIN ChatListItem.swift hooks/ { p = 1 }' "$STANDIN" | trim)
grep -q '^        self.updateDepthSwipe(offset: offset, transition: transition)$' "$ITEM"
grep -q '^                    strongSelf.depthSwipe?.contentUpdated()$' "$ITEM"
echo "the hooks HookCheck compiles are the patch's"
git_ diff --stat
