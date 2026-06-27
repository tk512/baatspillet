#!/usr/bin/env python3
# Extract OpenGFX ship sprites into assets/ships/<name>/0..7.png.
#
# OpenGFX (the OpenTTD base set) draws ships in 2:1 dimetric -- the SAME ratio as
# our Iso.SX/SY -- so its 8 compass views drop straight into our isometric world.
# For each ship we take the 8 views, key the blue background to transparent, and
# composite each view onto a shared canvas using the source's draw offsets so the
# hull keeps a common pivot (otherwise the boat jitters as it turns).
#
# Source: OpenGFX, GPLv2 (see CREDITS.md). Re-run after editing OPENGFX below.
# Frame order on disk (0..7) is the OpenTTD Direction enum: N, NE, E, SE, S, SW,
# W, NW -- see Objects.drawShipSprite for the heading -> frame mapping.

import os, re
from PIL import Image

OPENGFX = "/Users/tk/proj/OpenGFX"
DEST    = os.path.join(os.path.dirname(__file__), "..", "assets", "ships")


def keyed(im):
    """TTD transparent-blue background -> alpha 0."""
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if b > 120 and r < 80 and g < 80:
                px[x, y] = (0, 0, 0, 0)
    return im


def emit(name, sheet_path, boxes):
    sheet = Image.open(os.path.join(OPENGFX, sheet_path)).convert("RGBA")
    minx = min(b[4] for b in boxes); miny = min(b[5] for b in boxes)
    maxx = max(b[4] + b[2] for b in boxes); maxy = max(b[5] + b[3] for b in boxes)
    W, H = maxx - minx, maxy - miny
    out = os.path.join(DEST, name)
    os.makedirs(out, exist_ok=True)
    for i, (x, y, w, h, ox, oy) in enumerate(boxes):
        crop = keyed(sheet.crop((x, y, x + w, y + h)).convert("RGBA"))
        canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        canvas.paste(crop, (ox - minx, oy - miny), crop)
        canvas.save(os.path.join(out, f"{i}.png"))
    print(f"{name}: 8x {W}x{H}")


# --- ships01.png: 4 ships x 8 views, explicit boxes from the pnml ---
pnml = open(os.path.join(OPENGFX, "sprites/base/base-3668-ships.pnml")).read()
rows = re.findall(r'ships01\.png"\)\s*\{\s*\[([^\]]+)\]', pnml)
boxes = [[int(n) for n in re.split(r"[,\s]+", r.strip())] for r in rows]
NAMES = ["cargo_ship1", "cargo_ship2", "cargo_ship3", "cargo_ship4"]
for s, nm in enumerate(NAMES):
    emit(nm, "sprites/png/ships/ships01.png", boxes[s * 8:(s + 1) * 8])

# --- toyland_ships.png: 2 ships defined via templates (base x,y added in) ---
def tmpl(rows, bx, by):
    return [[bx + dx, by, w, h, ox, oy] for (dx, w, h, ox, oy) in rows]

T1 = [(0, 19, 39, -8, -7), (32, 56, 32, -70, 6), (96, 73, 26, -42, -14), (176, 56, 37, -5, -4),
      (240, 19, 42, -8, -16), (272, 56, 37, -60, -4), (336, 73, 26, -44, -10), (416, 56, 32, -3, -3)]
T2 = [(0, 16, 35, -7, -18), (32, 42, 34, -44, -4), (96, 52, 28, -24, -15), (176, 42, 29, 2, -1),
      (240, 16, 32, -7, -18), (272, 42, 29, -45, 0), (336, 52, 28, -26, -17), (416, 42, 35, 1, -6)]
emit("toyland_ship1", "sprites/png/ships/toyland_ships.png", tmpl(T1, 14, 12))
emit("toyland_ship2", "sprites/png/ships/toyland_ships.png", tmpl(T2, 14, 63))
print("done ->", os.path.normpath(DEST))
