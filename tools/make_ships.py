#!/usr/bin/env python3
"""Stylize real boat photos into ambient-ship billboards (like the Viking Sky).

Reads background-removed PNGs from INPUT_DIR named:

    "<Name> - <Country> - sprite.png"     e.g. "Aidaluna - Tyskland - sprite.png"

(the " - sprite" marks the cut-out version; originals without it are ignored).
Each is shot roughly side-on; the game mirrors it for boats sailing the other way.
Crops to the boat and shrinks to TARGET_W so it reads as chunky retro pixels under
the game's nearest filter.

Outputs:  assets/ships_photos/<slug>.png   (+ /tmp preview)
Also prints a src/data/ships.lua stub (name + country parsed from the filename;
fill in the `type` yourself, e.g. "Passasjerskip").

Run:  python3 tools/make_ships.py
"""
import os, glob, re
from PIL import Image

HERE = os.path.dirname(__file__)
INPUT_DIR = "/Users/tk/Desktop/skip"
OUT = os.path.join(HERE, "..", "assets", "ships_photos")
TARGET_W = 220            # sprite width in px (smaller = more pixelized)


def slugify(name):
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def process():
    os.makedirs(OUT, exist_ok=True)
    paths = sorted(glob.glob(os.path.join(INPUT_DIR, "* - sprite.png")))
    if not paths:
        print(f"no '* - sprite.png' files in {INPUT_DIR}")
        return
    stubs = []
    for p in paths:
        base = os.path.basename(p)[:-len(" - sprite.png")]      # "Name - Country"
        parts = [s.strip() for s in base.split(" - ")]
        name = parts[0]
        country = parts[1] if len(parts) > 1 else ""
        slug = slugify(name)

        im = Image.open(p).convert("RGBA")
        bbox = im.getbbox()
        if bbox:
            im = im.crop(bbox)
        h = max(1, round(im.height * TARGET_W / im.width))
        im = im.resize((TARGET_W, h), Image.LANCZOS)
        im.save(os.path.join(OUT, f"{slug}.png"))

        bg = Image.new("RGBA", (im.width + 20, im.height + 20), (46, 107, 140, 255))
        bg.alpha_composite(im, (10, 10))
        bg.convert("RGB").save(f"/tmp/ship_{slug}_prev.png")
        print(f"  {slug}.png  {im.size}  ({name}, {country})")
        stubs.append(f'    {{ photo="{slug}", name="{name}", country="{country}", type="" }},')

    print("\n-- src/data/ships.lua stub --")
    print("\n".join(stubs))
    print("done ->", os.path.normpath(OUT))


if __name__ == "__main__":
    process()
