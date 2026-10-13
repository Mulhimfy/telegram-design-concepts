#!/usr/bin/env bash
# Sends the phone test links, or a video, to the owner through the notifier bot.
#   tools/phone/tg-send.sh links ["html text"]
#   tools/phone/tg-send.sh video renders/designs/1-glass.mp4 ["caption"] [thumbnail-time-s]
#   tools/phone/tg-send.sh doc dist/1-Glass-Avatar.zip ["caption"]
#   tools/phone/tg-send.sh text "html" ['{"inline_keyboard": …}']
# Machine-local config, never in the repo: BOT_TOKEN / OWNER_ID in /root/.config/warrior-bot/env,
# the unguessable URL path in /root/.config/tgdesign-test-path.
set -euo pipefail
cd "$(dirname "$0")/../.."
set -a; . /root/.config/warrior-bot/env; set +a
api="https://api.telegram.org/bot$BOT_TOKEN"
base="https://tgdesign.62-238-117-250.sslip.io/$(cat /root/.config/tgdesign-test-path)/"
report() { python3 -c "import sys, json; r = json.load(sys.stdin); print('sent' if r.get('ok') else 'failed', r.get('result', {}).get('message_id', ''), r.get('description', ''))"; }

case "${1:-}" in
  links)
    keyboard=$(python3 - "$base" <<'EOF2'
import json, sys
b = sys.argv[1]
print(json.dumps({"inline_keyboard": [
    [{"text": "🪙 Open in Telegram", "web_app": {"url": b}},
     {"text": "🌐 Open in browser", "url": b}],
]}))
EOF2
)
    text=${2:-$(cat <<'EOF2'
<b>Glass Avatar — test build</b> 🪙
Touch your photo: it turns to glass. Drag any way to tilt, past edge-on to turn it over, flick to spin.
New rows: <b>Add Back Photo</b> and <b>Change Glass Color</b>. Scroll and pull the header like in Telegram.

• 🪙 opens it inside Telegram: native haptics, your theme.
• 🌐 opens the browser. Safari → Share → Add to Home Screen runs it full-screen.
On Android, haptics need the phone's touch vibration on.

It's live: when the code changes, an open page reloads by itself.
EOF2
)}
    curl -sS "$api/sendMessage" --data-urlencode chat_id="$OWNER_ID" --data-urlencode text="$text" \
      --data-urlencode parse_mode=HTML --data-urlencode reply_markup="$keyboard" \
      --data-urlencode 'link_preview_options={"is_disabled":true}' | report
    ;;
  video)
    file=${2:?video file}
    caption=${3:-"<b>Glass Coin</b> — $(basename "$file")"}
    at=${4:-3.4}
    thumb=$(mktemp --suffix .jpg)
    trap 'rm -f "$thumb"' EXIT
    ffmpeg -v error -y -ss "$at" -i "$file" -frames:v 1 -vf "scale=320:320:force_original_aspect_ratio=decrease" -q:v 3 "$thumb"
    meta=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -show_entries format=duration \
      -of default=nw=1:nk=1 "$file" | tr '\n' ' ')
    read -r w h d <<< "$meta"
    # --form-string: captions start with "<" (HTML), which -F would read as a file name.
    curl -sS --max-time 600 "$api/sendVideo" --form-string chat_id="$OWNER_ID" -F video=@"$file" \
      -F thumb=@"$thumb" --form-string thumbnail=attach://thumb \
      --form-string width="$w" --form-string height="$h" --form-string duration="$(printf '%.0f' "$d")" \
      --form-string supports_streaming=true --form-string parse_mode=HTML --form-string caption="$caption" | report
    ;;
  doc)
    file=${2:?file}
    caption=${3:-}
    curl -sS --max-time 900 "$api/sendDocument" --form-string chat_id="$OWNER_ID" -F document=@"$file" \
      --form-string parse_mode=HTML --form-string caption="$caption" | report
    ;;
  text)
    # tools/phone/tg-send.sh text "html" ['{"inline_keyboard": …}']
    extra=()
    [ -n "${3:-}" ] && extra=(--data-urlencode reply_markup="$3")
    curl -sS "$api/sendMessage" --data-urlencode chat_id="$OWNER_ID" --data-urlencode text="${2:?text}" \
      --data-urlencode parse_mode=HTML "${extra[@]}" \
      --data-urlencode 'link_preview_options={"is_disabled":true}' | report
    ;;
  *)
    echo "usage: $0 links | video FILE [caption] [thumbnail-time-s] | doc FILE [caption] | text HTML [keyboard-json]" >&2
    exit 2
    ;;
esac
