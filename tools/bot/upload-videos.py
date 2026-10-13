#!/usr/bin/env python3
"""Uploads the demo videos to Telegram once through @Tgdesignbot and keeps their file ids in
tools/bot/videos.json, so the bot sends each video by id (instant; Telegram can't fetch them from
Cloudflare Pages by URL). The upload goes to the owner's chat and is deleted right after: the file id
stays valid. Only videos that changed since the last upload (by size + mtime) are sent again.

    tools/bot/upload-videos.py            # renders/designs/<n>-<key>[-before|-after].mp4
"""
import json, os, subprocess, sys, glob, re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, 'tools/bot/videos.json')
env = {}
for line in open('/root/.config/tgdesign-bot/env'):
    if '=' in line:
        k, v = line.strip().split('=', 1)
        env[k] = v
OWNER = '7236904390'
api = f"https://api.telegram.org/bot{env['BOT_TOKEN']}"

def call(method, *args):
    r = subprocess.run(['curl', '-sS', '--max-time', '900', f'{api}/{method}', *args], capture_output=True, text=True)
    try:
        return json.loads(r.stdout)
    except Exception:
        return {'ok': False, 'description': r.stdout[:200] or r.stderr[:200]}

index = json.load(open(OUT)) if os.path.exists(OUT) else {}
for f in sorted(glob.glob(os.path.join(ROOT, 'renders/designs/*.mp4'))):
    m = re.match(r'\d+-([a-z]+)(?:-(before|after))?\.mp4$', os.path.basename(f))
    if not m:
        continue
    key = f"{m.group(1)}-{m.group(2) or 'after'}"
    stamp = f'{os.path.getsize(f)}:{int(os.path.getmtime(f))}'
    if index.get(key, {}).get('stamp') == stamp:
        print(f'{key}: unchanged')
        continue
    meta = json.loads(subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=width,height',
                                      '-show_entries', 'format=duration', '-of', 'json', f], capture_output=True, text=True).stdout)
    w, h = meta['streams'][0]['width'], meta['streams'][0]['height']
    d = round(float(meta['format']['duration']))
    thumb = f + '.thumb.jpg'
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-ss', '3', '-i', f, '-frames:v', '1', '-vf', 'scale=320:320', '-q:v', '3', thumb], check=True)
    r = call('sendVideo', '-F', f'chat_id={OWNER}', '-F', f'video=@{f}', '-F', f'thumbnail=@{thumb};filename=thumb.jpg',
             '-F', f'width={w}', '-F', f'height={h}', '-F', f'duration={d}', '-F', 'supports_streaming=true',
             '-F', 'disable_notification=true', '-F', 'caption=(caching the demo video for the bot)')
    os.remove(thumb)
    if not r.get('ok'):
        print(f'{key}: upload failed: {r.get("description")}', file=sys.stderr)
        continue
    msg = r['result']
    file_id = msg['video']['file_id']
    call('deleteMessage', '-d', f'chat_id={OWNER}', '-d', f'message_id={msg["message_id"]}')
    index[key] = {'file_id': file_id, 'width': w, 'height': h, 'duration': d, 'stamp': stamp}
    print(f'{key}: uploaded')
    json.dump(index, open(OUT, 'w'), indent=1, sort_keys=True)
json.dump(index, open(OUT, 'w'), indent=1, sort_keys=True)
