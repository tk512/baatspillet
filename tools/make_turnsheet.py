#!/usr/bin/env python3
# Import an 8-direction boat turnsheet (raw/bat-turnsheet.png) into game
# frames: assets/boats/<slug>/0..7.png.
#
# The sheet is a 4x3 grid: TOP, FRONT, BACK, LEFT / RIGHT, 45, 135, 225 / 315.
# Its "transparency" is a BAKED checkerboard (no alpha), and each cell has a
# baked label above the boat. Per cell we: cut the label band, flood-fill the
# checker from the edges into real alpha, crop to the boat, then apply the
# house style (pixelate + 32-colour Floyd-Steinberg dither, alpha kept crisp).
#
# Frame order matches Objects.drawBoatFrames screen-heading indices:
#   0=right 1=down-right 2=down(front) 3=down-left 4=left 5=up-left 6=up(back) 7=up-right
#
#   python3 tools/make_turnsheet.py
import os
from collections import deque
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "raw/bat-turnsheet.png")
SLUG = "nasse_noff"
OUT = os.path.join(ROOT, "assets/boats", SLUG)
TARGET_W = 192     # stored canvas width IN PIXELS — this IS the dither grid.
                   # iOS renders highdpi (a 140-unit sprite = 280 device px),
                   # so 192 stored px nearest-upscale ~1.5x: fine dither grain
                   # with real detail. Don't store larger than the on-screen
                   # device-pixel size — nearest DOWNscaling shreds the dither.
PAD_W = 1.55       # canvas width / hull length — the margin sizes the boat in
                   # BOTH the selector preview and gameplay (they scale by
                   # canvas width), so this is the one "how big" knob.

im = Image.open(SRC).convert("RGB")
W, H = im.size

# Band-ordered frame indices: after keying, content falls into horizontal
# bands (label band / boat band alternating — labels are skipped by taking
# only the TALL bands). Within each boat band, boats left→right:
#   band 1: TOP FRONT BACK LEFT   band 2: RIGHT 45 135 225   band 3: 315
# The sheet's numbered views are ALL stern-quarter renders (bow away):
# 45≈225=heading up-right, 135≈315=up-left. There are no bow-quarter views,
# so the down-diagonals (frames 1/3) reuse the side views below — the same
# trick the billboard photo-boats use for every diagonal.
BAND_FRAMES = [ [None, 2, 6, 4], [0, 7, 5, None], [None] ]

def key_cell(cell):
    """Flood the baked checkerboard from the edges into transparency."""
    c = cell.convert("RGBA")
    px = c.load()
    w, h = c.size
    # checker colours sampled from the corners (two shades of light grey)
    seeds = [px[1, 1][:3], px[w - 2, 1][:3], px[1, h - 2][:3], px[w - 2, h - 2][:3]]
    def is_checker(p):
        r, g, b = p[:3]
        if abs(r - g) > 14 or abs(g - b) > 14 or abs(r - b) > 14:
            return False                       # checker is neutral grey/white
        return any(abs(r - s[0]) + abs(g - s[1]) + abs(b - s[2]) < 60 for s in seeds) \
            or (r > 235 and g > 235 and b > 235)
    seen = [[False] * h for _ in range(w)]
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if not seen[x][y] and is_checker(px[x, y]):
                q.append((x, y)); seen[x][y] = True
    for y in range(h):
        for x in (0, w - 1):
            if not seen[x][y] and is_checker(px[x, y]):
                q.append((x, y)); seen[x][y] = True
    while q:
        x, y = q.popleft()
        px[x, y] = (0, 0, 0, 0)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not seen[nx][ny] and is_checker(px[nx, ny]):
                seen[nx][ny] = True
                q.append((nx, ny))
    return c

def house_style(frame):
    """Shrink to TARGET_W + dither (the Sierra look), alpha kept crisp.
    No upscale — the stored pixels ARE the chunky pixels."""
    w, h = frame.size
    gh = max(1, round(h * TARGET_W / w))
    small = frame.resize((TARGET_W, gh), Image.LANCZOS)
    rgb = small.convert("RGB").quantize(colors=32, dither=Image.Dither.FLOYDSTEINBERG).convert("RGB")
    alpha = small.split()[3].point(lambda a: 255 if a > 120 else 0)
    out = rgb.convert("RGBA")
    out.putalpha(alpha)
    return out

os.makedirs(OUT, exist_ok=True)

# 1) key the WHOLE sheet (checker background is one connected region)
keyed = key_cell(im)
kw, kh = keyed.size
kpx = keyed.load()

# 2) horizontal content bands (runs of rows containing any opaque pixel)
row_has = [any(kpx[x, y][3] > 0 for x in range(0, kw, 2)) for y in range(kh)]
bands, start = [], None
for y, h in enumerate(row_has + [False]):
    if h and start is None: start = y
    if not h and start is not None:
        bands.append((start, y)); start = None
boat_bands = [b for b in bands if b[1] - b[0] > 120]     # labels are short bands
assert len(boat_bands) == 3, f"expected 3 boat bands, got {len(boat_bands)}: {bands}"

crops = {}
for bi, (y0, y1) in enumerate(boat_bands):
    # 3) vertical runs of columns inside the band = individual boats
    col_has = [any(kpx[x, y][3] > 0 for y in range(y0, y1, 2)) for x in range(kw)]
    runs, s0 = [], None
    for x, h in enumerate(col_has + [False]):
        if h and s0 is None: s0 = x
        if not h and s0 is not None:
            if runs and s0 - runs[-1][1] < 20:           # bridge tiny gaps
                runs[-1] = (runs[-1][0], x)
            else:
                runs.append((s0, x))
            s0 = None
    runs = [r for r in runs if r[1] - r[0] > 60]
    frames = BAND_FRAMES[bi]
    assert len(runs) == len(frames), f"band {bi}: {len(runs)} boats vs {len(frames)} expected"
    for (x0, x1), idx in zip(runs, frames):
        if idx is None:
            continue
        boat = keyed.crop((x0, y0, x1, y1))
        crops[idx] = boat.crop(boat.getbbox())

# down-right / down-left have no source view: fake the bow-quarter by tilting
# the side profile toward the iso diagonal (bow dips ~16deg — reads as heading
# down-screen), then trimming the dipped bow's underside so it sits IN the
# water instead of showing red keel.
TILT = 26
def dive(side, sign):
    r = side.rotate(sign * -TILT, expand=True, resample=Image.BICUBIC)
    r = r.crop(r.getbbox())
    gain = r.size[1] - side.size[1]           # height added by the rotation
    r = r.crop((0, 0, r.size[0], r.size[1] - int(gain * 0.6)))
    return r.crop(r.getbbox())
crops[1] = dive(crops[0], +1)   # RIGHT view, bow down-right
crops[3] = dive(crops[4], -1)   # LEFT view, bow down-left

# All frames must share ONE canvas size (drawBoatFrames scales by frame width),
# and the sheet renders share a camera, so pasting without rescaling keeps the
# hull the same length in every view: centred x, bottom-aligned (waterline).
cw2 = int(max(c.size[0] for c in crops.values()) * PAD_W)
ch2 = max(c.size[1] for c in crops.values()) + 4
for idx, c in sorted(crops.items()):
    canvas = Image.new("RGBA", (cw2, ch2), (0, 0, 0, 0))
    canvas.paste(c, ((cw2 - c.size[0]) // 2, ch2 - 2 - c.size[1]))
    house_style(canvas).save(os.path.join(OUT, f"{idx}.png"))
print(f"wrote {len(crops)} frames ({cw2}x{ch2} src canvas -> {TARGET_W}px stored) -> {OUT}")
