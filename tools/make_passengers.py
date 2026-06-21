#!/usr/bin/env python3
"""Turn the 4 action figures in ~/Desktop/bruder.pdf into passenger icons.

  page 1..4  ->  assets/icons/passenger1.png .. passenger4.png

Each page is one figure centred on white (with a thin dark scan frame). We trim
the frame, flood-fill the white background to transparent (seeding from the
margins, not the corners), crop to the figure, shrink it small and quantize all
four to ONE shared dithered palette -- the game's lightly-pixelized retro look
under its nearest filter. The shared palette keeps the four looking like a set.

These feed the placeholder-first icon system (src/ui/icons.lua): a passenger
mission picks one of passenger1..4, and Icons.draw finds the PNG automatically.

Run:  python3 tools/make_passengers.py
"""
import glob
import os
import subprocess

import numpy as np
from PIL import Image, ImageDraw

PDF      = os.path.expanduser("~/Desktop/bruder.pdf")
OUT      = os.path.join(os.path.dirname(__file__), "..", "assets", "icons")
DPI      = 110
TRIM     = 0.05     # fraction cropped off each edge to drop the dark scan frame
FILL_TH  = 90       # flood-fill tolerance (sum of per-band diff from the seed)
PIX_H    = 300      # source height; kept high + drawn with a linear filter so it
                    # shrinks smoothly like the boat photo (not crunchy pixels)
COLORS   = 48       # gentle shared posterize (no dither) -> subtle retro banding
SENT     = (255, 0, 255)   # magenta sentinel for "this is background"


def render_pages():
    tmp = "/tmp/bruder"
    existing = sorted(glob.glob(tmp + "-*.png"))
    if existing:                      # reuse an earlier render (rendering is slow)
        return existing
    subprocess.run(["pdftoppm", "-png", "-r", str(DPI), PDF, tmp], check=True)
    return sorted(glob.glob(tmp + "-*.png"))


def cutout(path):
    """Return an RGBA image of just the figure (white background removed)."""
    im = Image.open(path).convert("RGB")
    w, h = im.size
    m = int(min(w, h) * TRIM)
    im = im.crop((m, m, w - m, h - m))
    w, h = im.size

    # Seed the flood fill from the white margins (mid-edges + inset corners),
    # never the very corner (the scan frame there can be dark).
    seeds = [(int(w * 0.06), int(h * 0.06)), (int(w * 0.5), int(h * 0.04)),
             (int(w * 0.94), int(h * 0.06)), (int(w * 0.06), int(h * 0.5)),
             (int(w * 0.94), int(h * 0.5)), (int(w * 0.06), int(h * 0.94)),
             (int(w * 0.5), int(h * 0.96)), (int(w * 0.94), int(h * 0.94))]
    for s in seeds:
        try:
            ImageDraw.floodfill(im, s, SENT, thresh=FILL_TH)
        except Exception:
            pass

    arr = np.asarray(im)
    bg = np.all(arr == np.array(SENT), axis=-1)
    rgba = np.dstack([arr, np.where(bg, 0, 255).astype("uint8")])
    rgba[bg] = (0, 0, 0, 0)
    out = Image.fromarray(rgba, "RGBA")

    # Crop to the DENSE region (the figure), ignoring sparse shadow fringe/specks
    # that a plain bbox would include -- so every figure fills its canvas evenly.
    a = np.asarray(out)[:, :, 3] > 40
    rows, cols = a.sum(1), a.sum(0)
    ys = np.where(rows > rows.max() * 0.06)[0]
    xs = np.where(cols > cols.max() * 0.06)[0]
    if len(xs) and len(ys):
        pad = 2
        out = out.crop((max(0, xs[0] - pad), max(0, ys[0] - pad),
                        min(out.width, xs[-1] + 1 + pad), min(out.height, ys[-1] + 1 + pad)))
    return out


def process():
    pages = render_pages()
    assert pages, "pdftoppm produced no pages"

    figs = []
    for p in pages[:4]:
        im = cutout(p)
        scale = PIX_H / im.height
        im = im.resize((max(1, round(im.width * scale)), PIX_H), Image.LANCZOS)
        figs.append(im)

    # One shared palette: stack the colour onto a neutral strip, quantize once
    # with light dithering, then recut each figure by its own alpha.
    sw = max(f.width for f in figs)
    strip = Image.new("RGB", (sw, PIX_H * len(figs)), (128, 128, 128))
    masks = []
    for i, f in enumerate(figs):
        r, g, b, a = f.split()
        a = a.point(lambda v: 255 if v > 128 else 0)
        masks.append(a)
        strip.paste(Image.merge("RGB", (r, g, b)), ((sw - f.width) // 2, i * PIX_H), a)
    q = strip.quantize(colors=COLORS, method=Image.MEDIANCUT,
                       dither=Image.NONE).convert("RGB")   # no dither -> clean, not noisy

    os.makedirs(OUT, exist_ok=True)
    prev = Image.new("RGBA", (sw * 4 + 50, PIX_H + 20), (60, 110, 150, 255))
    for i, f in enumerate(figs):
        x0 = (sw - f.width) // 2
        region = q.crop((x0, i * PIX_H, x0 + f.width, i * PIX_H + PIX_H))
        out = Image.merge("RGBA", (*region.split(), masks[i]))   # recut by the figure's alpha
        path = os.path.join(OUT, "passenger%d.png" % (i + 1))
        out.save(path)
        print("wrote", os.path.relpath(path), out.size)
        prev.alpha_composite(out, (10 + i * (sw + 10), 10))

    scale = 2
    big = prev.resize((prev.width * scale, prev.height * scale), Image.NEAREST)
    big.convert("RGB").save("/tmp/passengers_prev.png")
    print("preview -> /tmp/passengers_prev.png")


if __name__ == "__main__":
    process()
