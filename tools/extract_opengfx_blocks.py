#!/usr/bin/env python3
# Extract American-looking downtown high-rises into assets/props/blocks/us_<n>.png.
#
# These are the towers that fill the metropolis cores on the AMERIKA map (New
# York, Los Angeles...). They are deliberately a SEPARATE set from block_<n>.png:
# those are the modest Scandinavian blocks that Bergen and Oslo use, and dropping
# glass skyscrapers into a Norwegian fjord town would be wrong. src/scenes/world.lua
# picks the set per map (BLOCK_SETS).
#
# Each sprite keeps its FULL source box (the building sits centred with
# transparent margins) so the on-screen size stays 1:1 with a map tile --
# cropping tight would make Objects.draw upscale them. TTD blue is keyed out.
#
# PICK indices are positions in the sheet's pnml boxes sorted into READING ORDER
# (top-to-bottom, left-to-right) -- NOT the numbers printed on OpenGFX's own
# contact sheets, which are its internal sprite ids. Re-preview with
# tools/preview_opengfx_sheet.py after changing a sheet.
#
# Source: OpenGFX, GPLv2 (see CREDITS.md). Re-run after editing PICK below.

import glob
import os
import re
from PIL import Image

OG = "/Users/tk/proj/OpenGFX"
DEST = os.path.join(os.path.dirname(__file__), "..", "assets", "props", "blocks")

# Finished buildings only -- the sheets are mostly construction stages
# (foundations, scaffolding, half-built shells), which look like rubble in-game.
SHEETS = {
    # brownstones, brick blocks, twin-spire towers, gold glass, civic white,
    # tall red skyscrapers, grey offices
    # (11 and 29 dropped: they render as column skeletons, i.e. foundations)
    "temprtbuilds.png": [5, 6, 8, 14, 15, 17, 18, 25, 27, 31, 33, 39],
    # modern glass towers, a red civic hall, and the blue-glass high-rises that
    # read instantly as "downtown" (9 dropped: another foundation shell)
    "morebuildings.png": [3, 5, 7, 23, 24, 25, 28, 29, 30],
}


def boxes_for(sheet_name):
    """Every distinct sprite box referencing this sheet, in reading order."""
    pat = re.compile(re.escape(sheet_name) + r'"\)\s*\{\s*\[([^\]]+)\]')
    out, seen = [], set()
    for p in glob.glob(f"{OG}/sprites/base/*.pnml") + glob.glob(f"{OG}/*.pnml"):
        for row in pat.findall(open(p, encoding="utf-8", errors="ignore").read()):
            b = tuple(int(n) for n in re.split(r"[,\s]+", row.strip())[:4])
            if b not in seen and b[2] > 4 and b[3] > 4:   # skip 1px spacers
                seen.add(b)
                out.append(b)
    out.sort(key=lambda b: (b[1], b[0]))
    return out


def keyed(im):
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if b > 120 and r < 90 and g < 90:             # TTD blue background
                px[x, y] = (0, 0, 0, 0)
    return im


os.makedirs(DEST, exist_ok=True)
n = 0
for sheet_name, pick in SHEETS.items():
    sheet = Image.open(f"{OG}/sprites/png/houses/{sheet_name}").convert("RGBA")
    boxes = boxes_for(sheet_name)
    for idx in pick:
        if idx >= len(boxes):
            print(f"!! {sheet_name}: index {idx} past {len(boxes)} boxes -- skipped")
            continue
        x, y, w, h = boxes[idx]
        n += 1
        keyed(sheet.crop((x, y, x + w, y + h))).save(os.path.join(DEST, f"us_{n}.png"))
print(f"wrote {n} downtown blocks -> {os.path.normpath(DEST)}")
