# Screen-space analysis of a dragged bubble vs finger, using camera translation proxies; fits a 2D spring follower.
import json, sys, numpy as np
track = json.load(open(sys.argv[1])); cam = json.load(open(sys.argv[2]))
T0, T1 = float(sys.argv[3]), float(sys.argv[4])
S = float(sys.argv[5])  # canvas px per pt during the hold (1.727 * zoom)
camd = {r["frame"]: r for r in cam}
rows = []
for r in track:
    if not (T0 <= r["t"] <= T1): continue
    c = camd.get(r["frame"]); b = r["bubble"]; f = r["finger"]
    if not c or not b or c["bezel_x"] is None or c["card_y"] is None: continue
    bx = (b["cx"] - c["bezel_x"]) / S; by = (b["cy"] - c["card_y"]) / S
    fx = (f["x"] - c["bezel_x"]) / S; fy = (f["y"] - c["card_y"]) / S
    eqd = 2 * np.sqrt(b["area"] / np.pi) / S
    rows.append((r["t"], bx, by, fx, fy, b["major"] / S, b["minor"] / S, b["ang"], eqd, b["skew"]))
a = np.array(rows)
t, bx, by, fx, fy, maj, mnr, ang, eqd, skew = a.T
ox, oy = bx - fx, by - fy
print(f"n={len(t)}  t {t[0]:.3f}-{t[-1]:.3f}")
print(f"offset bubble-finger (pt): mean ({ox.mean():.1f},{oy.mean():.1f}) std ({ox.std():.1f},{oy.std():.1f}); |o| mean {np.hypot(ox,oy).mean():.1f}")
print(f"size: eq.diam {eqd.mean():.1f}pt (min {eqd.min():.1f} max {eqd.max():.1f}); major {maj.mean():.1f} minor {mnr.mean():.1f}; aspect mean {np.mean(maj/mnr):.3f} min {np.min(maj/mnr):.3f} max {np.max(maj/mnr):.3f}")
# velocities
dt = np.gradient(t)
vbx, vby = np.gradient(bx, t), np.gradient(by, t); vfx, vfy = np.gradient(fx, t), np.gradient(fy, t)
vb = np.hypot(vbx, vby); vf = np.hypot(vfx, vfy)
print(f"finger speed pt/s: mean {vf.mean():.0f} max {vf.max():.0f}; bubble speed mean {vb.mean():.0f} max {vb.max():.0f}")
asp = maj / mnr
print(f"corr(aspect, bubble speed) {np.corrcoef(asp, vb)[0,1]:.2f}; corr(aspect, |offset|) {np.corrcoef(asp, np.hypot(ox,oy))[0,1]:.2f}; corr(aspect, finger speed) {np.corrcoef(asp, vf)[0,1]:.2f}")
# orientation of major axis vs direction bubble->finger
dirf = np.degrees(np.arctan2(fy - by, fx - bx))
def adiff(a1, a2):
    d = (a1 - a2 + 90) % 180 - 90
    return d
print(f"major-axis vs bubble->finger direction: mean |diff| {np.mean(np.abs(adiff(ang, dirf))):.1f} deg")
dirv = np.degrees(np.arctan2(vby, vbx))
fast = vb > 150
if fast.any():
    print(f"major-axis vs velocity direction (|v|>150pt/s, n={fast.sum()}): mean |diff| {np.mean(np.abs(adiff(ang[fast], dirv[fast]))):.1f} deg")
# Fit 2D spring follower: b'' = w^2 (f + o - b) - 2 z w b'
fxi = lambda tt: np.interp(tt, t, fx); fyi = lambda tt: np.interp(tt, t, fy)
def sim(w, z, ox0, oy0):
    h = 1 / 240.0
    px, py = bx[0], by[0]; vx, vy = vbx[0], vby[0]
    out = []; tt = t[0]; j = 0
    res = np.zeros((len(t), 2))
    for i in range(len(t)):
        while tt < t[i] - 1e-9:
            ax = w * w * (fxi(tt) + ox0 - px) - 2 * z * w * vx
            ay = w * w * (fyi(tt) + oy0 - py) - 2 * z * w * vy
            vx += ax * h; vy += ay * h; px += vx * h; py += vy * h; tt += h
        res[i] = (px, py)
    return res
best = None
for w in np.linspace(4, 40, 37):
    for z in [0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.2, 1.5]:
        # offset: least squares approx -> use mean offset as starting guess, refine on small grid
        for dox in np.linspace(-15, 15, 7):
            for doy in np.linspace(-15, 15, 7):
                o = (ox.mean() + dox, oy.mean() + doy)
                r = sim(w, z, *o)
                e = np.sqrt(np.mean((r[:, 0] - bx) ** 2 + (r[:, 1] - by) ** 2))
                if best is None or e < best[0]: best = (e, w, z, o)
e, w, z, o = best
print(f"spring follower fit: omega {w:.1f} rad/s (response {2*np.pi/w:.3f}s), zeta {z}, offset ({o[0]:.1f},{o[1]:.1f}) pt, rms err {e:.1f} pt")
# lag via cross-correlation of velocities
def lag(sig_a, sig_b):
    best = None
    for L in range(0, 30):
        if L >= len(sig_a) - 5: break
        c = np.corrcoef(sig_a[:len(sig_a)-L], sig_b[L:])[0, 1]
        if best is None or c > best[1]: best = (L, c)
    return best
lx = lag(vfx, vbx); ly = lag(vfy, vby)
print(f"velocity xcorr lag: x {lx[0]} frames ({lx[0]/60*1000:.0f} ms, r={lx[1]:.2f}); y {ly[0]} frames ({ly[0]/60*1000:.0f} ms, r={ly[1]:.2f})")
amp = lambda s: (np.percentile(s, 95) - np.percentile(s, 5))
print(f"amplitude ratio bubble/finger: x {amp(bx)/amp(fx):.2f} y {amp(by)/amp(fy):.2f}")
np.save(sys.argv[6], a)
