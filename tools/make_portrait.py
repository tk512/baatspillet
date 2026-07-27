#!/usr/bin/env python3
"""Turn a face photo (transparent background) into a retro harbor-master portrait.

  in : argv[1], default /Users/tk/tmp/papsen.png
  out: assets/ports/portraits/<argv[2]>.png  (argv[2] = port id, default "default",
       the fallback portrait for towns without their own)

Crops to the face, shrinks it to a chunky retro size (it's drawn with nearest
filtering in the portrait well) and quantizes to a small palette for the 90s look.

SIZING, and why it changed: portraits used to be 130px wide. PortScreen:layout
gives the well pw*0.36 of a full-screen dock panel -- ~492x576 points on a 13"
iPad -- so a 130px portrait was blown up ~2.7x in points and ~5.3x in device
pixels on a Retina panel. Playtest feedback was that the faces looked bad, and
the culprit was DITHERING rather than the chunkiness: Floyd-Steinberg is meant to
be viewed small, and magnified 5x it reads as dirt on someone's face. So: render
near the well's real size and quantize WITHOUT dither. The retro banding stays
(COLORS is still small, filtering is still nearest) -- it's just clean now.

Tunable without editing this file:
    PORTRAIT_WIDTH=512 PORTRAIT_COLORS=32 PORTRAIT_DITHER=1 python3 tools/make_portrait.py …
"""
import os, sys
from PIL import Image

SRC = sys.argv[1] if len(sys.argv) > 1 else "/Users/tk/tmp/papsen.png"
NAME = sys.argv[2] if len(sys.argv) > 2 else "default"
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "ports", "portraits", NAME + ".png")
WIDTH = int(os.environ.get("PORTRAIT_WIDTH", 370))    # ~the portrait well's own width
COLORS = int(os.environ.get("PORTRAIT_COLORS", 24))   # palette size (lower = more retro banding)
DITHER = os.environ.get("PORTRAIT_DITHER", "0") == "1"  # off: see SIZING above

im = Image.open(SRC).convert("RGBA")
bbox = im.getbbox()
if bbox:
    im = im.crop(bbox)

# Never upscale: enlarging a small source just invents blur before the palette
# step. A photo narrower than WIDTH is used at its own size (and the console
# line below says so, so a too-small source is visible rather than silent).
w = min(WIDTH, im.width)
if w < WIDTH:
    print("note: %s is only %dpx wide, wanted %d" % (os.path.basename(SRC), im.width, WIDTH))
h = max(1, round(im.height * w / im.width))
im = im.resize((w, h), Image.LANCZOS)

r, g, b, a = im.split()
rgb = Image.merge("RGB", (r, g, b))
flat = rgb.quantize(colors=COLORS, method=Image.MEDIANCUT,
                    dither=Image.FLOYDSTEINBERG if DITHER else Image.NONE).convert("RGB")
amask = a.point(lambda v: 255 if v > 128 else 0)   # hard-threshold for a clean cutout
out = Image.merge("RGBA", (*flat.split(), amask))

os.makedirs(os.path.dirname(OUT), exist_ok=True)
out.save(OUT)
print("wrote", OUT, out.size)

# Preview exactly as the game shows it: contain-scaled into the portrait well
# at its 13"-iPad size, nearest-filtered, on the well's own brown. What you see
# here is what you get when you dock -- no need to launch the game to judge it.
FRAME_W, FRAME_H = 492, 576
s = min(FRAME_W / out.width, FRAME_H / out.height)
big = out.resize((max(1, round(out.width * s)), max(1, round(out.height * s))), Image.NEAREST)
well = Image.new("RGB", (FRAME_W, FRAME_H), (38, 26, 18))
well.paste(big, ((FRAME_W - big.width) // 2, (FRAME_H - big.height) // 2), big)
well.save("/tmp/portrait_prev.png")
