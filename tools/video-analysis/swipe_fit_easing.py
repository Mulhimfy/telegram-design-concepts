"""Fit named easing curves (start time + duration) to a measured 1-D motion.

python -I fitcurve.py TRACK.json KEY N0 N1 Y_FROM Y_TO
"""
import json, sys
import numpy as np

U = np.linspace(0, 1, 4001)

def bez(x1, y1, x2, y2):
    s = np.linspace(0, 1, 20001)
    xs = 3 * (1 - s) ** 2 * s * x1 + 3 * (1 - s) * s ** 2 * x2 + s ** 3
    ys = 3 * (1 - s) ** 2 * s * y1 + 3 * (1 - s) * s ** 2 * y2 + s ** 3
    return np.interp(U, xs, ys)

def crit(w=9.233):
    return 1 - (1 + w * U) * np.exp(-w * U)

def fit(ts, p, table):
    best = (1e9, 0.0, 0.0)
    for D in np.arange(0.15, 0.60, 0.005):
        for t0 in np.arange(ts[0] - 0.06, ts[0] + 0.03, 0.002):
            u = np.clip((ts - t0) / D, 0, 1)
            q = np.interp(u, U, table)
            e = float(np.sqrt(np.mean((q - p) ** 2)))
            if e < best[0]:
                best = (e, t0, D)
    return best

d = json.load(open(sys.argv[1])); key = sys.argv[2]
n0, n1 = int(sys.argv[3]), int(sys.argv[4]); y0, y1 = float(sys.argv[5]), float(sys.argv[6])
fr = [f for f in d['frames'] if n0 <= f['n'] <= n1 and f.get(key) is not None]
ts = np.array([f['n'] / 60.0 for f in fr]); p = (np.array([f[key] for f in fr]) - y0) / (y1 - y0)
curves = {'easeInOut(.42,0,.58,1)': bez(.42, 0, .58, 1), 'ease(.25,.1,.25,1)': bez(.25, .1, .25, 1),
          'easeOut(0,0,.58,1)': bez(0, 0, .58, 1), 'tg .spring bezier(.38,.7,.125,1)': bez(.38, .7, .125, 1),
          'easeIn(.42,0,1,1)': bez(.42, 0, 1, 1), 'linear': U.copy(), 'crit-damped from rest': crit()}
for k, c in curves.items():
    e, t0, D = fit(ts, p, c)
    print(f'{k:34s} rms={e * abs(y1 - y0):5.2f}pt  start={t0:.3f}s dur={D:.3f}s')
