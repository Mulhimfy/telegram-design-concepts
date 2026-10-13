# Track the Dynamic Island pill (camera zoom/pan proxy) over the whole video at half resolution.
import subprocess, numpy as np, sys
SRC = "/root/tgdesign/research/source/IMG_6025.MP4"
N = 540
cmd = ["ffmpeg", "-v", "error", "-i", SRC, "-vf", f"scale={N}:{N}:flags=area,format=gray", "-f", "rawvideo", "-"]
p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
fs = N * N
out = []
k = 0
from collections import deque
while True:
    b = p.stdout.read(fs)
    if len(b) < fs: break
    g = np.frombuffer(b, np.uint8).reshape(N, N)
    res = None
    m = g < 14
    # search rows in the top 45% for the widest run of dark pixels that is NOT touching left/right borders
    cands = []
    for y in range(4, int(N * 0.45), 2):
        row = m[y]
        d = np.diff(np.concatenate([[0], row.astype(np.int8), [0]]))
        starts = np.where(d == 1)[0]; ends = np.where(d == -1)[0]
        for s, e in zip(starts, ends):
            w = e - s
            if 30 <= w <= 300 and s > 20 and e < N - 20 and abs((s + e) / 2 - N / 2) < N * 0.35:
                x = (s + e) // 2
                y0 = y; y1 = y
                while y0 > 0 and m[y0-1, x]: y0 -= 1
                while y1 < N-1 and m[y1+1, x]: y1 += 1
                h = y1 - y0 + 1
                if 1.8 < w / max(h, 1) < 3.6 and h >= 10:
                    cands.append((w * h, w, h, s, e, y0, y1))
    if cands:
        _, w, h, s, e, y0, y1 = max(cands)
        res = (w*2, h*2, (s+e), (y0+y1+1))
    out.append((k, k/60, *(res if res else (-1, -1, -1, -1))))
    k += 1
p.wait()
np.save(sys.argv[1], np.array(out, np.float32))
print("frames", k)
