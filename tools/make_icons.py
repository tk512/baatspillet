#!/usr/bin/env python3
"""Stylize the Butikk goods photos into game icons -- the same semi-pixelized
recipe as the ships (crop to content, shrink small, 64-colour dither-quantize),
so the store gets the cool retro-atmospheric look without hand pixel art.

Reads background-removed PNGs from INPUT_DIR named:

    "<norsk navn> - sprite.png"      e.g. "ost - sprite.png"

and writes assets/icons/<ikonnavn>.png using the icon names the game already
references in src/data/shop.lua (so they drop in with zero code changes;
src/ui/icons.lua prefers the PNG over its code-drawn placeholder).

Run:  python3 tools/make_icons.py
"""
import os, glob, unicodedata
from PIL import Image

HERE = os.path.dirname(__file__)
INPUT_DIR = os.path.expanduser("~/Desktop/skip")
OUT = os.path.join(HERE, "..", "assets", "icons")
TARGET = 176          # max dimension: the crates ZOOM the photo to cover their
                      # picture area (Icons.drawCover), so keep enough pixels
                      # that the zoom stays crisp on big screens
COLORS = 64           # palette size: PNG-8 + Floyd-Steinberg = posterized look

# norsk filnavn -> icon name in src/data/shop.lua / src/ui/icons.lua
MAP = {
    "ost":        "cheese",
    "eple":       "apple",
    "sitron":     "lemon",
    "saft":       "juice",
    "brød":       "bread",
    "kanonkuler": "kanonkuler",
    "kanon":      "cannon",
}


def process():
    os.makedirs(OUT, exist_ok=True)
    done = 0
    for p in sorted(glob.glob(os.path.join(INPUT_DIR, "* - sprite.png"))):
        base = os.path.basename(p)[:-len(" - sprite.png")]
        # NFC: macOS filenames arrive decomposed ("ø" as o + stroke would miss)
        key = unicodedata.normalize("NFC", base).strip().lower()
        name = MAP.get(key)
        if not name:
            continue                      # not a goods photo (ships etc.)
        im = Image.open(p).convert("RGBA")
        bbox = im.getbbox()
        if bbox:
            im = im.crop(bbox)
        scale = TARGET / max(im.width, im.height)
        im = im.resize((max(1, round(im.width * scale)),
                        max(1, round(im.height * scale))), Image.LANCZOS)
        q = im.quantize(colors=COLORS, method=Image.FASTOCTREE,
                        dither=Image.FLOYDSTEINBERG)
        outp = os.path.join(OUT, f"{name}.png")
        q.save(outp, optimize=True)
        print(f"  {name}.png  {im.size}  (fra '{base}')")
        done += 1
    print(f"done -> {os.path.normpath(OUT)}  ({done} ikoner)")


if __name__ == "__main__":
    process()
