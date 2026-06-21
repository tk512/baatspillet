#!/usr/bin/env python3
"""Turn the toy Coast Guard helicopter photo into a pixelized menu sprite.

  ~/Downloads/Subject 4.png  (bow/nose RIGHT)  -> assets/menu/helicopter.png

The photo's own main-rotor blades are CROPPED OFF the top (ROTOR_CROP): the menu
draws a cheap spinning rotor in code over the hub instead, which reads as "busy"
far better than frozen blades. Same retro look as the shark (small canvas +
shared dithered palette under the game's nearest filter).

Run:  python3 tools/make_heli.py
"""
import os
from PIL import Image

SRC      = os.path.expanduser("~/Downloads/Subject 4.png")
OUT      = os.path.join(os.path.dirname(__file__), "..", "assets", "menu", "helicopter.png")
PIXEL_W  = 200      # final width -- small, so it reads as chunky pixels
COLORS   = 22       # shared palette size -> the game's lightly-dithered retro look
ALPHA_T  = 96       # hard alpha cutoff -> clean edges, no dark halo
ROTOR_CROP = 0.36   # fraction of height to shave off the TOP (the static blades)


def load_clean(path):
    im = Image.open(path).convert("RGBA")
    r, g, b, a = im.split()
    a = a.point(lambda v: 255 if v > ALPHA_T else 0)
    im = Image.merge("RGBA", (r, g, b, a))
    bbox = im.getbbox()
    return im.crop(bbox) if bbox else im


def process():
    im = load_clean(SRC)
    # shave the static main-rotor blades off the top, then re-crop tight
    cut = int(im.height * ROTOR_CROP)
    im = im.crop((0, cut, im.width, im.height))
    bbox = im.getbbox()
    if bbox:
        im = im.crop(bbox)

    ph = max(1, round(im.height * PIXEL_W / im.width))
    small = im.resize((PIXEL_W, ph), Image.LANCZOS)

    # quantize to a shared dithered palette; restore the alpha cutout
    r, g, b, a = small.split()
    a = a.point(lambda v: 255 if v > 128 else 0)
    q = Image.merge("RGB", (r, g, b)).quantize(
        colors=COLORS, method=Image.MEDIANCUT, dither=Image.FLOYDSTEINBERG).convert("RGB")
    out = Image.merge("RGBA", (*q.split(), a))

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    out.save(OUT)
    print("wrote", os.path.relpath(OUT), out.size)

    # preview upscaled (nearest, like the game) on sky-blue, with a guide line at
    # the cabin roof so we can judge where the code rotor hub should sit
    scale = 4
    bg = Image.new("RGB", (out.width * scale, out.height * scale + 40), (140, 180, 210))
    big = out.resize((out.width * scale, out.height * scale), Image.NEAREST)
    bg.paste(big, (0, 20), big)
    bg.save("/tmp/heli_prev.png")
    print("preview -> /tmp/heli_prev.png")


if __name__ == "__main__":
    process()
