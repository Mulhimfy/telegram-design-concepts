#!/usr/bin/env bash
# Publishes the prototype + @Tgdesignbot to Cloudflare Pages (project "tgdesign"), so people can
# test the designs from the bot whether or not this server is up:
#   · the static prototype (prototype/) and the demo videos (renders/designs/*.mp4),
#   · _worker.js: the bot's webhook (Pages advanced mode),
#   · the bot itself: webhook, menu button, commands, descriptions.
#
#   tools/bot/deploy.sh            deploy + configure the bot
#
# Machine-local config, never in the repo: /root/.config/tgdesign-bot/env (BOT_TOKEN; HOOK_PATH and
# WEBHOOK_SECRET are generated there on the first run), Cloudflare in /root/.config/gist/cloudflare.env.
set -euo pipefail
cd "$(dirname "$0")/../.."
CONF=/root/.config/tgdesign-bot/env
set -a; . "$CONF"; . /root/.config/gist/cloudflare.env; set +a
if [ -z "${HOOK_PATH:-}" ] || [ -z "${WEBHOOK_SECRET:-}" ]; then
  HOOK_PATH=$(openssl rand -hex 16)
  WEBHOOK_SECRET=$(openssl rand -hex 24)
  umask 077
  printf 'HOOK_PATH=%s\nWEBHOOK_SECRET=%s\n' "$HOOK_PATH" "$WEBHOOK_SECRET" >> "$CONF"
  NEW_SECRETS=1
fi
PROJECT=tgdesign
W=${WRANGLER:-/root/distilled/node_modules/.bin/wrangler}
api="https://api.telegram.org/bot$BOT_TOKEN"

dist=$(mktemp -d)
trap 'rm -rf "$dist"' EXIT
cp -r prototype/. "$dist/"
rm -f "$dist/artifact.html"
cp tools/bot/_worker.js "$dist/_worker.js"
# A 404 page turns off Pages' single-page fallback: a missing file (SF Pro is never deployed: Apple's
# licence) is a plain 404, not index.html served as a font.
printf '<!doctype html><title>Not found</title>' > "$dist/404.html"
# Demo videos (one per design), listed in videos/index.json for the bot.
if ls renders/designs/*.mp4 >/dev/null 2>&1; then
  mkdir -p "$dist/videos"
  python3 - "$dist/videos" renders/designs/*.mp4 <<'EOF'
import json, os, shutil, subprocess, sys
out, files = sys.argv[1], sys.argv[2:]
index = {}
for f in files:
    key = os.path.basename(f).split('-', 1)[1].rsplit('.', 1)[0] if '-' in os.path.basename(f) else os.path.basename(f)[:-4]
    meta = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=width,height',
                           '-show_entries', 'format=duration', '-of', 'json', f], capture_output=True, text=True).stdout
    m = json.loads(meta)
    dst = os.path.join(out, f'{key}.mp4')
    if os.path.getsize(f) > 19 * 1024 * 1024:
        # Telegram fetches videos by URL up to 20 MB: a lighter encode of the same frames for the bot
        # (cached next to the renders, redone when the render is newer).
        cache = os.path.join(os.path.dirname(f), '.bot', f'{key}.mp4')
        if not os.path.exists(cache) or os.path.getmtime(cache) < os.path.getmtime(f):
            os.makedirs(os.path.dirname(cache), exist_ok=True)
            for crf in (22, 25, 28):
                subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', f, '-c:v', 'libx264', '-preset', 'medium', '-crf', str(crf),
                                '-pix_fmt', 'yuv420p', '-movflags', '+faststart', '-threads', '1', cache], check=True)
                if os.path.getsize(cache) <= 19 * 1024 * 1024:
                    break
        shutil.copy(cache, dst)
    else:
        shutil.copy(f, dst)
    index[key] = {'file': f'{key}.mp4', 'width': m['streams'][0]['width'], 'height': m['streams'][0]['height'],
                  'duration': round(float(m['format']['duration']))}
json.dump(index, open(os.path.join(out, 'index.json'), 'w'), indent=1)
print('videos:', ', '.join(sorted(index)))
EOF
fi

cf="https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects"
auth="Authorization: Bearer $CLOUDFLARE_API_TOKEN"
# (Created through the API: wrangler 4.14x hands `pages project create` to Workers, which fails.)
curl -sSf -H "$auth" "$cf/$PROJECT" >/dev/null 2>&1 || curl -sS -X POST -H "$auth" -H 'content-type: application/json' "$cf" \
  -d "{\"name\":\"$PROJECT\",\"production_branch\":\"main\"}" >/dev/null
if [ -n "${NEW_SECRETS:-}" ] || ! $W pages secret list --project-name "$PROJECT" 2>/dev/null | grep -q BOT_TOKEN; then
  for k in BOT_TOKEN HOOK_PATH WEBHOOK_SECRET; do
    printf '%s' "${!k}" | $W pages secret put "$k" --project-name "$PROJECT" >/dev/null
  done
  echo "secrets set"
fi
$W pages deploy "$dist" --project-name "$PROJECT" --branch main --commit-dirty=true 2>&1 | grep -E "Success|Deployment complete|error|Error" | tail -3

origin="https://$(curl -sS -H "$auth" "$cf/$PROJECT" | python3 -c "import sys, json; print(json.load(sys.stdin)['result']['subdomain'])")"
ok() { python3 -c "import sys, json; r = json.load(sys.stdin); print('  $1:', 'ok' if r.get('ok') else r.get('description'))"; }
echo "site $origin"
curl -sS "$api/setWebhook" -H 'content-type: application/json' -d "$(python3 -c "import json,sys; print(json.dumps({'url': sys.argv[1], 'secret_token': sys.argv[2], 'allowed_updates': ['message', 'callback_query'], 'drop_pending_updates': True}))" "$origin/tg/$HOOK_PATH" "$WEBHOOK_SECRET")" | ok webhook
curl -sS "$api/setChatMenuButton" -H 'content-type: application/json' -d "{\"menu_button\":{\"type\":\"web_app\",\"text\":\"Try\",\"web_app\":{\"url\":\"$origin/\"}}}" | ok menu
curl -sS "$api/setMyCommands" -H 'content-type: application/json' -d '{"commands":[{"command":"start","description":"The five designs"},{"command":"videos","description":"All demo videos"},{"command":"glass","description":"Glass Avatar"},{"command":"back","description":"Back Photo"},{"command":"icons","description":"Living Icons"},{"command":"swipe","description":"Depth Swipe"},{"command":"gifts","description":"Glass Gifts"}]}' | ok commands
curl -sS "$api/setMyShortDescription" --data-urlencode "short_description=Five Telegram iOS design concepts you can try live: Glass Avatar, Back Photo, Living Icons, Depth Swipe, Glass Gifts." | ok short
curl -sS "$api/setMyDescription" --data-urlencode "description=Five design concepts for Telegram iOS, running in a replica of the app:

🪟 Glass Avatar — your photo turns to glass under your finger
🔄 Back Photo — your photo gets a back side
⚙️ Living Icons — Settings icons come alive
💬 Depth Swipe — chats move in 3D as you swipe
🎁 Glass Gifts — gifts become panes of glass

Tap Start, then a design to try it." | ok description
