#!/usr/bin/env python3
"""Draw AppleTube app icon concepts (1024x1024). The app uses "glassnote": the user's music-player.png note, bolder, with a Liquid Glass finish.
Usage: python3 -I Scripts/make_icon.py <glassnote|note|groove|pulse|tube> <out.png>"""
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


def note():
    """Hooked eighth note on a pink→red diagonal gradient, full-bleed (iOS applies the rounded mask)."""
    k = S / 512  # geometry measured on the 512px reference
    img = gradient((255, 168, 170), (255, 56, 58), 45)
    glow = Image.new("L", (S, S), 0)
    ImageDraw.Draw(glow).ellipse((-S * .25, -S * .25, S * .6, S * .6), fill=28)
    img = fill(img, (255, 255, 255), glow.filter(ImageFilter.GaussianBlur(S * .1)))

    def bezier(points, steps=200):
        out = []
        for i in range(steps + 1):
            t = i / steps
            pts = points
            while len(pts) > 1:
                pts = [(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t) for a, b in zip(pts, pts[1:])]
            out.append(pts[0])
        return out

    stroke = 10.5 * k
    glyph = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(glyph)
    def line(pts):
        # Stamp round dots densely along the path: smooth curves with round caps, no joint artefacts.
        pts = [(x * k, y * k) for x, y in pts]
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            n = max(1, int(((x1 - x0) ** 2 + (y1 - y0) ** 2) ** .5 / 4))
            for i in range(n + 1):
                x, y = x0 + (x1 - x0) * i / n, y0 + (y1 - y0) * i / n
                d.ellipse((x - stroke / 2, y - stroke / 2, x + stroke / 2, y + stroke / 2), fill=255)
    line([(245, 116), (245, 352)])                                     # stem
    line(bezier([(245, 116), (290, 170), (352, 198), (341, 252)])
         + bezier([(341, 252), (333, 282), (305, 284), (292, 283)])[1:])  # flag
    head = Image.new("L", (S, S), 0)
    cx, cy, r = 205 * k, 357 * k, 45 * k
    ImageDraw.Draw(head).ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    img = shadow(img, ImageChops.lighter(glyph, head), 14 * k, 8 * k, .28, (150, 20, 30))
    img = fill(img, (255, 255, 255), glyph)
    img = fill(img, (255, 255, 255), head)
    # faint shading low-right on the note head, as in the reference
    shade = Image.new("L", (S, S), 0)
    ImageDraw.Draw(shade).ellipse((cx - r * .2, cy - r * .2, cx + r * 1.4, cy + r * 1.4), fill=40)
    shade = ImageChops.multiply(shade.filter(ImageFilter.GaussianBlur(12 * k)), head)
    return fill(img, (235, 215, 220), shade)


def note_mask(k, stroke, head_r):
    """The hooked eighth note from the reference, as a mask (geometry measured on 512px)."""
    def bezier(points, steps=240):
        out = []
        for i in range(steps + 1):
            t = i / steps
            pts = points
            while len(pts) > 1:
                pts = [(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t) for a, b in zip(pts, pts[1:])]
            out.append(pts[0])
        return out

    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    def line(pts):
        pts = [(x * k, y * k) for x, y in pts]
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            n = max(1, int(((x1 - x0) ** 2 + (y1 - y0) ** 2) ** .5 / 4))
            for i in range(n + 1):
                x, y = x0 + (x1 - x0) * i / n, y0 + (y1 - y0) * i / n
                d.ellipse((x - stroke / 2, y - stroke / 2, x + stroke / 2, y + stroke / 2), fill=255)
    line([(250, 112), (250, 350)])
    line(bezier([(250, 112), (300, 168), (366, 196), (352, 256)])
         + bezier([(352, 256), (342, 292), (310, 296), (294, 294)])[1:])
    cx, cy = 202 * k, 356 * k
    d.ellipse((cx - head_r, cy - head_r, cx + head_r, cy + head_r), fill=255)
    return m


def glassnote():
    """The reference note, bolder, rendered as frosted Liquid Glass over a deep pink→red gradient."""
    k = S / 512
    bg = gradient((255, 128, 140), (226, 28, 58), 45)
    sheen = Image.new("L", (S, S), 0)
    ImageDraw.Draw(sheen).ellipse((-S * .35, -S * .45, S * .75, S * .5), fill=70)
    bg = fill(bg, (255, 236, 238), sheen.filter(ImageFilter.GaussianBlur(S * .1)))
    vignette = Image.new("L", (S, S), 0)
    ImageDraw.Draw(vignette).ellipse((S * .35, S * .4, S * 1.4, S * 1.4), fill=60)
    bg = fill(bg, (150, 0, 30), vignette.filter(ImageFilter.GaussianBlur(S * .12)))

    m = note_mask(k, 29 * k, 60 * k)
    img = shadow(bg, m, 26 * k, 14 * k, .45, (120, 0, 25))

    # Frosted body: the background, blurred and brightened, seen through the glass.
    frosted = bg.filter(ImageFilter.GaussianBlur(18 * k))
    frosted = Image.blend(frosted, Image.new("RGB", (S, S), (255, 255, 255)), .8)
    body = gradient((255, 255, 255), (255, 214, 220), 80)
    glass = Image.blend(frosted, body, .45)
    img = Image.composite(glass, img, m)

    # Inner shade low-right and a bright specular rim top-left give the edge thickness.
    def edge(dx, dy, blur):
        shifted = ImageChops.offset(m, int(dx * k), int(dy * k))
        return ImageChops.subtract(m, shifted).filter(ImageFilter.GaussianBlur(blur * k))
    img = fill(img, (215, 70, 95), edge(-5, -5, 3).point(lambda v: int(v * .55)))
    img = fill(img, (255, 255, 255), edge(4, 4, 1.2))
    # A soft gloss band across the upper part of the glass.
    gloss = Image.new("L", (S, S), 0)
    ImageDraw.Draw(gloss).ellipse((120 * k, 60 * k, 420 * k, 250 * k), fill=110)
    gloss = ImageChops.multiply(gloss.filter(ImageFilter.GaussianBlur(30 * k)), m)
    return fill(img, (255, 255, 255), gloss)


img = {"glassnote": glassnote, "note": note, "groove": groove, "pulse": pulse, "tube": tube}[sys.argv[1]]()
img.resize((1024, 1024), Image.LANCZOS).save(sys.argv[2])
