# Assets — how to drop in a free CC0 isometric pixel pack

The game runs **with no images at all** (it draws code placeholders). To get the
SimCity-2000 pixel look, drop in a **CC0-licensed** isometric pixel pack. The
ground is now a **flat** iso tilemap, so flat tile sprites map cleanly.

## Recommended free packs (CC0 — free for any use, no attribution)

- Isometric Pixel Terrain — https://opengameart.org/content/isometric-pixel-terrain
- Grass and Water Tiles (incl. coast banks) — https://opengameart.org/content/grass-and-water-tiles
- Isometric road tiles (+ trees, "SimCity-style") — https://opengameart.org/content/isometric-road-tiles
- Kenney Isometric Landscape / Buildings (cleaner) — https://kenney.nl/assets/isometric-landscape

Download the `.zip`/`.7z`, unpack it, and copy the PNGs to the names below.
(I can't download these for you — they're binary bundles — but the engine
auto-loads them the moment they're in place.)

## Where the files go

### Ground tiles — `assets/tiles/`  (one flat iso diamond each)
| File         | Used for                          |
|--------------|-----------------------------------|
| `water.png`  | open sea (and shallows)           |
| `sand.png`   | beaches / coastline tiles         |
| `grass.png`  | grassland                          |
| `rock.png`   | rocky ground                       |

Each is scaled to the tile and centered. For a 1:1 match set `config.TILE` to
the pack's tile width (e.g. 64). If a file is missing, that tile uses the
textured code fallback, so you can add them one at a time.

### Objects — `assets/props/`, `assets/ports/`, `assets/boats/`
| File                     | Used for                | Footprint |
|--------------------------|-------------------------|-----------|
| `props/tree.png`         | a single tree           | 1×1       |
| `props/rock.png`         | a rock                  | 1×1       |
| `ports/<portId>.png`     | a harbor (e.g. `solhavn.png`) | 4×4 |
| `boats/boat1.png` …      | the boat (`sprite` in `data/boats.lua`) | billboard |

Object PNGs are scaled to cover their footprint's diamond width and anchored
bottom-center on the ground, so tall art rises upward correctly.

## After you add the files

Tell me and I'll do the "make it fit" pass with the real images in hand:
- read each PNG's true size and set `config.TILE` / per-sprite scale + anchor,
- wire **autotiled coastlines** (concave/convex bank tiles) instead of the
  current curvy-polygon fallback,
- slice any sprite **sheets** into the individual files above.

Sound effects + music are still generated in code — no audio files needed.
