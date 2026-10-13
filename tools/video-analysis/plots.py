# Render analysis plots with PIL (no matplotlib): timeline overview, frog drag trajectories, spring fits.
import json, numpy as np, sys, os
sys.path.insert(0, os.path.dirname(__file__))
from PIL import Image, ImageDraw, ImageFont
from fit import spring
W = "/root/tgdesign/research/video/work"; OUT = "/root/tgdesign/research/video/sheets"
try:
    F = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 15); FB = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 18)
except Exception:
    F = FB = ImageFont.load_default()
BG = (18, 20, 26); FG = (230, 232, 240); GRID = (52, 56, 68); MUTED = (140, 146, 160)

# ---------- 1. timeline overview ----------
tl = np.load(f"{W}/timeline.npy"); di = np.load(f"{W}/di.npy"); fing = json.load(open(f"{W}/finger_timeline.json"))
Wd, H = 1800, 640; L, R = 70, 30
im = Image.new("RGB", (Wd, H), BG); d = ImageDraw.Draw(im)
def X(t): return L + (Wd - L - R) * t / 76.0
d.text((L, 12), "IMG_6025 (t.me/designers/266) — timeline: backdrop colour, camera zoom, touches, motion, music", font=FB, fill=FG)
# backdrop color strip
for i in range(0, len(tl), 2):
    t = tl[i, 1]; c = tuple(int(v) for v in tl[i, 3:6])
    d.line([(X(t), 50), (X(t), 90)], fill=c, width=2)
d.text((8, 62), "bg", font=F, fill=MUTED)
# zoom
y0, y1 = 110, 270
for z in [1.0, 1.33, 1.64]:
    yy = y1 - (z - 0.9) / (1.75 - 0.9) * (y1 - y0); d.line([(L, yy), (Wd - R, yy)], fill=GRID); d.text((8, yy - 8), f"{z:.2f}x", font=F, fill=MUTED)
pts = []
for i in range(0, len(di)):
    t = di[i, 1]; w = di[i, 2]
    if w > 0:
        z = w / 163.0; pts.append((X(t), y1 - (z - 0.9) / (1.75 - 0.9) * (y1 - y0)))
    else:
        if pts and len(pts) > 1: d.line(pts, fill=(120, 200, 255), width=2)
        pts = []
if len(pts) > 1: d.line(pts, fill=(120, 200, 255), width=2)
for (a, b) in [(17.9, 22.03), (29.95, 33.15), (47.38, 50.45)]:
    yy = y1 - (1.64 - 0.9) / (1.75 - 0.9) * (y1 - y0)
    d.line([(X(a), yy), (X(b), yy)], fill=(120, 200, 255), width=2)
d.text((L, y0 - 18), "camera zoom (DI width / 163 px; holds where the island is off-frame inferred at 1.64x)", font=F, fill=MUTED)
# touches
ty = 300
d.text((8, ty - 4), "touch", font=F, fill=MUTED)
for f in fing:
    zi = int(round(f["t"] * 60)); w = di[min(zi, len(di) - 1), 2]; z = w / 163.0 if w > 0 else 1.64
    if f["score"] > 55 and abs(f["r"] - 27 * z) <= 7:
        d.rectangle([X(f["t"]) - 1, ty, X(f["t"]) + 1, ty + 16], fill=(255, 170, 60))
# motion energy
my0, my1 = 340, 470
d.text((L, my0 - 18), "frame-difference motion energy (log)", font=F, fill=MUTED)
mv = np.log1p(tl[:, 2]); mv = mv / mv.max()
pts = [(X(tl[i, 1]), my1 - mv[i] * (my1 - my0)) for i in range(0, len(tl), 2)]
d.line(pts, fill=(170, 240, 170), width=1)
# audio
ay = 500
d.text((8, ay - 4), "music", font=F, fill=MUTED)
d.rectangle([X(28.6), ay, X(70.3), ay + 14], fill=(240, 90, 160))
d.text((X(28.6) + 6, ay - 1), "Stayin' Alive 103.7 BPM — dark 'party' mode, glow pulses each beat", font=F, fill=(20, 20, 20))
# chapter labels
chap = [(0, "chats"), (1.5, "chat"), (3.13, "profile (morph)"), (5.35, "chat"), (7.05, "expanded"), (9.35, "swipe"), (11.33, "profile"), (12.93, "x-fade → gifts profile"), (17.25, "drag frog"), (24.3, "expand"), (26.5, "collapse"),
        (29.6, "drag pink"), (35.07, "colour cycle 2.6 s"), (46.9, "drag gold"), (51.75, "spin swipes"), (59.2, "colour cycle"), (71.75, "swipe back"), (73.91, "pop")]
for t, s in chap:
    d.line([(X(t), 530), (X(t), 545)], fill=FG); d.text((X(t) + 2, 548 + (12 if chap.index((t, s)) % 2 else 0)), s, font=F, fill=FG)
for s in range(0, 77, 5):
    d.line([(X(s), 595), (X(s), 602)], fill=MUTED); d.text((X(s) - 8, 606), f"{s}s", font=F, fill=MUTED)
im.save(f"{OUT}/plot-timeline.png")

# ---------- 2. frog drag trajectories ----------
a = np.load(f"{W}/frog_screen.npy"); t, bx, by, fx, fy, maj, mnr = a[:, 0], a[:, 1], a[:, 2], a[:, 3], a[:, 4], a[:, 5], a[:, 6]
im = Image.new("RGB", (1400, 760), BG); d = ImageDraw.Draw(im)
d.text((20, 12), "Dragged bubble (frog, 18.1–21.6 s) vs finger — screen space, points (camera pan removed; zoom 1.64x)", font=FB, fill=FG)
def panel(x0, y0, w, h, series, title, rng):
    d.rectangle([x0, y0, x0 + w, y0 + h], outline=GRID)
    d.text((x0 + 6, y0 + 4), title, font=F, fill=MUTED)
    lo, hi = rng
    for (vals, col) in series:
        pts = [(x0 + w * (ti - t[0]) / (t[-1] - t[0]), y0 + h - h * (v - lo) / (hi - lo)) for ti, v in zip(t, vals)]
        d.line(pts, fill=col, width=2)
fxm, bxm = fx - fx.mean(), bx - bx.mean(); fym, bym = fy - fy.mean(), by - by.mean()
panel(30, 50, 1340, 200, [(fxm, (255, 170, 60)), (bxm, (120, 200, 255))], "x (pt, mean-removed): orange = finger, blue = bubble centre", (-80, 80))
panel(30, 270, 1340, 200, [(fym, (255, 170, 60)), (bym, (120, 200, 255))], "y (pt, mean-removed)", (-80, 80))
panel(30, 490, 1340, 200, [(maj / mnr, (240, 90, 160))], "aspect ratio major/minor (1.0–1.5)", (1.0, 1.5))
d.text((30, 705), f"offset bubble−finger mean ({(bx-fx).mean():.0f}, {(by-fy).mean():.0f}) pt; grabbed size {np.sqrt(maj*mnr).mean():.0f} pt; follower fit ω≈23.6 rad/s ζ≈1.2 (Telegram iOS-26 spring k=555 c=47 m=1 fits within 6 pt rms)", font=F, fill=FG)
im.save(f"{OUT}/plot-frog-drag.png")

# ---------- 3. spring fits ----------
series = {}
for fn in ["series.json", "series2.json", "series3.json", "series4.json"]:
    series.update(json.load(open(f"{W}/{fn}")))
im = Image.new("RGB", (1400, 220 * ((len(series) + 1) // 2) + 60), BG); d = ImageDraw.Draw(im)
d.text((20, 12), "Measured progress (dots) vs Telegram iOS-26 spring (mass 1, stiffness 555.027, damping 47.118 → ω 23.56, ζ 1.0) (line)", font=FB, fill=FG)
for k, (name, s) in enumerate(series.items()):
    x0 = 30 + (k % 2) * 690; y0 = 50 + (k // 2) * 220; w, h = 650, 190
    d.rectangle([x0, y0, x0 + w, y0 + h], outline=GRID); d.text((x0 + 6, y0 + 4), name, font=F, fill=MUTED)
    ts = np.array(s["t"]); ps = np.array(s["p"]); T0, T1 = ts[0] - 0.05, ts[0] + 0.6
    def XX(tt): return x0 + w * (tt - T0) / (T1 - T0)
    def YY(p): return y0 + h - 10 - (h - 30) * p
    # best t0 for the Telegram curve
    best = None
    for t0 in np.linspace(ts[0] - 0.06, ts[0] + 0.04, 101):
        pr = np.where(ts < t0, 0, spring(ts - t0, 23.56, 1.0)); e = np.sqrt(np.mean((pr - ps) ** 2))
        if best is None or e < best[0]: best = (e, t0)
    tt = np.linspace(T0, T1, 300); pr = np.where(tt < best[1], 0, spring(tt - best[1], 23.56, 1.0))
    d.line([(XX(a), YY(b)) for a, b in zip(tt, pr)], fill=(120, 200, 255), width=2)
    for a, b in zip(ts, ps): d.ellipse([XX(a) - 3, YY(b) - 3, XX(a) + 3, YY(b) + 3], fill=(255, 170, 60))
    d.text((x0 + 6, y0 + h - 24), f"rms vs TG-26 spring {best[0]:.3f}", font=F, fill=FG)
im.save(f"{OUT}/plot-spring-fits.png")
print("ok")
