#!/usr/bin/env python3
# Extract the Amerika map's OpenGFX art into assets/props/.
#
#   rig/rig_*.png     offshore oil rig -- the ONE thing OpenGFX draws standing in
#                     open water, which is why it earns a place in a boat game
#   oil/flare*.png    refinery flare stack (with and without its flame), plus
#                     tanks and pipework -- the Starbase landmark
#   buoy/buoy_*.png   red navigation buoy, two bob frames
#   palms/palm_*.png  four palms at their MATURE growth stage (Miami, LA)
#
# Boxes come from OpenGFX's own .pnml sprite tables rather than being eyeballed,
# so a re-vendor of the graphics can be re-cut by re-running this. The TTD blue
# background is keyed to transparent.
#
# EVERY cut is PADDED onto a 64px-wide canvas -- one map tile -- exactly like the
# airport and farm extractors, and for the reason their comments give: Objects.draw
# scales a sprite to FILL its tile footprint, so a 50px-wide rig cut down to its
# own ink gets stretched to a full tile and then some, and comes out enormous
# beside the houses. The 64px box is what keeps TTD's own proportions: a palm
# ends up a quarter of a tile wide because that is what it is, and the rig ends
# up towering because a 117px-tall sprite on a 64px tile IS that tall.
#
# Horizontal placement uses the pnml's xofs (the sprite's offset from the tile
# anchor, always about -31 for a tile-wide box), so each thing sits where TTD
# puts it rather than merely centred.
#
# Source: OpenGFX, GPLv2 (see CREDITS.md).

import os
from PIL import Image

OG   = "/Users/tk/proj/OpenGFX/sprites/png"
DEST = os.path.join(os.path.dirname(__file__), "..", "assets", "props")

MISC = "industries/industries_misc.png"
LAND = "landscape/landscape031.png"


def keyed(im):
    """TTD's blue backdrop -> transparent. Same test the other extractors use."""
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if b > 110 and r < 95 and g < 95:
                px[x, y] = (0, 0, 0, 0)
    return im


_sheets = {}


def sheet(path):
    if path not in _sheets:
        _sheets[path] = Image.open(f"{OG}/{path}").convert("RGBA")
    return _sheets[path]


TILE = 64            # one map tile, the reference every sprite is drawn against


def save(name, path, box, xofs=None):
    """Cut, key, and PAD onto a one-tile-wide canvas. `xofs` is the pnml's own
    x offset; without one the cut is centred. Vertical padding is not needed --
    Objects.draw anchors on the lowest opaque row, so the ink's bottom is the
    ground line whatever sits above it."""
    x, y, w, h = box
    im = keyed(sheet(path).crop((x, y, x + w, y + h)))
    bb = im.getbbox()
    if bb:
        im = im.crop((bb[0], bb[1], bb[2], bb[3]))
        left = (bb[0] + (xofs + TILE // 2)) if xofs is not None else (TILE - im.width) // 2
    else:
        left = 0
    left = max(0, min(TILE - im.width, int(left)))
    canvas = Image.new("RGBA", (TILE, max(1, im.height)), (0, 0, 0, 0))
    canvas.paste(im, (left, 0), im)
    out = os.path.join(DEST, name)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    canvas.save(out)
    print("  %-26s ink %dx%d -> %dx%d" % (name, im.width, im.height, canvas.width, canvas.height))
    return canvas


# The oil rig is THREE SPRITES ON THREE TILES, not three variants of one rig --
# 2096 is the helideck on its stalk, 2097 the accommodation block, 2098 the
# derrick and crane. Shipping 2098 alone gives you the right-hand third of a rig
# and nothing else, which is exactly how it first went in.
#
# They compose along the iso diagonal: one tile step is (-32, -16) on screen, and
# the part whose legs reach lowest is the FRONT one. Drawn back to front, that is
# 2096 at (-64,-32), 2097 at (-32,-16), 2098 at (0,0).
RIG_PARTS = [
    ([690, 1976, 32,  75], -31,  -43, -64, -32),   # helideck, back
    ([738, 1976, 32, 110], -31,  -94, -32, -16),   # accommodation
    ([  2, 2104, 50, 117], -31, -117,   0,   0),   # derrick + crane, front
]


def save_rig(name, tiles=2):
    """Compose the parts into one sprite on a `tiles`-wide canvas. Objects.draw
    scales a sprite to the footprint width and Iso.footprint makes that exactly
    tiles*64, so a canvas of that width draws at TTD's own 1:1 pixel scale."""
    laid = []
    for box, xo, yo, dx, dy in RIG_PARTS:
        x, y, w, h = box
        laid.append((keyed(sheet(MISC).crop((x, y, x + w, y + h))), xo + dx, yo + dy))
    minx = min(x for _, x, _ in laid)
    miny = min(y for _, _, y in laid)
    maxx = max(x + im.width for im, x, _ in laid)
    maxy = max(y + im.height for im, _, y in laid)
    comp = Image.new("RGBA", (maxx - minx, maxy - miny), (0, 0, 0, 0))
    for im, x, y in laid:
        comp.alpha_composite(im, (x - minx, y - miny))
    bb = comp.getbbox()
    if bb:
        comp = comp.crop(bb)
    W = TILE * tiles
    assert comp.width <= W, "rig is wider than %d px; raise `tiles`" % W
    canvas = Image.new("RGBA", (W, comp.height), (0, 0, 0, 0))
    canvas.paste(comp, ((W - comp.width) // 2, 0), comp)
    out = os.path.join(DEST, name)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    canvas.save(out)
    print("  %-26s ink %dx%d -> %dx%d (%d tiles wide)"
          % (name, comp.width, comp.height, canvas.width, canvas.height, tiles))


print("oil rig (pnml 2096/2097/2098, composed) ->")
save_rig("rig/rig.png")

# The refinery run (2078-2095) is groups of CONSTRUCTION STAGES, not composites:
# within a group the boxes share a size and offset and the LAST is the finished
# building. Picking by "looks about right" got the bare scaffold (2087) the first
# time round -- the same class of mistake as shipping one third of the oil rig.
print("refinery (pnml 2078-2095, finished stages) ->")
save("oil/flare.png",   MISC, [226,  952, 22, 110],  -9)   # 2086 stack + flame
save("oil/chimney.png", MISC, [ 82,  952, 31,  76], -17)   # 2082 striped column
save("oil/tower.png",   MISC, [130,  952, 26,  71], -16)   # 2083 column + riser
save("oil/plant.png",   MISC, [386,  952, 53,  75], -21)   # 2089 frame, FILLED
save("oil/tank.png",    MISC, [  2,  952, 43,  47], -21)   # 2080 storage tank
save("oil/pumps.png",   MISC, [562,  952, 64,  59], -31)   # 2092 pipework cluster

print("buoy (infrastructure/buoy_map.png) ->")
# 33x68 with no pnml entry. The sheet pads with WHITE and boxes each sprite in
# TTD blue, so the blue runs ARE the two frames -- taking naive halves drags the
# white padding in, and keying white instead would eat the buoy's own stripe.
save("buoy/buoy_1.png", "infrastructure/buoy_map.png", [0,  0, 20, 20])
save("buoy/buoy_2.png", "infrastructure/buoy_map.png", [0, 32, 24, 22])

print("palms (pnml 1884/1898/1905/1926, mature stage) ->")
save("palms/palm_1.png", LAND, [ 66, 808, 25, 43], -12)   # palm tree
save("palms/palm_2.png", LAND, [498, 808, 25, 75], -12)   # large palm -- the tall one
save("palms/palm_3.png", LAND, [706, 808, 25, 41], -12)   # palm tree 2
save("palms/palm_4.png", LAND, [434, 904, 25, 64], -12)   # palm tree 3

print("done ->", os.path.normpath(DEST))
