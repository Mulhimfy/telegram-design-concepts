#!/usr/bin/env bash
# Publishes the current main as one snapshot commit to the public repository
# (github.com/Mulhimfy/telegram-design-concepts), without this repository's history and without the files that
# must stay private or aren't ours to publish:
#   · research/source/IMG_6025.MP4 — Telegram's own designer demo (t.me/designers/266), the research input.
# The snapshot branch is `public` here; every run adds one commit on top of the previous snapshot. GitHub Actions
# runs the native checks there (free on public repositories).
#   tools/publish.sh "message"
set -euo pipefail
cd "$(dirname "$0")/.."
msg=${1:-"Snapshot of $(git rev-parse --short HEAD)"}
EXCLUDE=(research/source/IMG_6025.MP4)
remote=public
git remote get-url "$remote" >/dev/null 2>&1 || git remote add "$remote" https://github.com/Mulhimfy/telegram-design-concepts.git
idx=$(mktemp)
trap 'rm -f "$idx"' EXIT
export GIT_INDEX_FILE=$idx
git read-tree main
for p in "${EXCLUDE[@]}"; do git rm -q --cached --ignore-unmatch -- "$p"; done
tree=$(git write-tree)
unset GIT_INDEX_FILE
parent=$(git rev-parse -q --verify refs/heads/public || true)
if [ -n "$parent" ] && [ "$(git rev-parse "$parent^{tree}")" = "$tree" ]; then
  echo "nothing new to publish"
  exit 0
fi
commit=$(printf '%s\n\nFrom %s.\n' "$msg" "$(git rev-parse --short main)" | git commit-tree "$tree" ${parent:+-p "$parent"})
git update-ref refs/heads/public "$commit"
git push -q "$remote" public:main
echo "published $(git rev-parse --short "$commit") → $(git remote get-url "$remote")"
