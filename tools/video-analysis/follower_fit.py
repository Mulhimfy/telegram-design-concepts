# Refit follower with gain: target = k*finger + c (per axis), spring (w, z). Input: npy from drag_analysis.
import sys, numpy as np
a = np.load(sys.argv[1]); t, bx, by, fx, fy = a[:, 0], a[:, 1], a[:, 2], a[:, 3], a[:, 4]
vbx0, vby0 = np.gradient(bx, t)[0], np.gradient(by, t)[0]
def sim(w, z, kx, ky, cx, cy):
    h = 1 / 240.0; px, py = bx[0], by[0]; vx, vy = vbx0, vby0; tt = t[0]; res = np.zeros((len(t), 2))
    for i in range(len(t)):
        while tt < t[i] - 1e-9:
            txx = kx * np.interp(tt, t, fx) + cx; tyy = ky * np.interp(tt, t, fy) + cy
            ax = w * w * (txx - px) - 2 * z * w * vx; ay = w * w * (tyy - py) - 2 * z * w * vy
            vx += ax * h; vy += ay * h; px += vx * h; py += vy * h; tt += h
        res[i] = (px, py)
    return res
best = None
for w in [12, 15, 18, 21, 23.56, 26, 30, 35]:
    for z in [0.6, 0.8, 1.0, 1.2, 1.5, 2.0]:
        for kx in [0.5, 0.6, 0.7, 0.8, 0.9, 1.0]:
            for ky in [0.7, 0.8, 0.9, 1.0]:
                # c solved approximately: make mean target match mean bubble
                cx = bx.mean() - kx * fx.mean(); cy = by.mean() - ky * fy.mean()
                r = sim(w, z, kx, ky, cx, cy)
                e = np.sqrt(np.mean((r[:, 0] - bx) ** 2 + (r[:, 1] - by) ** 2))
                if best is None or e < best[0]: best = (e, w, z, kx, ky)
print("best (rms, omega, zeta, kx, ky):", [round(float(v), 3) for v in best])
for z in [1.0]:
    for w in [23.56]:
        r = sim(w, z, 1.0, 1.0, bx.mean() - fx.mean(), by.mean() - fy.mean())
        print("telegram-26 spring, k=1:", round(float(np.sqrt(np.mean((r[:, 0] - bx) ** 2 + (r[:, 1] - by) ** 2))), 2))
