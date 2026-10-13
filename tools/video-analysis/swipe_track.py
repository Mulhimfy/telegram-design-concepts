"""Row-swipe tracker v2: content offset from a text template (NCC), button runs, touch ring.

python -I swipe_track.py VIDEO OUT.json --n0 N --n1 N --nrest N --sx0 X --sx1 X --y0 Y --y1 Y
       --scale PXPERPT --tpl x0,y0,x1,y1 [--colors name:r,g,b;...] [--next-row y0,y1]

--tpl is a box (video px) in the REST frame around a piece of row content that stays visible and
unchanged during the swipe (e.g. the timestamp). Each frame: NCC search of that template along x
(y +-2 px) -> content offset dx (px, negative = left). Button runs: per-column median colour inside
the band, classified against reference colours, reported only right of the content edge (left
swipe). Ring: count of touch-indicator (light blue) pixels in the band.
"""
import argparse, json, subprocess
import numpy as np

ap = argparse.ArgumentParser()
ap.add_argument('video'); ap.add_argument('out')
for k in ('n0', 'n1', 'nrest', 'sx0', 'sx1', 'y0', 'y1'):
    ap.add_argument('--' + k, type=int, required=True)
ap.add_argument('--scale', type=float, required=True)
ap.add_argument('--tpl', required=True)
ap.add_argument('--colors', default='orange:245,157,45;red:252,55,40;gray:190,188,196;white:252,252,254')
ap.add_argument('--next-row', default=None)
ap.add_argument('--W', type=int, default=1080); ap.add_argument('--H', type=int, default=1080)
a = ap.parse_args()
W, H = a.W, a.H
need = set(range(a.n0, a.n1 + 1)) | {a.nrest}
p = subprocess.Popen(['ffmpeg', '-v', 'error', '-i', a.video, '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'],
                     stdout=subprocess.PIPE)
fs = W * H * 3; n = 0; frames = {}
while True:
    b = p.stdout.read(fs)
    if len(b) < fs or n > max(need):
        break
    if n in need:
        frames[n] = np.frombuffer(b, np.uint8).reshape(H, W, 3).copy()
    n += 1
p.stdout.close(); p.wait()

tx0, ty0, tx1, ty1 = [int(v) for v in a.tpl.split(',')]
rest = frames[a.nrest].astype(float)
T = rest[ty0:ty1, tx0:tx1].mean(2); T = (T - T.mean()) / (T.std() + 1e-6)
th, tw = T.shape

def find_tpl(F, prev_x):
    G = F.astype(float).mean(2)
    best = (-2, 0, 0)
    xs = range(max(a.sx0, prev_x - 80), min(a.sx1 - tw, prev_x + 40) + 1) if prev_x is not None else range(a.sx0, a.sx1 - tw + 1)
    for dy in (-2, -1, 0, 1, 2):
        rows = G[ty0 + dy:ty0 + dy + th]
        for x in xs:
            P = rows[:, x:x + tw]
            s = P.std()
            if s < 1e-3:
                continue
            c = float(((P - P.mean()) / s * T).mean())
            if c > best[0]:
                best = (c, x, dy)
    return best

cols = {}
for item in a.colors.split(';'):
    k, v = item.split(':'); cols[k] = np.array([int(t) for t in v.split(',')], float)
names = list(cols); ref = np.stack([cols[k] for k in names])
yb0, yb1 = a.y0 + 5, a.y1 - 5

def runs_of(F):
    med = np.median(F[yb0:yb1, a.sx0:a.sx1 + 1].astype(float), axis=0)
    dist = np.linalg.norm(med[:, None, :] - ref[None], axis=2)
    lab = np.where(dist.min(1) < 40, dist.argmin(1), -1)
    out = []; s = 0; L = len(lab)
    for x in range(1, L + 1):
        if x == L or lab[x] != lab[s]:
            if lab[s] >= 0 and x - s >= 3:
                out.append([names[lab[s]], s + a.sx0, x - 1 + a.sx0])
            s = x
    return out

def ring(F):
    band = F[a.y0:a.y1, a.sx0:a.sx1 + 1].astype(int)
    r, g, b = band[..., 0], band[..., 1], band[..., 2]
    return int(((b - r > 12) & (b > 200) & (r < 245) & (r > 150)).sum())

if a.next_row:
    ny0, ny1 = [int(t) for t in a.next_row.split(',')]
    NR = rest[ny0:ny1, a.sx0 + 20:a.sx1 - 20].mean(2)
def next_dy(F):
    G = F.astype(float).mean(2); best = (1e9, 0); hh = NR.shape[0]
    for dy in range(-(a.y1 - a.y0) - 12, 6):
        y = ny0 + dy
        if y < 0 or y + hh > H: continue
        m = float(np.abs(G[y:y + hh, a.sx0 + 20:a.sx1 - 20] - NR).mean())
        if m < best[0]: best = (m, dy)
    return best

res = []; prev = None
for n in range(a.n0, a.n1 + 1):
    F = frames[n]
    c, x, dy = find_tpl(F, prev)
    ok = c > 0.6
    dxp = (x - tx0) if ok else None
    if ok: prev = x
    rr = runs_of(F)
    edge = (a.sx1 + 1 + dxp) if dxp is not None else None
    if edge is not None:
        rr = [r for r in rr if r[2] >= edge - 2 and r[0] != 'white']
    rec = {'n': n, 't': round(n / 60.0, 4), 'ncc': round(c, 3), 'dx_px': dxp,
           'dx_pt': round(dxp / a.scale, 1) if dxp is not None else None,
           'runs_px': rr,
           'runs_pt_from_right': [[k, round((x0 - a.sx1 - 1) / a.scale, 1), round((x1 - a.sx1) / a.scale, 1)] for k, x0, x1 in rr],
           'ring': ring(F)}
    if a.next_row:
        m2, d2 = next_dy(F); rec['next_dy_pt'] = round(d2 / a.scale, 1); rec['next_mad'] = round(m2, 1)
    res.append(rec)
json.dump({'args': vars(a), 'frames': res}, open(a.out, 'w'), indent=1)
for r in res:
    rr = ' '.join(f"{k[0]}[{x0},{x1}]" for k, x0, x1 in r['runs_pt_from_right'])
    nd = f" next_dy={r['next_dy_pt']}" if 'next_dy_pt' in r else ''
    dx = f"{r['dx_pt']:7.1f}" if r['dx_pt'] is not None else '   None'
    print(f"n={r['n']} t={r['t']:.3f} dx={dx}pt ncc={r['ncc']:.2f} ring={r['ring']:5d}{nd} | {rr}")
