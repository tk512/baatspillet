#!/usr/bin/env python3
"""Bake a 3D OBJ boat model into the game's iso turn frames — no Blender needed.

The 2D pipeline in tools/render_boat_frames.md describes doing this by hand in
Blender; this script is the automated equivalent for the flat-coloured low-poly
models asset sites hand out (no textures, just named materials). It parses the
OBJ, flat-shades each triangle from a per-material palette, projects through the
game's exact iso camera (orthographic, Blender-style X=60 deg / Z=45 deg), painter-
sorts, and writes N frames of a full turn:

    assets/boats/<name>/0.png ... (N-1).png

Frame convention (see Objects.drawBoatFrames): all frames the same size, boat
centred and sitting near the bottom, frame 0 = bow pointing screen-right,
turning clockwise. If a model's bow points elsewhere, fix it in data with
frameOffset / frameCW — no re-render needed.

Usage:
    python3 tools/render_boat_frames.py "path/to/model.obj" <boatname>
        [--frames 32] [--size 512] [--yaw0 DEG]

Materials the script doesn't know get a neutral grey and a warning — add them
to PALETTE below.
"""

import argparse
import math
import os
import sys

from PIL import Image, ImageDraw

# Per-material base colours (0-1 RGB). Names come from the OBJ's `usemtl` lines
# (the .mtl file itself is not needed). Extend as new models bring new names.
PALETTE = {
    "Wood":      (0.52, 0.36, 0.21),
    "DarkWood":  (0.34, 0.22, 0.13),
    "LightWood": (0.70, 0.53, 0.32),
    "Red":       (0.78, 0.20, 0.16),
    "White":     (0.93, 0.89, 0.79),
}
FALLBACK = (0.62, 0.60, 0.58)

# The game's iso camera as unit vectors (orthographic, Blender rot X=60, Z=45).
S45, C45 = math.sin(math.radians(45)), math.cos(math.radians(45))
S60, C60 = math.sin(math.radians(60)), math.cos(math.radians(60))
RIGHT = (C45, S45, 0.0)
UP    = (-C60 * S45, C60 * C45, S60)
FWD   = (-S60 * S45, S60 * C45, -C60)

LIGHT = (-0.35, 0.25, 0.90)          # fixed world sun, upper-left-ish
AMBIENT, DIFFUSE = 0.50, 0.55

SUPER = 2                            # supersampling factor for clean edges
MARGIN = 0.05                        # frame margin as a fraction of the size


def normalize(v):
    l = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]) or 1.0
    return (v[0] / l, v[1] / l, v[2] / l)


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def load_obj(path):
    """Return (verts, tris): verts as Z-up world points, tris as
    (i, j, k, material). OBJ files are Y-up (Blender export default), so
    (x, y, z) becomes world (x, -z, y). Polygons are fan-triangulated."""
    verts, tris, mtl = [], [], None
    unknown = set()
    for line in open(path):
        if line.startswith("v "):
            x, y, z = (float(t) for t in line.split()[1:4])
            verts.append((x, -z, y))
        elif line.startswith("usemtl"):
            mtl = line.split(None, 1)[1].strip()
            if mtl not in PALETTE:
                unknown.add(mtl)
        elif line.startswith("f "):
            idx = [int(t.split("/")[0]) - 1 for t in line.split()[1:]]
            for a in range(1, len(idx) - 1):
                tris.append((idx[0], idx[a], idx[a + 1], mtl))
    for m in sorted(unknown):
        print(f"  warning: material '{m}' not in PALETTE, using fallback grey")
    return verts, tris


def rotated(verts, yaw):
    s, c = math.sin(yaw), math.cos(yaw)
    return [(x * c - y * s, x * s + y * c, z) for x, y, z in verts]


def project(p):
    return dot(p, RIGHT), dot(p, UP)


def render(verts, tris, out_dir, n_frames, size, yaw0):
    light = normalize(LIGHT)

    # One shared framing for every frame: union of the projected bounds over
    # the whole turn, so the boat never jumps between frames.
    lo_u = lo_v = math.inf
    hi_u = hi_v = -math.inf
    for i in range(n_frames):
        for p in rotated(verts, yaw0 + 2 * math.pi * i / n_frames):
            u, v = project(p)
            lo_u, hi_u = min(lo_u, u), max(hi_u, u)
            lo_v, hi_v = min(lo_v, v), max(hi_v, v)

    canvas = size * SUPER
    avail = canvas * (1 - 2 * MARGIN)
    scale = min(avail / (hi_u - lo_u), avail / (hi_v - lo_v))
    cx = canvas / 2 - (lo_u + hi_u) / 2 * scale
    # Bottom-anchored (the game pins the frame's bottom-centre at the
    # waterline): lowest projected point sits just above the bottom margin.
    cy = canvas * (1 - MARGIN) + lo_v * scale

    os.makedirs(out_dir, exist_ok=True)
    for i in range(n_frames):
        world = rotated(verts, yaw0 + 2 * math.pi * i / n_frames)
        img = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
        draw = ImageDraw.Draw(img)

        faces = []
        for a, b, c, mtl in tris:
            pa, pb, pc = world[a], world[b], world[c]
            depth = dot(pa, FWD) + dot(pb, FWD) + dot(pc, FWD)
            faces.append((depth, pa, pb, pc, mtl))
        faces.sort(key=lambda f: f[0], reverse=True)   # painter: far first

        for _, pa, pb, pc, mtl in faces:
            e1 = (pb[0] - pa[0], pb[1] - pa[1], pb[2] - pa[2])
            e2 = (pc[0] - pa[0], pc[1] - pa[1], pc[2] - pa[2])
            n = normalize((e1[1] * e2[2] - e1[2] * e2[1],
                           e1[2] * e2[0] - e1[0] * e2[2],
                           e1[0] * e2[1] - e1[1] * e2[0]))
            if dot(n, FWD) > 0:                        # double-sided (the sail)
                n = (-n[0], -n[1], -n[2])
            shade = min(1.0, AMBIENT + DIFFUSE * max(0.0, dot(n, light)))
            base = PALETTE.get(mtl, FALLBACK)
            col = tuple(min(255, int(ch * shade * 255 + 0.5)) for ch in base)
            pts = []
            for p in (pa, pb, pc):
                u, v = project(p)
                pts.append((cx + u * scale, cy - v * scale))
            draw.polygon(pts, fill=col + (255,))

        img = img.resize((size, size), Image.LANCZOS)
        img.save(os.path.join(out_dir, f"{i}.png"))
    print(f"  wrote {n_frames} frames ({size}x{size}) to {out_dir}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("obj", help="path to the .obj model")
    ap.add_argument("name", help="boat name -> assets/boats/<name>/")
    ap.add_argument("--frames", type=int, default=32)
    ap.add_argument("--size", type=int, default=512)
    ap.add_argument("--yaw0", type=float, default=0.0,
                    help="base model rotation in degrees (frame 0 tweak)")
    args = ap.parse_args()

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(root, "assets", "boats", args.name)

    verts, tris = load_obj(os.path.expanduser(args.obj))
    print(f"{args.obj}: {len(verts)} verts, {len(tris)} tris")
    render(verts, tris, out_dir, args.frames, args.size,
           math.radians(args.yaw0))


if __name__ == "__main__":
    main()
