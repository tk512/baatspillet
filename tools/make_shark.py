#!/usr/bin/env python3
"""Turn the 4 photos of the toy shark into an aligned swim/chomp animation.

  ~/Desktop/hai/hai-1.png  jaw closed   -> assets/shark/shark_1.png
  ~/Desktop/hai/hai-2.png  jaw ajar     -> assets/shark/shark_2.png
  ~/Desktop/hai/hai-3.png  jaw open     -> assets/shark/shark_3.png
  ~/Desktop/hai/hai-4.png  jaw wide     -> assets/shark/shark_4.png

The four photos were taken hand-held at slightly different distances and angles,
so a raw loop would inflate and wobble. To get a clean chomp we, per frame:
  - LEVEL it: rotate so the body's principal axis (from image moments) is
    horizontal, killing the hand-held tilt (frame 4's nose-up most of all);
  - NORMALISE size by mid-body thickness (a measure the jaw can't change), so
    the shark stays the same size while only the jaw/tail move; then
  - ANCHOR at the SNOUT (left edge, vertical centre of the nose) on a shared
    canvas, so the head stays put frame-to-frame.
The game can then just swap frames at a single position with no per-frame maths.

Geometry (angle, thickness) is measured on a small downscaled mask for speed;
the actual pixels come from rotating/scaling the full-res photo.

Run:  python3 tools/make_shark.py
"""
import math
import os
from PIL import Image

SRC_DIR = os.path.expanduser("~/Desktop/hai")
FRAMES  = ["hai-1.png", "hai-2.png", "hai-3.png", "hai-4.png"]
OUT     = os.path.join(os.path.dirname(__file__), "..", "assets", "shark")
TARGET_W = 260      # working length used for alignment (kept high for precision)
PIXEL_W  = 120      # final canvas width -- small, so it reads as chunky pixels
COLORS   = 20       # shared palette size -> the game's lightly-dithered retro look
ALPHA_T  = 96       # hard alpha cutoff -> clean edges, no dark halo
MARGIN   = 6        # transparent breathing room around the shark on the canvas
SNOUT_F  = 0.08     # fraction of width treated as "the nose" for the anchor
BODY_LO, BODY_HI = 0.45, 0.65   # mid-body column band used to measure thickness
MASK_W = 400        # width of the downscaled mask used for geometry
ROT_SIGN = -1       # flip if levelling tilts the wrong way (eyeball the preview)


def load_clean(path):
    """RGBA, cropped to a hard-thresholded silhouette (kills halo + stray px)."""
    im = Image.open(path).convert("RGBA")
    r, g, b, a = im.split()
    a = a.point(lambda v: 255 if v > ALPHA_T else 0)
    im = Image.merge("RGBA", (r, g, b, a))
    bbox = im.getbbox()
    return im.crop(bbox) if bbox else im


def small_mask(im):
    """A downscaled binary silhouette (list-of-rows of 0/1) for fast geometry."""
    h = max(1, round(im.height * MASK_W / im.width))
    a = im.resize((MASK_W, h), Image.LANCZOS).split()[3]
    px = list(a.getdata())
    return [[1 if px[y * MASK_W + x] > ALPHA_T else 0 for x in range(MASK_W)]
            for y in range(h)], MASK_W, h


def principal_angle(im):
    """Tilt of the silhouette's long axis, in degrees (0 = level)."""
    grid, w, h = small_mask(im)
    m00 = m10 = m01 = 0
    for y in range(h):
        row = grid[y]
        for x in range(w):
            if row[x]:
                m00 += 1; m10 += x; m01 += y
    if m00 == 0:
        return 0.0
    cx, cy = m10 / m00, m01 / m00
    mu20 = mu02 = mu11 = 0.0
    for y in range(h):
        row = grid[y]; dy = y - cy
        for x in range(w):
            if row[x]:
                dx = x - cx
                mu20 += dx * dx; mu02 += dy * dy; mu11 += dx * dy
    theta = 0.5 * math.atan2(2 * mu11, mu20 - mu02)
    return ROT_SIGN * math.degrees(theta)


def body_thickness(im):
    """Median vertical span of the silhouette across the mid-body band."""
    grid, w, h = small_mask(im)
    spans = []
    for x in range(int(w * BODY_LO), int(w * BODY_HI)):
        ys = [y for y in range(h) if grid[y][x]]
        if ys:
            spans.append(ys[-1] - ys[0] + 1)
    if not spans:
        return 1.0
    spans.sort()
    return spans[len(spans) // 2] * im.width / w     # back to full-res px


def level(im):
    """Rotate so the body's long axis is horizontal, then re-crop cleanly."""
    deg = principal_angle(im)
    im = im.rotate(deg, expand=True, resample=Image.BICUBIC)
    r, g, b, a = im.split()
    a = a.point(lambda v: 255 if v > ALPHA_T else 0)   # rotation softens edges
    im = Image.merge("RGBA", (r, g, b, a))
    bbox = im.getbbox()
    return (im.crop(bbox) if bbox else im), deg


def snout_y(im):
    """Vertical centre of the opaque pixels in the leftmost SNOUT_F columns."""
    w, h = im.size
    cols = max(1, round(w * SNOUT_F))
    a = im.split()[3]
    top, bot = None, None
    for y in range(h):
        row_on = any(a.getpixel((x, y)) > 0 for x in range(cols))
        if row_on:
            if top is None:
                top = y
            bot = y
    if top is None:
        return h // 2
    return (top + bot) // 2


def process():
    cleaned = [load_clean(os.path.join(SRC_DIR, f)) for f in FRAMES]
    levelled = []
    for f, im in zip(FRAMES, cleaned):
        lev, deg = level(im)
        levelled.append(lev)
        print(f"{f}: levelled {deg:+.1f}deg")

    # One size for all: scale frame 1 to TARGET_W, then match every other frame
    # to frame 1's mid-body thickness so the jaw (not the shark) is what changes.
    ref_scale = TARGET_W / levelled[0].width
    ref_bt = body_thickness(levelled[0]) * ref_scale
    scaled = []
    for im in levelled:
        s = ref_bt / body_thickness(im)
        scaled.append(im.resize((max(1, round(im.width * s)),
                                 max(1, round(im.height * s))), Image.LANCZOS))

    anchors = [snout_y(im) for im in scaled]
    up   = max(anchors)                                  # space needed above snout
    down = max(im.height - ay for im, ay in zip(scaled, anchors))
    midY = up + MARGIN
    canvas_w = MARGIN + max(im.width for im in scaled) + MARGIN
    canvas_h = up + down + 2 * MARGIN

    # Compose each aligned frame, then shrink to PIXEL_W so it's genuinely chunky
    # under the game's nearest-filter upscale.
    pscale = PIXEL_W / canvas_w
    pw, ph = PIXEL_W, max(1, round(canvas_h * pscale))
    small = []
    for im, ay in zip(scaled, anchors):
        canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
        canvas.alpha_composite(im, (MARGIN, midY - ay))      # snout-anchored
        small.append(canvas.resize((pw, ph), Image.LANCZOS))

    # ONE shared palette across all frames (else the palette flickers frame to
    # frame): stack the colour, quantize once with light dithering, recut by
    # alpha. Transparent areas are filled with the shark's grey first so the
    # palette isn't wasted banding the (masked-out) background.
    GREY = (150, 152, 156)
    strip = Image.new("RGB", (pw, ph * len(small)), GREY)
    masks = []
    for k, c in enumerate(small):
        r, g, b, a = c.split()
        a = a.point(lambda v: 255 if v > 128 else 0)
        masks.append(a)
        strip.paste(Image.merge("RGB", (r, g, b)), (0, k * ph), a)
    q = strip.quantize(colors=COLORS, method=Image.MEDIANCUT,
                       dither=Image.FLOYDSTEINBERG).convert("RGB")

    os.makedirs(OUT, exist_ok=True)
    prev = Image.new("RGBA", (pw, ph * len(small)), (0, 0, 0, 0))
    for i in range(len(small)):
        row = q.crop((0, i * ph, pw, (i + 1) * ph))
        out = Image.merge("RGBA", (*row.split(), masks[i]))
        path = os.path.join(OUT, f"shark_{i + 1}.png")
        out.save(path)
        print("wrote", os.path.relpath(path), out.size)
        prev.alpha_composite(out, (0, i * ph))

    # stacked preview on water-blue, upscaled (nearest, like the game) to eyeball
    # the pixelation + alignment
    scale_up = 4
    bg = Image.new("RGB", (prev.width * scale_up, prev.height * scale_up), (79, 125, 153))
    big = prev.resize((prev.width * scale_up, prev.height * scale_up), Image.NEAREST)
    bg.paste(big, (0, 0), big)
    bg.save("/tmp/shark_prev.png")
    print("preview -> /tmp/shark_prev.png  (canvas", (pw, ph), ")")


if __name__ == "__main__":
    process()
