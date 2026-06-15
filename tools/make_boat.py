#!/usr/bin/env python3
"""Turn two photos of the boy's boat into game sprites.

  Subject.png    bow-left  -> boats/boat1_left.png
  Subject 2.png  bow-right -> boats/boat1.png   (leveled by SUBJ2_ROTATE)

Crops to the boat and shrinks to TARGET_W; the small size reads as chunky pixels
under the game's nearest filter.

Run:  python3 tools/make_boat.py
"""
import os
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "boats")
TARGET_W = 300           # sprite width in px (smaller = more pixelized)
SUBJ2_ROTATE = 6.0       # degrees CCW to level Subject 2 (bow dips down-right)


def load_crop(path, rotate=0.0):
    im = Image.open(path).convert("RGBA")
    if rotate:
        im = im.rotate(rotate, expand=True, resample=Image.BICUBIC)
    bbox = im.getbbox()
    if bbox:
        im = im.crop(bbox)
    return im


def resize_w(im, w):
    h = max(1, round(im.height * w / im.width))
    return im.resize((w, h), Image.LANCZOS)


def process():
    left  = resize_w(load_crop("/Users/tk/Downloads/Subject.png"), TARGET_W)
    right = resize_w(load_crop("/Users/tk/Downloads/Subject 2.png", SUBJ2_ROTATE), TARGET_W)
    os.makedirs(OUT, exist_ok=True)
    left.save(os.path.join(OUT, "boat1_left.png"))
    right.save(os.path.join(OUT, "boat1.png"))
    print("boat1.png      (right)", right.size)
    print("boat1_left.png (left) ", left.size)
    return left, right


if __name__ == "__main__":
    left, right = process()
    # save previews on a water-blue background to /tmp for eyeballing
    for name, im in [("boat_right", right), ("boat_left", left)]:
        bg = Image.new("RGBA", (im.width + 20, im.height + 20), (79, 125, 153, 255))
        bg.alpha_composite(im, (10, 10))
        bg.convert("RGB").save(f"/tmp/{name}_prev.png")
