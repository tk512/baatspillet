#!/usr/bin/env python3
"""Generate borderless 2:1 iso ground tiles for Båtspillet.

Each tile is a 64x32 diamond on a transparent background, with no outline so
tiles tessellate without drawing a grid. Detail fades out near the edges so
neighbours blend seamlessly. Subtle value-noise shading + sparse speckles.

Run:  python3 tools/gen_tiles.py
Out:  assets/tiles/{water,grass,sand,rock}.png
"""

import os
from PIL import Image

W, H = 64, 32
CX, CY = W / 2.0, H / 2.0          # diamond centre
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "tiles")

# Palette matches src/config.lua so PNGs blend with code-drawn parts.
WATER_TOP  = (79, 125, 153)
WATER_DEEP = (54, 94, 128)
WAVE       = (133, 163, 179)
GRASS_TOP  = (125, 140, 79)
GRASS_LIP  = (92, 107, 56)
GRASS_DOT  = (112, 128, 69)
SAND_TOP   = (194, 176, 125)
SAND_LIP   = (153, 135, 92)
SAND_DOT   = (179, 161, 112)
ROCK_TOP   = (143, 133, 115)
ROCK_LIP   = (107, 99, 84)
ROCK_DOT   = (130, 120, 105)


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def lighten(c, t):
    return mix(c, (255, 255, 255), t)


def rnd(x, y, salt=0):
    """Deterministic pseudo-random float in [0,1) from integer coords."""
    n = (x * 374761393 + y * 668265263 + salt * 362437) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFFFFFF) / 0xFFFFFFFF


def vnoise(x, y, scale, salt=0):
    """Smooth value noise (bilinear-interpolated lattice), returns [0,1)."""
    import math
    gx, gy = x / scale, y / scale
    x0, y0 = math.floor(gx), math.floor(gy)
    fx, fy = gx - x0, gy - y0
    sx = fx * fx * (3 - 2 * fx)
    sy = fy * fy * (3 - 2 * fy)
    n00 = rnd(x0, y0, salt);     n10 = rnd(x0 + 1, y0, salt)
    n01 = rnd(x0, y0 + 1, salt); n11 = rnd(x0 + 1, y0 + 1, salt)
    nx0 = n00 + (n10 - n00) * sx
    nx1 = n01 + (n11 - n01) * sx
    return nx0 + (nx1 - nx0) * sy


def diamond_t(x, y):
    """|dx|+|dy| in 0..1 inside the diamond, >1 outside (the see-through corners)."""
    dx = abs((x + 0.5 - CX) / CX)
    dy = abs((y + 0.5 - CY) / CY)
    return dx + dy


def edge_fade(t):
    """1 in the centre, easing to 0 within the outer ~30% so edges stay clean."""
    d = 1.0 - t                      # 0 at edge, 1 at centre
    return max(0.0, min(1.0, d / 0.30))


# Per-tile-type pixel shaders.
def shade_water(x, y, f):
    c = WATER_TOP
    depth = vnoise(x, y, 11, 1)                       # gentle depth blobs
    c = mix(c, WATER_DEEP, 0.16 * depth * f)
    shimmer = vnoise(x, y, 5, 2)
    if shimmer > 0.80:                                # faint ripple highlights
        c = mix(c, WAVE, 0.22 * f)
    return c


def shade_grass(x, y, f):
    c = GRASS_TOP
    patch = vnoise(x, y, 9, 1)
    c = mix(c, GRASS_LIP, 0.18 * patch * f)
    c = mix(c, lighten(GRASS_TOP, 0.18), 0.18 * (1 - patch) * f)
    r = rnd(x, y, 3)
    if r > 0.93:                                      # darker speckle (blades)
        c = mix(c, GRASS_DOT, 0.55 * f)
    elif r < 0.04:                                    # tiny bright fleck
        c = mix(c, lighten(GRASS_TOP, 0.30), 0.5 * f)
    return c


def shade_sand(x, y, f):
    c = SAND_TOP
    patch = vnoise(x, y, 10, 1)
    c = mix(c, SAND_LIP, 0.12 * patch * f)
    r = rnd(x, y, 4)
    if r > 0.90:                                      # grain
        c = mix(c, SAND_DOT, 0.5 * f)
    elif r < 0.06:
        c = mix(c, lighten(SAND_TOP, 0.22), 0.45 * f)
    return c


def shade_rock(x, y, f):
    c = ROCK_TOP
    patch = vnoise(x, y, 7, 1)
    c = mix(c, ROCK_DOT, 0.45 * patch * f)            # mottled stone
    crack = vnoise(x, y, 4, 9)
    if 0.47 < crack < 0.53:                           # thin darker cracks
        c = mix(c, ROCK_LIP, 0.6 * f)
    if patch > 0.72:                                  # catch-light on bumps
        c = mix(c, lighten(ROCK_TOP, 0.18), 0.5 * f)
    return c


SHADERS = {
    "water": shade_water,
    "grass": shade_grass,
    "sand":  shade_sand,
    "rock":  shade_rock,
}


def build(name, shader):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = img.load()
    for y in range(H):
        for x in range(W):
            t = diamond_t(x, y)
            if t <= 1.0:                              # inside the diamond
                f = edge_fade(t)
                r, g, b = shader(x, y, f)
                px[x, y] = (r, g, b, 255)
    out = os.path.join(OUT, name + ".png")
    img.save(out)
    return out


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, shader in SHADERS.items():
        print("wrote", build(name, shader))
