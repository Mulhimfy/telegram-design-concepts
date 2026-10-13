# Estimate camera translation per frame vs a reference frame using phase correlation on a static crop.
# usage: camera_shift.py START DUR REF_T X0 Y0 X1 Y1 OUT.json  (crop in full-res canvas coords)
import sys, json, subprocess, numpy as np
SRC = "/root/tgdesign/research/source/IMG_6025.MP4"
S, D, REF = float(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3])
X0, Y0, X1, Y1 = map(int, sys.argv[4:8]); OUT = sys.argv[8]
cmd = ["ffmpeg", "-v", "error", "-ss", f"{S}", "-t", f"{D}", "-i", SRC, "-vf", "format=gray", "-f", "rawvideo", "-"]
p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
N = 1080; fs = N * N
frames = []
while True:
    b = p.stdout.read(fs)
    if len(b) < fs: break
    g = np.frombuffer(b, np.uint8).reshape(N, N)[Y0:Y1, X0:X1].astype(np.float32)
    frames.append(g)
p.wait()
f0 = round(S * 60)
ri = round(REF * 60) - f0
win = np.outer(np.hanning(Y1 - Y0), np.hanning(X1 - X0)).astype(np.float32)
def pc(a, b):
    A = np.fft.fft2((a - a.mean()) * win); B = np.fft.fft2((b - b.mean()) * win)
    R = A * np.conj(B); R /= np.abs(R) + 1e-6
    r = np.fft.ifft2(R).real
    i = int(np.argmax(r)); y, x = divmod(i, r.shape[1])
    # subpixel via parabola
    def sub(v, idx, n):
        l = v[(idx - 1) % n]; c = v[idx]; rr = v[(idx + 1) % n]
        d = (l - rr) / (2 * (l - 2 * c + rr) + 1e-9); return d
    dy = sub(r[:, x], y, r.shape[0]); dx = sub(r[y, :], x, r.shape[1])
    y = y + dy; x = x + dx
    if y > r.shape[0] / 2: y -= r.shape[0]
    if x > r.shape[1] / 2: x -= r.shape[1]
    return float(x), float(y), float(r.max())
out = []
for k, g in enumerate(frames):
    dx, dy, q = pc(g, frames[ri])
    out.append(dict(frame=f0 + k, t=round((f0 + k) / 60, 4), dx=round(dx, 2), dy=round(dy, 2), q=round(q, 3)))
json.dump(out, open(OUT, "w"))
print("frames", len(out))
