#!/usr/bin/env python3
"""Draw AppleTube app icon concepts (1024x1024). The app uses "pulse".
Usage: python3 -I Scripts/make_icon.py <groove|pulse|tube> <out.png>"""
import math, sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops

S = 4096
U = S / 1024


def gradient(c1, c2, angle=90):
    """Linear gradient from c1 to c2; angle 90 = top→bottom, 45 = top-left→bottom-right."""
    a = math.radians(angle)
    dx, dy = math.cos(a), math.sin(a)
    small = 256
    img = Image.new("RGB", (small, small))
    px = img.load()
    for y in range(small):
        for x in range(small):
            t = ((x / small - .5) * dx + (y / small - .5) * dy) / (abs(dx) * .5 + abs(dy) * .5) * .5 + .5
            t = min(max(t, 0), 1)
            px[x, y] = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))
    return img.resize((S, S), Image.BICUBIC)


def rounded(mask, radius):
    """Round a mask's corners: blur, then threshold."""
    return mask.filter(ImageFilter.GaussianBlur(radius)).point(lambda v: 255 if v > 128 else 0)


def play_triangle(cx, cy, size, radius):
    m = Image.new("L", (S, S), 0)
    h = size * math.sqrt(3) / 2
    # centroid at (cx, cy)
    pts = [(cx - h / 3, cy - size / 2), (cx - h / 3, cy + size / 2), (cx + 2 * h / 3, cy)]
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return rounded(m, radius)


def fill(base, color_or_img, mask):
    layer = color_or_img if isinstance(color_or_img, Image.Image) else Image.new("RGB", (S, S), color_or_img)
    return Image.composite(layer, base, mask)


def shadow(base, mask, blur, offset, opacity, color=(0, 0, 0)):
    sh = mask.filter(ImageFilter.GaussianBlur(blur)).point(lambda v: int(v * opacity))
    sh = ImageChops.offset(sh, 0, int(offset))
    return fill(base, color, sh)


def groove():
    """A vinyl record whose label is a warm play button."""
    img = gradient((26, 18, 64), (8, 6, 22), 70)
    c = S / 2
    disc = Image.new("L", (S, S), 0)
    r = 410 * U
    ImageDraw.Draw(disc).ellipse((c - r, c - r, c + r, c + r), fill=255)
    img = shadow(img, disc, 40 * U, 24 * U, .55)
    img = fill(img, (14, 12, 20), disc)
    grooves = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(grooves)
    for i, rr in enumerate(range(int(395 * U), int(200 * U), -int(14 * U))):
        d.ellipse((c - rr, c - rr, c + rr, c + rr), outline=38 + (i % 3) * 10, width=int(2.2 * U))
    img = fill(img, (90, 80, 120), grooves)
    # sheen across the grooves
    sheen = Image.new("L", (S, S), 0)
    ImageDraw.Draw(sheen).pieslice((c - r, c - r, c + r, c + r), 205, 245, fill=70)
    ImageDraw.Draw(sheen).pieslice((c - r, c - r, c + r, c + r), 25, 65, fill=45)
    sheen = ImageChops.multiply(sheen.filter(ImageFilter.GaussianBlur(30 * U)), disc)
    img = fill(img, (255, 255, 255), sheen)
    label = Image.new("L", (S, S), 0)
    lr = 185 * U
    ImageDraw.Draw(label).ellipse((c - lr, c - lr, c + lr, c + lr), fill=255)
    img = fill(img, gradient((255, 95, 109), (255, 175, 80), 45), label)
    tri = play_triangle(c + 6 * U, c, 170 * U, 18 * U)
    img = shadow(img, tri, 10 * U, 6 * U, .25, (120, 20, 30))
    return fill(img, (255, 255, 255), tri)


def pulse():
    """A rounded play button built from equalizer bars."""
    img = gradient((0, 214, 180), (70, 52, 235), 60)
    glow = Image.new("L", (S, S), 0)
    ImageDraw.Draw(glow).ellipse((-S * .2, -S * .3, S * .8, S * .5), fill=60)
    img = fill(img, (255, 255, 255), glow.filter(ImageFilter.GaussianBlur(S * .12)))
    tri = play_triangle(S / 2 + 20 * U, S / 2, 600 * U, 40 * U)
    bars = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(bars)
    x0, w, gap = 300 * U, 62 * U, 30 * U
    for i in range(6):
        x = x0 + i * (w + gap)
        d.rounded_rectangle((x, 0, x + w, S), radius=w / 2, fill=255)
    shape = ImageChops.multiply(tri, bars)
    shape = rounded(shape, 6 * U)
    img = shadow(img, shape, 30 * U, 18 * U, .3, (20, 10, 80))
    return fill(img, (255, 255, 255), shape)


def tube():
    """A glossy capsule ('tube') carrying a sound wave, on a sunset gradient."""
    img = gradient((255, 122, 24), (175, 0, 72), 75)
    cap = Image.new("L", (S, S), 0)
    ImageDraw.Draw(cap).rounded_rectangle((150 * U, 360 * U, 874 * U, 664 * U), radius=152 * U, fill=255)
    img = shadow(img, cap, 40 * U, 26 * U, .35, (90, 0, 30))
    img = fill(img, (255, 248, 240), cap)
    wave = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(wave)
    heights = [40, 90, 150, 210, 150, 230, 120, 180, 90, 50]
    n, w = len(heights), 34 * U
    span = 560 * U
    for i, hgt in enumerate(heights):
        x = 232 * U + i * span / (n - 1) - w / 2
        h = hgt * U / 2
        d.rounded_rectangle((x, 512 * U - h, x + w, 512 * U + h), radius=w / 2, fill=255)
    img = fill(img, gradient((255, 110, 40), (200, 0, 80), 0), wave)
    gloss = Image.new("L", (S, S), 0)
    ImageDraw.Draw(gloss).rounded_rectangle((190 * U, 378 * U, 834 * U, 470 * U), radius=46 * U, fill=70)
    return fill(img, (255, 255, 255), gloss.filter(ImageFilter.GaussianBlur(10 * U)))


img = {"groove": groove, "pulse": pulse, "tube": tube}[sys.argv[1]]()
img.resize((1024, 1024), Image.LANCZOS).save(sys.argv[2])
