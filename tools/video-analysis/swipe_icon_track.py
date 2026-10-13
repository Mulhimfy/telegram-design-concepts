"""Icon animation tracker inside a moving button (per-frame x-range from swipe_track JSON).

python -I icon_dyn.py VIDEO TRACK.json --color red --y0 Y --y1 Y [--thr 225] [--nref N] [--merge-same]
Uses, per frame, the union of that colour's runs (video px) as the horizontal search range.
Prints bbox size (px), centre, ink, and the shape difference vs the reference frame (bbox-centred).
"""
import argparse, json, subprocess
import numpy as np
ap = argparse.ArgumentParser()
ap.add_argument('video'); ap.add_argument('track')
ap.add_argument('--color', required=True)
ap.add_argument('--y0', type=int, required=True); ap.add_argument('--y1', type=int, required=True)
ap.add_argument('--thr', type=int, default=225); ap.add_argument('--nref', type=int, default=None)
ap.add_argument('--box', type=int, default=90)
ap.add_argument('--W', type=int, default=1080); ap.add_argument('--H', type=int, default=1080)
a = ap.parse_args()
tr = json.load(open(a.track))['frames']
rng = {}
for f in tr:
    rr = [r for r in f['runs_px'] if r[0] == a.color]
    if rr:
        rng[f['n']] = (min(r[1] for r in rr) + 2, max(r[2] for r in rr) - 2)
ns = sorted(rng)
p = subprocess.Popen(['ffmpeg', '-v', 'error', '-i', a.video, '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'], stdout=subprocess.PIPE)
fs = a.W * a.H * 3; n = 0; crops = {}
while True:
    b = p.stdout.read(fs)
    if len(b) < fs or n > ns[-1]: break
    if n in rng:
        x0, x1 = rng[n]
        crops[n] = (x0, np.frombuffer(b, np.uint8).reshape(a.H, a.W, 3)[a.y0:a.y1, x0:x1 + 1].astype(int))
    n += 1
p.stdout.close(); p.wait()
def shape(x0, F):
    m = F.min(2) > a.thr
    ys, xs = np.nonzero(m)
    if len(xs) < 6: return None
    cy = (ys.min() + ys.max()) / 2; cx = (xs.min() + xs.max()) / 2; hb = a.box // 2
    out = np.zeros((a.box, a.box), bool)
    yy = np.round(ys - cy).astype(int) + hb; xx = np.round(xs - cx).astype(int) + hb
    ok = (yy >= 0) & (yy < a.box) & (xx >= 0) & (xx < a.box)
    out[yy[ok], xx[ok]] = True
    return out, (xs.min() + x0, xs.max() + x0, ys.min() + a.y0, ys.max() + a.y0), len(xs)
nref = a.nref if a.nref is not None else max(crops)
ref = shape(*crops[nref])
for k in sorted(crops):
    s = shape(*crops[k])
    if s is None:
        print(f'n={k} t={k/60:.3f} range={rng[k]} no icon'); continue
    m, (bx0, bx1, by0, by1), ink = s
    d = float((m ^ ref[0]).sum()) / max(1, ref[0].sum())
    print(f'n={k} t={k/60:.3f} range={rng[k]} bbox {bx1-bx0+1}x{by1-by0+1}px centre=({(bx0+bx1)/2:.1f},{(by0+by1)/2:.1f}) ink={ink:4d} diff_vs_n{nref}={d:.3f}')
