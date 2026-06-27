#!/usr/bin/env python3
# Bake a provided nuclear-power-plant sprite (GPL art from another game) into the
# game's retro size: assets/props/powerplant.png. The source already has a
# transparent background; we just crop to content and shrink so it reads as a
# chunky retro sprite under the nearest filter. Put it on the Klokkarvik land.

import os
from PIL import Image

SRC = os.path.expanduser("~/tmp/atomkrat.png")   # override if the source moves
DEST = os.path.join(os.path.dirname(__file__), "..", "assets", "props", "powerplant.png")
TARGET_W = 192

im = Image.open(SRC).convert("RGBA")
bbox = im.getbbox()
if bbox:
    im = im.crop(bbox)
h = max(1, round(im.height * TARGET_W / im.width))
im = im.resize((TARGET_W, h), Image.LANCZOS)
os.makedirs(os.path.dirname(DEST), exist_ok=True)
im.save(DEST)
print("wrote", os.path.normpath(DEST), im.size)
