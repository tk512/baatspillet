#!/usr/bin/env python3
# Extract OpenGFX landmarks + town blocks into assets/props/.
#
#   church.png      arctic church  -> auto-swaps the code-drawn church landmark
#   lighthouse.png  coastal landmark (very Norwegian)
#   fountain.png    town-square decoration
#   park.png        leafy town park
#   blocks/block_*  low apartment blocks for bigger towns
#
# 1-tile buildings keep their full 64px source box so on-screen size stays 1:1
# with a map tile. The TTD blue background is keyed to transparent.
#
# Source: OpenGFX, GPLv2 (see CREDITS.md).

import os, re
from PIL import Image

OG   = "/Users/tk/proj/OpenGFX/sprites/png"
DEST = os.path.join(os.path.dirname(__file__), "..", "assets", "props")


def keyed(im):
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if b > 110 and r < 95 and g < 95:
                px[x, y] = (0, 0, 0, 0)
    return im


def cut(sheet, box):
    im = Image.open(f"{OG}/{sheet}").convert("RGBA")
    x, y, w, h = box
    return keyed(im.crop((x, y, x + w, y + h)))


def save(name, sheet, box):
    out = os.path.join(DEST, name)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    cut(sheet, box).save(out)
    print(" ", name)


save("church.png",     "houses/arcticchurch.png",     [150, 10, 64, 44])
save("lighthouse.png", "landscape/landscape031.png",  [706, 3976, 41, 61])
save("fountain.png",   "houses/statuefountain.png",   [41, 21, 34, 42])
save("park.png",       "houses/1456_1457_parks.png",  [11, 0, 64, 80])

# town apartment blocks (towns02 indices 23,24,26,27) -- full-tile boxes
pnml = open("/Users/tk/proj/OpenGFX/sprites/base/base-4588-houses-tropic.pnml").read()
tboxes = [[int(n) for n in re.split(r"[,\s]+", r.strip())]
          for r in re.findall(r'towns02\.png"\)\s*\{\s*\[([^\]]+)\]', pnml)]
for n, idx in enumerate((23, 24, 26, 27), start=1):
    x, y, w, h = tboxes[idx][:4]
    save(f"blocks/block_{n}.png", "houses/towns02.png", [x, y, w, h])

print("done ->", os.path.normpath(DEST))
