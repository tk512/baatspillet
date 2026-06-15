#!/usr/bin/env python3
"""Turn a face photo (transparent background) into a dithered harbor-master portrait.

  in : argv[1], default /Users/tk/tmp/papsen.png
  out: assets/ports/portraits/<argv[2]>.png  (argv[2] = port id, default "default",
       the fallback portrait for towns without their own)

Crops to the face, shrinks it small (chunky pixels in the nearest-filter well),
and quantizes to a small dithered palette for the 90s look.
"""
import os, sys
from PIL import Image

SRC = sys.argv[1] if len(sys.argv) > 1 else "/Users/tk/tmp/papsen.png"
NAME = sys.argv[2] if len(sys.argv) > 2 else "default"
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "ports", "portraits", NAME + ".png")
WIDTH = 130       # small -> chunky pixels when scaled up
COLORS = 24       # palette size (lower = more retro banding)

im = Image.open(SRC).convert("RGBA")
bbox = im.getbbox()
if bbox:
    im = im.crop(bbox)

h = max(1, round(im.height * WIDTH / im.width))
im = im.resize((WIDTH, h), Image.LANCZOS)

r, g, b, a = im.split()
rgb = Image.merge("RGB", (r, g, b))
dithered = rgb.quantize(colors=COLORS, method=Image.MEDIANCUT,
                        dither=Image.FLOYDSTEINBERG).convert("RGB")
amask = a.point(lambda v: 255 if v > 128 else 0)   # hard-threshold for a clean cutout
out = Image.merge("RGBA", (*dithered.split(), amask))

os.makedirs(os.path.dirname(OUT), exist_ok=True)
out.save(OUT)
print("wrote", OUT, out.size)

# preview on the portrait-well colour, scaled up, for eyeballing
scale = 3
well = Image.new("RGB", (out.width * scale, out.height * scale), (38, 26, 18))
big = out.resize((out.width * scale, out.height * scale), Image.NEAREST)
well.paste(big, (0, 0), big)
well.save("/tmp/portrait_prev.png")
