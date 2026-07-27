#!/usr/bin/env python3
# Extract farm buildings into assets/props/farm/<name>.png -- the Norwegian
# countryside: a farmhouse, a barn, a grain silo and a pig pen. src/scenes/world.lua
# scatters these instead of cottages across occasional "farm districts", so the
# land between the towns reads as farmed rather than as the same brick house
# repeating.
#
# These sprites are NOT defined with literal boxes in the pnml -- they come from
# the tmpl_farm() template in sprites/templates/sprite_templates.pnml, which is
# also where the friendly names below come from. Hence the hand-copied boxes
# rather than the usual pnml scrape; re-check them if OpenGFX is ever updated.
#
# PADDING, and why it matters: Objects.draw scales a sprite so its width fills
# the tile footprint, so a 32px-wide farmhouse would be drawn at twice the size
# of a 64px-wide cottage. Every sprite is therefore padded onto a 64px-wide
# canvas (centred, bottom-aligned) so farm buildings sit at the same scale as
# the houses they stand among.
#
# Source: OpenGFX, GPL v2 (see CREDITS.md).

import os
from PIL import Image

OG   = "/Users/tk/proj/OpenGFX"
DEST = os.path.join(os.path.dirname(__file__), "..", "assets", "props", "farm")
TILE = 64        # match the cottages' source box width

# name -> [x, y, w, h] from tmpl_farm(). The pig pen is in on purpose: a
# five-year-old will find the griser long before he notices the silo.
PICK = {
    "farmhouse": [10,  60, 32, 64],
    "barn":      [170, 60, 57, 29],
    "silo":      [330, 60, 45, 48],
    "pigs":      [410, 60, 54, 30],
}


def keyed(im):
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if b > 120 and r < 90 and g < 90:        # TTD blue background
                px[x, y] = (0, 0, 0, 0)
    return im


sheet = Image.open(f"{OG}/sprites/png/industries/farm_temperate.png").convert("RGBA")
os.makedirs(DEST, exist_ok=True)
for name, (x, y, w, h) in PICK.items():
    im = keyed(sheet.crop((x, y, x + w, y + h)))
    canvas = Image.new("RGBA", (TILE, max(h, 1)), (0, 0, 0, 0))
    canvas.paste(im, ((TILE - im.width) // 2, max(0, canvas.height - im.height)), im)
    canvas.save(os.path.join(DEST, f"{name}.png"))
    print(f"  {name:<10} {w}x{h} -> {TILE}x{canvas.height}")
print(f"wrote {len(PICK)} farm buildings -> {os.path.normpath(DEST)}")
