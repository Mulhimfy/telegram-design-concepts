# Camera pan proxy: left bezel inner edge (x) + info-card top edge (y) per frame.
import sys, subprocess, numpy as np, json
SRC = "/root/tgdesign/research/source/IMG_6025.MP4"
S, D, OUT = float(sys.argv[1]), float(sys.argv[2]), sys.argv[3]
YMIN = int(sys.argv[4]) if len(sys.argv) > 4 else 500
cmd = ["ffmpeg", "-v", "error", "-ss", f"{S}", "-t", f"{D}", "-i", SRC, "-vf", "format=gray", "-f", "rawvideo", "-"]
p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
N = 1080; fs = N * N; k = 0; f0 = round(S * 60); out = []
while True:
    b = p.stdout.read(fs)
    if len(b) < fs: break
    g = np.frombuffer(b, np.uint8).reshape(N, N).astype(np.float32)
    xs = []
    for y in range(300, 1060, 20):
        r = g[y, :400]
        dark = np.where(r < 25)[0]
        if len(dark) == 0: continue
        runs = np.split(dark, np.where(np.diff(dark) != 1)[0] + 1)
        run = runs[0]
        if 8 <= len(run) <= 120 and run[-1] + 3 < 400 and r[run[-1] + 3] > 50:
            xs.append(run[-1] + 0.5)
    bx = float(np.median(xs)) if xs else None
    cy = None
    if bx is not None:
        a = int(bx + 15); c = int(bx + 70)
        prof = g[:, a:c].mean(axis=1)
        prof = np.convolve(prof, np.ones(3) / 3, mode="same")
        d = prof[YMIN + 2:1076] - prof[YMIN:1074]
        i = int(np.argmax(np.abs(d))) if '--abs' in sys.argv else int(np.argmin(d)); cy = float(YMIN + i + 1)
        step = float(d[i])
    out.append(dict(frame=f0 + k, t=round((f0 + k) / 60, 4), bezel_x=bx, card_y=cy))
    k += 1
p.wait()
json.dump(out, open(OUT, "w")); print("frames", k)
