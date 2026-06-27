#!/usr/bin/env python3
# Extract small OpenGFX town houses into assets/props/houses/house_<n>.png.
#
# Curated Scandinavian-looking cottages (white walls, red/grey roofs) from
# towns02.png. We keep each sprite's FULL 64px-wide source box (the house sits
# centred with transparent margins) so the on-screen size stays 1:1 with a map
# tile -- cropping tight would make Objects.draw upscale them. The TTD blue
# background is keyed to transparent.
#
# Source: OpenGFX, GPLv2 (see CREDITS.md). Re-run after editing PICK below.

import os, re
from PIL import Image

OG   = "/Users/tk/proj/OpenGFX"
DEST = os.path.join(os.path.dirname(__file__), "..", "assets", "props", "houses")
PICK = [1, 2, 7, 8, 11, 17, 18]      # indices in the towns02 contact sheet

sheet = Image.open(OG + "/sprites/png/houses/towns02.png").convert("RGBA")
pnml  = open(OG + "/sprites/base/base-4588-houses-tropic.pnml").read()
rows  = re.findall(r'towns02\.png"\)\s*\{\s*\[([^\]]+)\]', pnml)
boxes = [[int(n) for n in re.split(r"[,\s]+", r.strip())] for r in rows]


def keyed(im):
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if b > 120 and r < 90 and g < 90:        # TTD blue background
                px[x, y] = (0, 0, 0, 0)
    return im


os.makedirs(DEST, exist_ok=True)
for n, idx in enumerate(PICK, start=1):
    x, y, w, h, ox, oy = boxes[idx]
    keyed(sheet.crop((x, y, x + w, y + h))).save(os.path.join(DEST, f"house_{n}.png"))
print("wrote", len(PICK), "houses ->", os.path.normpath(DEST))
