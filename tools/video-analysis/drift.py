# Multi-bubble drift tracking on dark theme segment: saturated bright blobs, nearest-neighbour linking.
import sys, json, subprocess, numpy as np
from collections import deque
SRC = "/root/tgdesign/research/source/IMG_6025.MP4"
S, D, STEP, OUT = float(sys.argv[1]), float(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
N = 540
cmd = ["ffmpeg", "-v", "error", "-ss", f"{S}", "-t", f"{D}", "-i", SRC, "-vf", f"select='not(mod(n\\,{STEP}))',scale={N}:{N}:flags=area", "-fps_mode", "passthrough", "-pix_fmt", "rgb24", "-f", "rawvideo", "-"]
p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
fs = N * N * 3; k = 0; frames = []
def blobs(m, minpix=60):
    H, W = m.shape; seen = np.zeros_like(m); out = []
    ys, xs = np.nonzero(m)
    for y0, x0 in zip(ys, xs):
        if seen[y0, x0]: continue
        q = deque([(y0, x0)]); seen[y0, x0] = True; pts = []
        while q:
            y, x = q.popleft(); pts.append((y, x))
            for dy, dx in ((1,0),(-1,0),(0,1),(0,-1)):
                yy, xx = y+dy, x+dx
                if 0 <= yy < H and 0 <= xx < W and m[yy, xx] and not seen[yy, xx]:
                    seen[yy, xx] = True; q.append((yy, xx))
        if len(pts) >= minpix:
            a = np.array(pts); out.append((a[:,1].mean()*2, a[:,0].mean()*2, len(pts)*4))
    return out
while True:
    b = p.stdout.read(fs)
    if len(b) < fs: break
    f = np.frombuffer(b, np.uint8).reshape(N, N, 3).astype(np.int16)
    mx = f.max(axis=2); mn = f.min(axis=2)
    sat = (mx - mn); m = (sat > 110) & (mx > 170)
    frames.append(dict(t=round(S + k * STEP / 60, 4), blobs=blobs(m)))
    k += 1
p.wait()
json.dump(frames, open(OUT, "w")); print("frames", k)
