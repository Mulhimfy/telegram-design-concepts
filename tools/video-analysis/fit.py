# Fit damped-spring step responses to normalized progress series (vectorized grid search).
import numpy as np, json, sys
def spring(t, w, z, v0=0.0):
    t = np.maximum(t, 0)
    if abs(z - 1) < 1e-6:
        return 1 - np.exp(-w * t) * (1 + (w - v0) * t)
    if z < 1:
        wd = w * np.sqrt(1 - z * z)
        return 1 - np.exp(-z * w * t) * (np.cos(wd * t) + (z * w - v0) / wd * np.sin(wd * t))
    s = np.sqrt(z * z - 1); r1 = -w * (z - s); r2 = -w * (z + s)
    b = (v0 + r1) / (r2 - r1); a = -1 - b
    return 1 + a * np.exp(r1 * t) + b * np.exp(r2 * t)
def fit(ts, ps, zs=None, name="", v0=0.0):
    ts = np.asarray(ts, float); ps = np.asarray(ps, float)
    W = np.linspace(4, 70, 331)[:, None, None]
    T0 = np.linspace(ts[0] - 0.06, ts[0] + 0.06, 121)[None, :, None]
    zlist = np.concatenate([np.linspace(0.25, 0.99, 38), [1.0], np.linspace(1.1, 4.0, 30)]) if zs is None else np.asarray(zs, float)
    best = None
    for z in zlist:
        tt = ts[None, None, :] - T0
        pr = np.where(tt < 0, 0.0, spring(tt, W, z, v0))
        e = np.sqrt(((pr - ps[None, None, :]) ** 2).mean(axis=2))
        i, j = np.unravel_index(np.argmin(e), e.shape)
        if best is None or e[i, j] < best[0]:
            best = (e[i, j], W[i, 0, 0], z, T0[0, j, 0])
    e, w, z, t0 = best
    tt = np.linspace(0, 3, 30001); x = spring(tt, w, z, v0)
    idx = np.where(np.abs(x - 1) > 0.02)[0]; settle = tt[idx[-1] + 1] if len(idx) else 0.0
    idx99 = np.where(np.abs(x - 1) > 0.005)[0]; settle05 = tt[idx99[-1] + 1] if len(idx99) else 0.0
    return dict(name=name, rms=round(float(e), 4), omega=round(float(w), 2), zeta=round(float(z), 3), t0=round(float(t0), 4),
                response_s=round(2 * np.pi / w, 3), settle2pct_s=round(float(settle), 3), settle0_5pct_s=round(float(settle05), 3),
                overshoot=round(float(max(0, x.max() - 1)), 3), stiffness_m1=round(float(w * w), 1), damping_m1=round(float(2 * z * w), 2))
if __name__ == "__main__":
    d = json.load(open(sys.argv[1]))
    for name, ser in d.items():
        print(json.dumps(fit(ser["t"], ser["p"], name=name)))
        print(json.dumps(fit(ser["t"], ser["p"], zs=[1.0], name=name + " [z=1]")))
