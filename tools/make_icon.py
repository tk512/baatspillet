#!/usr/bin/env python3
# Build the app icons from the hand-made master (assets/icon/batlogo-master.png,
# the low-poly ferry). The master has rounded corners with BLACK behind them, so
# it becomes two derivatives:
#
#   assets/icon/icon-1024.png          FULL-BLEED square for iOS (corners
#                                      inpainted with the neighbouring art —
#                                      Apple applies its own rounded mask)
#   assets/icon/batlogo-rounded.png    the master with TRANSPARENT corners,
#                                      for macOS icns + marketing use
#
# The iOS one is installed into the vendored engine's appiconset (single-size;
# Xcode derives every size from the 1024).
#
#   python3 tools/make_icon.py
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets/icon/batlogo-master.png")

im = Image.open(SRC).convert("RGB")
W, H = im.size
px = im.load()

# The black outside the rounded corners: near-black pixels inside the four
# corner boxes (radius measured ~230px at 1254; use a generous box).
R = 260
def outside(x, y):
    r, g, b = px[x, y]
    return r + g + b <= 60

corners = [(0, 0, 1, 1), (W - 1, 0, -1, 1), (0, H - 1, 1, -1), (W - 1, H - 1, -1, -1)]

# 1) FULL-BLEED: crop past the rounded corners AND the dark anti-aliased rim
#    around the master's border — the art has margin to spare, so a ~4.5%
#    inset yields a clean edge-to-edge square (Apple rounds it itself).
inset = int(W * 0.045)
bleed = im.crop((inset, inset, W - inset, H - inset))

# THE HOUSE STYLE: pixelated on a 128-cell grid, 32 colours with
# Floyd-Steinberg dithering — the old Sierra VGA look (the sky and sea carry
# a soft dither weave; railings and the flag stay crisp). Restrained on
# purpose: grid/colours are the two taste knobs.
def pixelate(img, grid=128, colors=32):
    small = img.resize((grid, grid), Image.LANCZOS)
    small = small.quantize(colors=colors, dither=Image.Dither.FLOYDSTEINBERG).convert("RGB")
    return small.resize((1024, 1024), Image.NEAREST)

bleed = pixelate(bleed)
out1 = os.path.join(ROOT, "assets/icon/icon-1024.png")
bleed.save(out1)
print("wrote", out1)

# 2) TRANSPARENT-CORNER version (macOS / marketing)
rounded = im.convert("RGBA")
rpx = rounded.load()
for cx, cy, dx, dy in corners:
    for j in range(R):
        y = cy + dy * j
        for i in range(R):
            x = cx + dx * i
            if outside(x, y):
                r, g, b, _ = rpx[x, y]
                rpx[x, y] = (r, g, b, 0)
            else:
                break
# same pixel treatment, alpha preserved
rgb = pixelate(rounded.convert("RGB"))
alpha = rounded.split()[3].resize((128, 128), Image.LANCZOS).resize((1024, 1024), Image.NEAREST)
rounded = rgb.convert("RGBA")
rounded.putalpha(alpha)
out2 = os.path.join(ROOT, "assets/icon/batlogo-rounded.png")
rounded.save(out2)
print("wrote", out2)

# 3) install the full-bleed icon into the vendored engine's iOS appiconset
iconset = os.path.join(ROOT, "engine/platform/xcode/Images.xcassets/iOS AppIcon.appiconset")
for f in os.listdir(iconset):
    os.remove(os.path.join(iconset, f))
bleed.save(os.path.join(iconset, "icon-1024.png"))
with open(os.path.join(iconset, "Contents.json"), "w") as f:
    f.write('{\n  "images" : [\n    {\n      "filename" : "icon-1024.png",\n'
            '      "idiom" : "universal",\n      "platform" : "ios",\n'
            '      "size" : "1024x1024"\n    }\n  ],\n'
            '  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n')
print("installed into", iconset)
