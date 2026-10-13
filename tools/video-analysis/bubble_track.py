# Track a dragged glass bubble (color mask, hole-filled) and the touch-indicator ring per frame.
# usage: bubble_track.py START DUR KIND OUT.json   KIND in frog|pink|gold
import sys, json, subprocess, numpy as np
SRC = "/root/tgdesign/research/source/IMG_6025.MP4"
S = float(sys.argv[1]); D = float(sys.argv[2]); KIND = sys.argv[3]; OUT = sys.argv[4]
N = 540  # half resolution processing
cmd = ["ffmpeg", "-v", "error", "-ss", f"{S}", "-t", f"{D}", "-i", SRC, "-vf", f"scale={N}:{N}:flags=area", "-pix_fmt", "rgb24", "-f", "rawvideo", "-"]
p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
fs = N * N * 3

def mask_for(f):
    R, G, B = f[..., 0], f[..., 1], f[..., 2]
    if KIND == "frog":
        return ((R - G) < 40) & (B > 170) & (R < 135)
    if KIND == "pink":
        return (R > 210) & (G < 140) & (B > 140)
    if KIND == "gold":
        return (R > 215) & (G > 130) & (B < 130)
    raise SystemExit("kind")

def label_largest(m):
    # two-pass-free BFS labelling restricted to the mask (numpy + python deque; mask is small enough at 540^2)
    from collections import deque
    H, W = m.shape
    seen = np.zeros_like(m, dtype=bool)
    best = None
    ys, xs = np.nonzero(m)
    for y0, x0 in zip(ys[::5], xs[::5]):
        if seen[y0, x0]: continue
        q = deque([(y0, x0)]); seen[y0, x0] = True; pts = []
        while q:
            y, x = q.popleft(); pts.append(y * W + x)
            if y > 0 and m[y-1, x] and not seen[y-1, x]: seen[y-1, x] = True; q.append((y-1, x))
            if y < H-1 and m[y+1, x] and not seen[y+1, x]: seen[y+1, x] = True; q.append((y+1, x))
            if x > 0 and m[y, x-1] and not seen[y, x-1]: seen[y, x-1] = True; q.append((y, x-1))
            if x < W-1 and m[y, x+1] and not seen[y, x+1]: seen[y, x+1] = True; q.append((y, x+1))
        if best is None or len(pts) > len(best): best = pts
    out = np.zeros(m.shape, bool)
    if best: out.flat[np.array(best)] = True
    return out

def fill_holes(m):
    # holes = background components not connected to the border -> fill using row/col scan approximation (convex-ish shapes)
    out = m.copy()
    H, W = m.shape
    rows = np.where(m.any(axis=1))[0]
    for y in rows:
        xs = np.where(m[y])[0]; out[y, xs.min():xs.max()+1] = True
    cols = np.where(out.any(axis=0))[0]
    out2 = out.copy()
    for x in cols:
        ys = np.where(out[:, x])[0]; out2[ys.min():ys.max()+1, x] = True
    return out2 & out  # intersection keeps it tight for convex shapes

def moments(m):
    ys, xs = np.nonzero(m)
    if len(xs) < 30: return None
    cx, cy = xs.mean(), ys.mean()
    cov = np.cov(np.stack([xs - cx, ys - cy]))
    ev, evec = np.linalg.eigh(cov)
    major = 4 * np.sqrt(ev[1]); minor = 4 * np.sqrt(ev[0])
    ang = np.degrees(np.arctan2(evec[1, 1], evec[0, 1]))  # angle of major axis vs +x (y down)
    # asymmetry along major axis (egg shape): third moment sign
    v = np.stack([xs - cx, ys - cy])
    proj = evec[:, 1] @ v
    skew = float((proj ** 3).mean() / (proj.std() ** 3 + 1e-9))
    return dict(cx=float(cx * 2), cy=float(cy * 2), area=int(len(xs) * 4), major=float(major * 2), minor=float(minor * 2), ang=float(ang), skew=skew,
                x0=int(xs.min() * 2), x1=int(xs.max() * 2), y0=int(ys.min() * 2), y1=int(ys.max() * 2))

# ring detector kernels (luminance): bright thin ring with darker interior
def kernels(shape, radii):
    H, W = shape
    yy, xx = np.mgrid[0:H, 0:W]
    yy = np.where(yy > H // 2, yy - H, yy); xx = np.where(xx > W // 2, xx - W, xx)
    rr = np.sqrt(yy ** 2 + xx ** 2)
    ks = []
    for r in radii:
        ring = (np.abs(rr - r) < 0.9).astype(np.float32); ring /= ring.sum()
        inner = (rr < r - 2.5).astype(np.float32); inner /= inner.sum()
        outer = ((rr > r + 2.0) & (rr < r + 5.0)).astype(np.float32); outer /= outer.sum()
        k = ring - 0.5 * inner - 0.5 * outer
        ks.append(np.fft.rfft2(k))
    return ks
RADII = list(range(12, 30))
KS = None
rows = []
k = 0
f0 = round(S * 60)
while True:
    b = p.stdout.read(fs)
    if len(b) < fs: break
    f = np.frombuffer(b, np.uint8).reshape(N, N, 3).astype(np.int16)
    m = mask_for(f)
    m = label_largest(m)
    m = fill_holes(m)
    st = moments(m)
    L = (0.2126 * f[..., 0] + 0.7152 * f[..., 1] + 0.0722 * f[..., 2]).astype(np.float32)
    if KS is None: KS = kernels(L.shape, RADII)
    FL = np.fft.rfft2(L)
    best = None
    for r, K in zip(RADII, KS):
        resp = np.fft.irfft2(FL * K, s=L.shape)
        i = int(np.argmax(resp)); y, x = divmod(i, N)
        v = float(resp[y, x])
        if best is None or v > best[0]: best = (v, x * 2, y * 2, r * 2)
    rows.append(dict(frame=f0 + k, t=round((f0 + k) / 60, 4), bubble=st, finger=dict(score=round(best[0], 2), x=best[1], y=best[2], r=best[3])))
    k += 1
p.wait()
json.dump(rows, open(OUT, "w"))
print("frames", k)
