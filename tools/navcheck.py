#!/usr/bin/env python3
"""Which parts of the sea can a five-year-old actually sail to?

Run the game with BATNAV=1 first (World:dumpNavGrid writes navgrid.txt), then:

    BATNAV=1 love .            # any map; quit once the world has loaded
    python3 tools/navcheck.py  # [comfort-clearance, default 56]

Writes navcheck.png beside the repo: blue is the sea the boat can steer around,
every other colour is a body of water it cannot reach.

Water is split into BASINS: connected bodies with at least COMFORT clearance
from land. Anything outside the boat's own basin is somewhere he cannot get to
without threading a gap too tight to steer. For every stranded basin this also
finds the shortest carve that would join it to the main sea -- which is exactly
the channel to author in maps.lua.
"""
import os, sys, collections
import numpy as np
from PIL import Image, ImageDraw

PATH = os.path.expanduser("~/Library/Application Support/LOVE/batspillet/navgrid.txt")
OUT  = os.path.join(os.path.dirname(__file__), "..", "navcheck.png")
COMFORT = int(sys.argv[1]) if len(sys.argv) > 1 else 56
MIN_BASIN = 300                        # cells; smaller than this is a puddle

raw = open(PATH).read().split("\n")
nx, ny, step, bx, by = map(int, raw[0].split())
water = np.array([[c == "." for c in r] for r in raw[1:1+ny]], dtype=bool)

# clearance from land (and from the map border, which is equally unsailable)
INF = 10**9
dist = np.full(water.shape, INF, np.int32)
q = collections.deque()
for y, x in zip(*np.where(~water)):
    dist[y, x] = 0; q.append((y, x))
for x in range(nx):
    for y in (0, ny-1):
        if dist[y, x]: dist[y, x] = 0; q.append((y, x))
for y in range(ny):
    for x in (0, nx-1):
        if dist[y, x]: dist[y, x] = 0; q.append((y, x))
while q:
    y, x = q.popleft(); d = dist[y, x] + 1
    for dy, dx in ((1,0),(-1,0),(0,1),(0,-1)):
        a, b = y+dy, x+dx
        if 0 <= a < ny and 0 <= b < nx and dist[a, b] > d:
            dist[a, b] = d; q.append((a, b))
clear = dist * step

comfy = water & (clear >= COMFORT)
lab = np.zeros(comfy.shape, np.int32)
basins = []
N8 = ((1,0),(-1,0),(0,1),(0,-1),(1,1),(1,-1),(-1,1),(-1,-1))
n = 0
for y0, x0 in zip(*np.where(comfy)):
    if lab[y0, x0]: continue
    n += 1; st = [(y0, x0)]; lab[y0, x0] = n; cells = []
    while st:
        y, x = st.pop(); cells.append((y, x))
        for dy, dx in N8:
            a, b = y+dy, x+dx
            if 0 <= a < ny and 0 <= b < nx and comfy[a, b] and not lab[a, b]:
                lab[a, b] = n; st.append((a, b))
    basins.append(cells)

order = sorted(range(len(basins)), key=lambda i: -len(basins[i]))
byi, bxi = by // step, bx // step
home = lab[byi, bxi]
if home == 0:                                    # boat sits in a tight spot
    ys, xs = np.where(comfy)
    k = np.argmin((ys-byi)**2 + (xs-bxi)**2); home = lab[ys[k], xs[k]]

print(f"COMFORT >= {COMFORT}u   basins: {len(basins)}   boat is in basin {home}\n")
print(f"{'basin':>5} {'cells':>7}  {'centre':>15}  note")
big = [i for i in order if len(basins[i]) >= MIN_BASIN]
for i in big:
    cells = basins[i]
    cy = sum(c[0] for c in cells)/len(cells)*step
    cx = sum(c[1] for c in cells)/len(cells)*step
    tag = "<- the boat's sea" if (i+1) == home else "STRANDED"
    print(f"{i+1:>5} {len(cells):>7}  ({cx:6.0f},{cy:6.0f})  {tag}")

# --- ports: is every harbour in the boat's sea? ---
# Ports are drawn from maps.lua intent, not their snapped positions, and a
# harbour approach is shallow by design -- so this only marks them on the
# picture. Judge a harbour by looking, not by this list.
PORTS = {"los_angeles": (2700,5600), "new_york": (8500,3100), "boston": (9700,1300),
         "starbase": (9900,5900), "miami": (11400,5200)}

# --- for each stranded basin, the shortest carve back to the boat's sea ---
home_cells = np.array(basins[home-1])
print("\n-- shortest channel that would join each stranded basin to the main sea --")
for i in big:
    if (i+1) == home: continue
    cells = np.array(basins[i])
    # coarse nearest-pair: sample both sets, then refine
    a = cells[::max(1, len(cells)//1500)]
    b = home_cells[::max(1, len(home_cells)//1500)]
    d2 = ((a[:, None, 0]-b[None, :, 0])**2 + (a[:, None, 1]-b[None, :, 1])**2)
    ia, ib = np.unravel_index(np.argmin(d2), d2.shape)
    ay, ax = a[ia]; byy, bxx = b[ib]
    dist_u = (d2[ia, ib] ** 0.5) * step
    print(f"  basin {i+1:>3} ({len(cells):5d} cells): "
          f"{{ {ax*step:5.0f}, {ay*step:5.0f}, {bxx*step:5.0f}, {byy*step:5.0f}, ??? }}"
          f"   gap {dist_u:4.0f}u")

# --- picture ---
px = np.zeros((ny, nx, 3), np.uint8)
px[~water] = (74, 104, 62)
px[water] = (26, 52, 84)
palette = [(52,120,180),(230,150,40),(200,80,190),(240,220,60),(80,220,200),(240,120,120)]
for k, i in enumerate(big):
    col = (52,120,180) if (i+1) == home else palette[1 + k % (len(palette)-1)]
    for y, x in basins[i]: px[y, x] = col
im = Image.fromarray(np.repeat(np.repeat(px, 2, 0), 2, 1))
d = ImageDraw.Draw(im)
for wx in range(0, nx*step, 1000):
    d.line([wx/step*2,0,wx/step*2,im.height], fill=(255,255,255)); d.text((wx/step*2+2,2), str(wx), fill=(255,255,140))
for wy in range(0, ny*step, 1000):
    d.line([0,wy/step*2,im.width,wy/step*2], fill=(255,255,255)); d.text((2,wy/step*2+2), str(wy), fill=(255,255,140))
for name,(pxx,pyy) in PORTS.items():
    d.ellipse([pxx/step*2-5,pyy/step*2-5,pxx/step*2+5,pyy/step*2+5], fill=(255,255,255))
    d.text((pxx/step*2+7,pyy/step*2-6), name, fill=(255,255,255))
d.ellipse([bx/step*2-7,by/step*2-7,bx/step*2+7,by/step*2+7], outline=(0,0,0), width=3)
im.save(OUT)
print("\nblue = the boat's sea; every other colour is a stranded basin")
