#!/usr/bin/env python3
"""Stylize real boat photos into ambient-ship billboards (like the Viking Sky).

Reads background-removed PNGs from INPUT_DIR named:

    "<Name> - <Country> - sprite.png"     e.g. "Aidaluna - Tyskland - sprite.png"

(the " - sprite" marks the cut-out version; originals without it are ignored).
Each is shot roughly side-on. The game wants the BOW POINTING RIGHT in
<slug>.png; photos shot bow-left go in BOW_LEFT below, and are mirrored to make
the right-facing sprite while the untouched original is saved as <slug>_left.png
(used when the ship sails screen-left, so hull text stays readable). A dedicated
photo of the other side, "<Name> - <Country> - sprite left.png" (or a hand-made
"... - sprite mirrored.png"), beats the mirror and becomes <slug>_left.png
directly. Without any left image the game just mirrors the right-facing sprite
at runtime.
Crops to the boat and shrinks to TARGET_W so it reads as chunky retro pixels under
the game's nearest filter.

Outputs:  assets/ships_photos/<slug>.png (+ <slug>_left.png)   (+ /tmp preview)
Also prints a src/data/ships.lua stub (name + country parsed from the filename;
fill in the `type` yourself, e.g. "Passasjerskip").

Run:  python3 tools/make_ships.py
"""
import os, glob, re, unicodedata
from PIL import Image

HERE = os.path.dirname(__file__)
INPUT_DIR = "/Users/tk/Desktop/skip"
OUT = os.path.join(HERE, "..", "assets", "ships_photos")
TARGET_W = 110            # sprite width in px. Kept AT/BELOW the on-screen width
                          # (config.AMBIENT_PHOTO_WIDTH = 115) so the nearest
                          # filter only ever UPSCALES: chunky stable game-sprite
                          # pixels, no downscale moire/shimmer when ships move.
COLORS = 64               # palette size: PNG-8, dithered -- posterized sprite look

# Slugs whose source photo has the bow pointing LEFT (accommodation aft-right).
# Beffen is a double-ended ferry, so its facing doesn't matter.
BOW_LEFT = {"aidaluna", "msc_santhya", "italeni", "vasiliy_golovnin",
            "hurtigruten_nordlys", "rem_inspektor"}


def slugify(name):
    # NFC first: macOS filenames arrive decomposed ("å" = "a" + ring), which
    # would slip past the replacements below and slug as "_".
    name = unicodedata.normalize("NFC", name).lower()
    for a, b in (("æ", "ae"), ("ø", "o"), ("å", "a")):
        name = name.replace(a, b)
    return re.sub(r"[^a-z0-9]+", "_", name).strip("_")


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

        def load(path):
            im = Image.open(path).convert("RGBA")
            bbox = im.getbbox()
            if bbox:
                im = im.crop(bbox)
            h = max(1, round(im.height * TARGET_W / im.width))
            return im.resize((TARGET_W, h), Image.LANCZOS)

        im = load(p)
        left = None
        for suffix in (" - sprite left.png", " - sprite mirrored.png"):
            left_src = p[:-len(" - sprite.png")] + suffix
            if os.path.exists(left_src):        # real photo / hand-made mirror
                left = load(left_src)
                break
        if slug in BOW_LEFT:                    # photo faces left: mirror for the
            left = left or im                   # right-facing sprite, keep the
            im = im.transpose(Image.FLIP_LEFT_RIGHT)  # original as the left view
        def save(img, path):
            q = img.quantize(colors=COLORS, method=Image.FASTOCTREE,
                             dither=Image.FLOYDSTEINBERG)
            q.save(path, optimize=True)

        save(im, os.path.join(OUT, f"{slug}.png"))
        if left:
            save(left, os.path.join(OUT, f"{slug}_left.png"))

        bg = Image.new("RGBA", (im.width + 20, im.height + 20), (46, 107, 140, 255))
        bg.alpha_composite(im, (10, 10))
        bg.convert("RGB").save(f"/tmp/ship_{slug}_prev.png")
        print(f"  {slug}.png  {im.size}  ({name}, {country})"
              + ("  + _left" if left else ""))
        stubs.append(f'    {{ photo="{slug}", name="{name}", country="{country}", type="" }},')

    print("\n-- src/data/ships.lua stub --")
    print("\n".join(stubs))
    print("done ->", os.path.normpath(OUT))


if __name__ == "__main__":
    process()
