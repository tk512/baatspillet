#!/usr/bin/env python3
"""Contact sheet of an OpenGFX sprite sheet, labelled with USABLE indices.

The numbers OpenGFX prints on its own sheets are its internal sprite ids, not
the order boxes appear in the pnml — so you can't pick from them directly. This
renders the boxes with the indices an extractor actually sees.

TWO index spaces, because the extractors use two. Preview in the same one as the
extractor you're editing, or your picks will be silently wrong:

    python3 tools/preview_opengfx_sheet.py houses/temprtbuilds.png
        Every pnml referencing the sheet, deduped, sorted into reading order.
        This is extract_opengfx_blocks.py's space (and any new extractor's).

    python3 tools/preview_opengfx_sheet.py houses/towns02.png \\
            --pnml base-4588-houses-tropic.pnml
        ONE pnml, in file order — extract_opengfx_houses.py's space. Use this
        when adding to an existing PICK list, so sprites already shipped keep
        their numbers.

Writes <sheet>_INDEX.png into --out (default /tmp).
"""
import argparse
import glob
import os
import re
from PIL import Image, ImageDraw

OG = "/Users/tk/proj/OpenGFX"

ap = argparse.ArgumentParser()
ap.add_argument("sheet", help="path under sprites/png, e.g. industries/farm_temperate.png")
ap.add_argument("--pnml", help="single pnml under sprites/base (file order)")
ap.add_argument("--out", default="/tmp")
args = ap.parse_args()

name  = os.path.basename(args.sheet)
sheet = Image.open(f"{OG}/sprites/png/{args.sheet}").convert("RGBA")
pat   = re.compile(re.escape(name) + r'"\)\s*\{\s*\[([^\]]+)\]')

if args.pnml:                                    # one file, file order, no dedupe
    text = open(f"{OG}/sprites/base/{args.pnml}", encoding="utf-8", errors="ignore").read()
    boxes = [tuple(int(n) for n in re.split(r"[,\s]+", r.strip())[:4])
             for r in pat.findall(text)]
else:                                            # all files, deduped, reading order
    boxes, seen = [], set()
    for p in glob.glob(f"{OG}/sprites/base/*.pnml") + glob.glob(f"{OG}/*.pnml"):
        for row in pat.findall(open(p, encoding="utf-8", errors="ignore").read()):
            b = tuple(int(n) for n in re.split(r"[,\s]+", row.strip())[:4])
            if b not in seen and b[2] > 4 and b[3] > 4:   # skip 1px spacers
                seen.add(b)
                boxes.append(b)
    boxes.sort(key=lambda b: (b[1], b[0]))
print(f"{name}: {len(boxes)} sprite boxes")


def keyed(im):
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if b > 120 and r < 90 and g < 90:             # TTD blue background
                px[x, y] = (0, 0, 0, 0)
    return im


CELL_W, CELL_H, COLS = 96, 116, 10
rows = max(1, (len(boxes) + COLS - 1) // COLS)
grid = Image.new("RGB", (CELL_W * COLS, CELL_H * rows), (28, 30, 34))
d = ImageDraw.Draw(grid)
for i, (x, y, w, h) in enumerate(boxes):
    im = keyed(sheet.crop((x, y, x + w, y + h)))
    cx, cy = (i % COLS) * CELL_W, (i // COLS) * CELL_H
    grid.paste(im, (cx + max(0, (CELL_W - im.width) // 2),
                    cy + 14 + max(0, (CELL_H - 14 - im.height) // 2)), im)
    d.text((cx + 3, cy + 2), str(i), fill=(255, 220, 90))
    d.rectangle([cx, cy, cx + CELL_W - 1, cy + CELL_H - 1], outline=(60, 64, 70))
path = os.path.join(args.out, name.replace(".png", "") + "_INDEX.png")
grid.save(path)
print("wrote", path)
