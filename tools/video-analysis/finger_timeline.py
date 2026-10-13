# Coarse touch-indicator timeline over the whole video (ring detector on half-res luminance).
import sys, json, subprocess, numpy as np
SRC = "/root/tgdesign/research/source/IMG_6025.MP4"
STEP = int(sys.argv[1]); OUT = sys.argv[2]
N = 540
cmd = ["ffmpeg", "-v", "error", "-i", SRC, "-vf", f"select='not(mod(n\\,{STEP}))',scale={N}:{N}:flags=area,format=gray", "-fps_mode", "passthrough", "-f", "rawvideo", "-"]
p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
H = W = N
yy, xx = np.mgrid[0:H, 0:W]
yy = np.where(yy > H // 2, yy - H, yy); xx = np.where(xx > W // 2, xx - W, xx)
rr = np.sqrt(yy ** 2 + xx ** 2)
RADII = list(range(12, 25))
KS = []
for r in RADII:
    ring = (np.abs(rr - r) < 0.9).astype(np.float32); ring /= ring.sum()
    inner = (rr < r - 2.5).astype(np.float32); inner /= inner.sum()
    outer = ((rr > r + 2.0) & (rr < r + 5.0)).astype(np.float32); outer /= outer.sum()
    KS.append(np.fft.rfft2(ring - 0.5 * inner - 0.5 * outer))
out = []; k = 0
while True:
    b = p.stdout.read(N * N)
    if len(b) < N * N: break
    L = np.frombuffer(b, np.uint8).reshape(N, N).astype(np.float32)
    FL = np.fft.rfft2(L); best = None
    for r, K in zip(RADII, KS):
        resp = np.fft.irfft2(FL * K, s=L.shape)
        i = int(np.argmax(resp)); y, x = divmod(i, N); v = float(resp[y, x])
        if best is None or v > best[0]: best = (v, x * 2, y * 2, r * 2)
    out.append(dict(t=round(k * STEP / 60, 3), score=round(best[0], 1), x=best[1], y=best[2], r=best[3]))
    k += 1
p.wait()
json.dump(out, open(OUT, "w")); print("samples", k)
