# Credits

## Ship sprites — OpenGFX

The ambient sea-traffic ships (`assets/ships/<name>/0..7.png`) are extracted from
**OpenGFX**, the free base graphics set for OpenTTD.

- Source: https://github.com/OpenTTD/OpenGFX
- License: **GNU General Public License v2.0**
- Extracted with `tools/extract_opengfx_ships.py` (8 dimetric views per ship, blue
  background keyed to transparent, draw-offsets baked to a common pivot).

The forest trees (`assets/props/trees/*.png`) come from the same OpenGFX set,
extracted with `tools/extract_opengfx_trees.py` (the fully-grown growth stage of
each tree, blue background keyed to transparent). Norway mix: green arctic
conifers, snowy conifers near the treeline, and two bushy temperate leaf trees.

The town houses (`assets/props/houses/*.png`) are small Scandinavian-style
cottages from OpenGFX's `towns02` set, extracted with
`tools/extract_opengfx_houses.py` (full-tile boxes, blue background keyed out).

Landmarks + town blocks (`assets/props/church.png`, `lighthouse.png`,
`fountain.png`, `park.png`, `blocks/*.png`) are from OpenGFX too, extracted with
`tools/extract_opengfx_props.py`: an arctic church, a coastal lighthouse, a
fountain and park for town squares, and low apartment blocks for bigger towns.

The Klokkarvik nuclear power plant (`assets/props/powerplant.png`) is a GPL
power-plant sprite from another open-source game, baked to retro size by
`tools/make_powerplant.py`.

OpenGFX is GPLv2; if this game is ever distributed publicly, that obligation
travels with these sprites (attribution + offer of source). For private/family
use this note is courtesy attribution.
