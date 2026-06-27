#!/usr/bin/env python3
# Extract OpenGFX trees into assets/props/trees/<group>_<n>.png.
#
# Each OpenGFX tree file holds the tree at 7 growth stages laid out left->right
# (templates tmpl_tree_wide / tmpl_tree_narrow). We take the LAST (fully grown)
# stage and key the TTD-blue background to transparent. Groups:
#   conifer_*  green arctic conifers      -> lowland forests
#   snow_*     snowy arctic conifers      -> tiles near the treeline
#   leaf_*     bushy temperate leaf trees -> lowland variety
#
# Source: OpenGFX, GPLv2 (see CREDITS.md). Re-run after editing SELECT below.

import os
from PIL import Image

OG   = "/Users/tk/proj/OpenGFX/sprites/png/trees"
DEST = os.path.join(os.path.dirname(__file__), "..", "assets", "props", "trees")

# (group, source-relative-path). narrow = arctic (35px stages), wide = temperate (45px).
SELECT = [
    ("conifer", "arctic/tree_01_conifer.gimp.png"),
    ("conifer", "arctic/tree_04_conifer.gimp.png"),
    ("conifer", "arctic/tree_05_conifer.gimp.png"),
    ("conifer", "arctic/tree_08_conifer.gimp.png"),
    ("conifer", "arctic/tree_09_conifer.gimp.png"),
    ("snow",    "arctic/tree_01_snow_conifer.gimp.png"),
    ("snow",    "arctic/tree_05_snow_conifer.gimp.png"),
    ("snow",    "arctic/tree_08_snow_conifer.gimp.png"),
    ("snow",    "arctic/tree_09_snow_conifer.gimp.png"),
    ("leaf",    "temperate/tree_wide_02_leaf.gimp.png"),
    ("leaf",    "temperate/tree_wide_13_leaf.gimp.png"),
]


def keyed(im):
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if b > 110 and r < 90 and g < 90:        # TTD blue background
                px[x, y] = (0, 0, 0, 0)
    return im


def crop_to_content(im):
    bbox = im.getbbox()
    return im.crop(bbox) if bbox else im


def full_grown(path):
    im = Image.open(os.path.join(OG, path)).convert("RGBA")
    narrow = "arctic/" in path
    w = 35 if narrow else 45
    x = 240 if narrow else 300                       # last (fully grown) stage
    return crop_to_content(keyed(im.crop((x, 0, x + w, 80))))


os.makedirs(DEST, exist_ok=True)
counts = {}
for group, path in SELECT:
    n = counts.get(group, 0) + 1
    counts[group] = n
    full_grown(path).save(os.path.join(DEST, f"{group}_{n}.png"))
print("wrote", {g: c for g, c in counts.items()}, "->", os.path.normpath(DEST))
