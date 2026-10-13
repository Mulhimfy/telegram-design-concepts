# Side-by-side / split / difference comparison between a reference screenshot and a replica render.
# usage: .venv-img/bin/python -I tools/compare.py REF.jpg REPLICA.png OUTPREFIX [--crop x0,y0,x1,y1] [--zoom 2]
import sys
from PIL import Image, ImageChops, ImageDraw, ImageFont

ref_path, rep_path, out = sys.argv[1], sys.argv[2], sys.argv[3]
crop = None
zoom = 1.0
args = sys.argv[4:]
for i, a in enumerate(args):
    if a == '--crop':
        crop = tuple(int(v) for v in args[i + 1].split(','))
    if a == '--zoom':
        zoom = float(args[i + 1])

ref = Image.open(ref_path).convert('RGB')
rep = Image.open(rep_path).convert('RGB').resize(ref.size, Image.LANCZOS)
if crop:
    ref = ref.crop(crop)
    rep = rep.crop(crop)
if zoom != 1.0:
    size = (round(ref.width * zoom), round(ref.height * zoom))
    ref = ref.resize(size, Image.LANCZOS)
    rep = rep.resize(size, Image.LANCZOS)

w, h = ref.size
side = Image.new('RGB', (w * 2 + 12, h + 28), (40, 40, 40))
side.paste(ref, (0, 28))
side.paste(rep, (w + 12, 28))
d = ImageDraw.Draw(side)
d.text((8, 6), 'TELEGRAM (real)', fill=(255, 220, 80))
d.text((w + 20, 6), 'REPLICA', fill=(120, 220, 255))
side.save(out + '-side.png')

split = ref.copy()
split.paste(rep.crop((w // 2, 0, w, h)), (w // 2, 0))
ImageDraw.Draw(split).line([(w // 2, 0), (w // 2, h)], fill=(255, 0, 255), width=1)
split.save(out + '-split.png')

diff = ImageChops.difference(ref, rep).convert('L').point(lambda v: min(255, v * 4))
diff.save(out + '-diff.png')
print('saved', out + '-side.png', out + '-split.png', out + '-diff.png')
