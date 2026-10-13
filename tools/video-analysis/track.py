# Generic per-frame tracker over a time segment (half-res 540x540).
# usage: track.py START DUR MODE [args]
import sys, subprocess, numpy as np
SRC = "/root/tgdesign/research/source/IMG_6025.MP4"
S = float(sys.argv[1]); D = float(sys.argv[2]); MODE = sys.argv[3]
N = 540
cmd = ["ffmpeg", "-v", "error", "-ss", f"{S}", "-t", f"{D}", "-i", SRC, "-vf", f"scale={N}:{N}:flags=area", "-pix_fmt", "rgb24", "-f", "rawvideo", "-"]
p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
fs = N * N * 3
frames = []
while True:
    b = p.stdout.read(fs)
    if len(b) < fs: break
    frames.append(np.frombuffer(b, np.uint8).reshape(N, N, 3).astype(np.int16))
p.wait()
# Input seeking snaps to the frame at/after S; assume frame k at S + k/60 (rounded to frame grid)
f0 = round(S * 60)
def largest_blob_stats(mask):
    ys, xs = np.nonzero(mask)
    if len(xs) < 20: return None
    # crude largest-component via histogram clustering: use connected components with BFS on downsampled grid
    from collections import deque
    m = mask
    H, W = m.shape
    lab = np.zeros(m.shape, np.int32); best = None; cur = 0
    for y0, x0 in zip(ys[::7], xs[::7]):
        if lab[y0, x0]: continue
        cur += 1; q = deque([(y0, x0)]); lab[y0, x0] = cur; pts = []
        while q:
            y, x = q.popleft(); pts.append((y, x))
            for dy, dx in ((1,0),(-1,0),(0,1),(0,-1)):
                yy, xx = y+dy, x+dx
                if 0 <= yy < H and 0 <= xx < W and m[yy, xx] and not lab[yy, xx]:
                    lab[yy, xx] = cur; q.append((yy, xx))
        if best is None or len(pts) > len(best): best = pts
    a = np.array(best, np.float64)
    cy, cx = a[:,0].mean(), a[:,1].mean()
    cov = np.cov(np.stack([a[:,1]-cx, a[:,0]-cy]))
    ev, evec = np.linalg.eigh(cov)
    major = 4*np.sqrt(max(ev[1],1e-9)); minor = 4*np.sqrt(max(ev[0],1e-9))  # full axes of equivalent ellipse
    ang = np.degrees(np.arctan2(evec[1,1], evec[0,1]))
    return dict(cx=cx, cy=cy, area=len(best), major=major, minor=minor, ang=ang,
                x0=a[:,1].min(), x1=a[:,1].max(), y0=a[:,0].min(), y1=a[:,0].max())
out = []
if MODE in ("lightcard", "lightcard_rev"):
    ref = frames[0] if MODE == "lightcard" else frames[-1]
    for k, f in enumerate(frames):
        lum = f.mean(axis=2)
        changed = np.abs(f - ref).sum(axis=2) > 60
        light = (lum > 200)
        m = changed & light
        m[:, :96] = False; m[:, 444:] = False  # screen x range (half-res 96..443)
        ys, xs = np.nonzero(m)
        cy = (f[...,1] > 150) & (f[...,2] > 170) & (f[...,0] < 90)
        st = largest_blob_stats(cy)
        if len(xs) > 50:
            row = (f0+k, (f0+k)/60, xs.min()*2, xs.max()*2, ys.min()*2, ys.max()*2, len(xs)*4)
        else:
            row = (f0+k, (f0+k)/60, -1, -1, -1, -1, 0)
        cyan = (st['cx']*2, st['cy']*2, st['area']*4) if st else (-1, -1, 0)
        print("%5d %7.3f bbox x%4d-%4d y%4d-%4d area%7d | cyan c(%6.1f,%6.1f) a%6d" % (row + cyan))
elif MODE == "color":
    # args: r g b tol  -> stats of the largest blob of that color
    R, G, B, T = map(int, sys.argv[4:8])
    for k, f in enumerate(frames):
        m = (np.abs(f[...,0]-R) < T) & (np.abs(f[...,1]-G) < T) & (np.abs(f[...,2]-B) < T)
        st = largest_blob_stats(m)
        if st:
            print("%5d %7.3f c(%6.1f,%6.1f) area%7d major%6.1f minor%6.1f ang%6.1f bbox x%4d-%4d y%4d-%4d" % (f0+k, (f0+k)/60, st['cx']*2, st['cy']*2, st['area']*4, st['major']*2, st['minor']*2, st['ang'], st['x0']*2, st['x1']*2, st['y0']*2, st['y1']*2))
        else:
            print("%5d %7.3f none" % (f0+k, (f0+k)/60))
