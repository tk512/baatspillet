#!/usr/bin/env python3
# Extract airport buildings into assets/props/airport/<name>.png.
#
# An airport is the single most recognisable "this is a big foreign city" thing
# we can put on the Amerika map -- a control tower reads as an airport to a
# five-year-old instantly, in a way that a slightly different house never will.
# Placed as a CLUSTER (tower + terminal + hangar) via a port's `landmarks` list
# in src/data/ports_amerika.lua.
#
# Indices are positions in the sheet's pnml boxes in reading order; preview with
#   python3 tools/preview_opengfx_sheet.py infrastructure/airports.png
#
# Padded onto a 64px-wide canvas for the same reason as the farm buildings:
# Objects.draw scales a sprite to fill the tile footprint, so an un-padded
# narrow sprite would be drawn far too large next to the houses around it.
#
# Source: OpenGFX, GPL v2 (see CREDITS.md).

import glob
import os
import re
from PIL import Image

OG   = "/Users/tk/proj/OpenGFX"
DEST = os.path.join(os.path.dirname(__file__), "..", "assets", "props", "airport")
SHEET = "infrastructure/airports.png"
TILE = 64

PICK = {
    "terminal": 17,   # glass terminal block with a tower on the roof
    "tower":    18,   # the control tower -- the one that says "airport"
    "hangar":   22,   # arched brick hangar
}


def boxes_for(sheet_name):
    pat = re.compile(re.escape(sheet_name) + r'"\)\s*\{\s*\[([^\]]+)\]')
    out, seen = [], set()
    for p in glob.glob(f"{OG}/sprites/base/*.pnml") + glob.glob(f"{OG}/*.pnml"):
        for row in pat.findall(open(p, encoding="utf-8", errors="ignore").read()):
            b = tuple(int(n) for n in re.split(r"[,\s]+", row.strip())[:4])
            if b not in seen and b[2] > 4 and b[3] > 4:
                seen.add(b)
                out.append(b)
    out.sort(key=lambda b: (b[1], b[0]))
    return out


def keyed(im):
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if b > 120 and r < 90 and g < 90:        # TTD blue background
                px[x, y] = (0, 0, 0, 0)
    return im


sheet = Image.open(f"{OG}/sprites/png/{SHEET}").convert("RGBA")
boxes = boxes_for(os.path.basename(SHEET))
os.makedirs(DEST, exist_ok=True)
for name, idx in PICK.items():
    x, y, w, h = boxes[idx]
    im = keyed(sheet.crop((x, y, x + w, y + h)))
    canvas = Image.new("RGBA", (TILE, max(h, 1)), (0, 0, 0, 0))
    canvas.paste(im, ((TILE - im.width) // 2, max(0, canvas.height - im.height)), im)
    canvas.save(os.path.join(DEST, f"{name}.png"))
    print(f"  {name:<9} {w}x{h} -> {TILE}x{canvas.height}")
print(f"wrote {len(PICK)} airport buildings -> {os.path.normpath(DEST)}")
