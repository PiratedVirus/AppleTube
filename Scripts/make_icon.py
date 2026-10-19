#!/usr/bin/env python3
"""Draw the AppleTube app icon (1024x1024): white beamed note on a red→coral gradient.
Usage: python3 -I Scripts/make_icon.py <out.png>"""
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 4096  # supersample, then downscale for smooth edges
img = Image.new("RGB", (S, S))
top, bottom = (255, 94, 108), (214, 16, 52)   # coral → deep red
px = img.load()
for y in range(S):
    t = y / (S - 1)
    row = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    for x in range(S):
        px[x, y] = row
# soft highlight in the upper-left
glow = Image.new("L", (S, S), 0)
ImageDraw.Draw(glow).ellipse((-S * 0.3, -S * 0.4, S * 0.9, S * 0.6), fill=45)
glow = glow.filter(ImageFilter.GaussianBlur(S * 0.12))
img = Image.composite(Image.new("RGB", (S, S), (255, 255, 255)), img, glow)

note = Image.new("L", (S, S), 0)
d = ImageDraw.Draw(note)
u = S / 1024
stem_w = 52 * u
lx, rx = 330 * u, 690 * u           # stems' right edges
top_l, top_r = 300 * u, 240 * u      # beam slopes up to the right
bottom_y = 700 * u
d.polygon([(lx - stem_w, top_l), (rx, top_r), (rx, top_r + 120 * u), (lx - stem_w, top_l + 120 * u)], fill=255)  # beam
d.rectangle((lx - stem_w, top_l + 60 * u, lx, bottom_y), fill=255)
d.rectangle((rx - stem_w, top_r + 60 * u, rx, bottom_y - 60 * u), fill=255)
def head(cx, cy):
    rw, rh = 104 * u, 78 * u
    tmp = Image.new("L", (S, S), 0)
    ImageDraw.Draw(tmp).ellipse((cx - rw, cy - rh, cx + rw, cy + rh), fill=255)
    return tmp.rotate(22, center=(cx, cy), resample=Image.BICUBIC)
for cx, cy in ((lx - 92 * u, bottom_y + 8 * u), (rx - 92 * u, bottom_y - 52 * u)):
    note = Image.composite(Image.new("L", (S, S), 255), note, head(cx, cy))
# Scale to ~58% of the canvas and centre by bounding box (nudged up slightly for optical balance).
box = note.getbbox()
w, h = box[2] - box[0], box[3] - box[1]
k = S * 0.58 / max(w, h)
note = note.crop(box).resize((int(w * k), int(h * k)), Image.LANCZOS)
canvas = Image.new("L", (S, S), 0)
canvas.paste(note, ((S - note.width) // 2, (S - note.height) // 2 - int(14 * u)))
note = canvas
shadow = note.filter(ImageFilter.GaussianBlur(24 * u)).point(lambda v: v * 0.25)
img = Image.composite(Image.new("RGB", (S, S), (120, 0, 20)), img, shadow.transform((S, S), Image.AFFINE, (1, 0, 0, 0, 1, -18 * u)))
img = Image.composite(Image.new("RGB", (S, S), (255, 255, 255)), img, note)
img.resize((1024, 1024), Image.LANCZOS).save(sys.argv[1])
