-- src/data/ships.lua
-- Real boats (photographed, stylized by tools/make_ships.py) that sail the sea as
-- ambient traffic. Click one in-game for a little MarineTraffic-style popup.
--
--   photo    basename in assets/ships_photos/<photo>.png (bow pointing right)
--   name     display name
--   country  Norwegian country name (drives the flag in src/ui/shipinfo.lua)
--   type     Norwegian vessel type, e.g. "Passasjerskip", "Lasteskip", "Ferje"
--   scale    OPTIONAL size multiplier (default 1). A given boat always renders at
--            this one size everywhere -- use it to make a small ferry smaller than
--            a big cruise ship (e.g. scale = 0.7). Different boats = different sizes;
--            the SAME boat is never shown bigger in one spot than another.
--
-- Add a boat: make a "<Name> - <Country> - sprite.png" (background removed),
-- run tools/make_ships.py, paste its stub here and fill in `type` (and `scale`).
-- Safe to edit by non-coders; F6 reloads it.

return {
    { photo = "aidaluna", name = "Aidaluna", country = "Tyskland", type = "Passasjerskip" },
}
