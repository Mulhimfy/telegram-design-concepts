# Per-frame signals for the whole video: motion energy, background corner color, mean luma.
import sys, subprocess, numpy as np, json
src = sys.argv[1]; out = sys.argv[2]
W = H = 180
cmd = ["ffmpeg", "-v", "error", "-i", src, "-vf", f"scale={W}:{H}:flags=area", "-pix_fmt", "rgb24", "-f", "rawvideo", "-"]
p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
fs = W * H * 3
prev = None
rows = []
i = 0
while True:
    b = p.stdout.read(fs)
    if len(b) < fs:
        break
    f = np.frombuffer(b, np.uint8).reshape(H, W, 3).astype(np.float32)
    g = f.mean(axis=2)
    md = float(np.abs(g - prev).mean()) if prev is not None else 0.0
    # motion restricted to phone screen center column region (avoid background)
    corner = f[2:14, 2:14].reshape(-1, 3).mean(axis=0)  # top-left corner bg
    corner2 = f[H-14:H-2, W-14:W-2].reshape(-1, 3).mean(axis=0)
    rows.append([i, i / 60.0, md, *corner.tolist(), *corner2.tolist(), float(g.mean())])
    prev = g
    i += 1
p.wait()
np.save(out, np.array(rows, np.float32))
print("frames", i)
