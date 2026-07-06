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
--   cruise   OPTIONAL true = the boat sails slowly in a straight line instead of
--            lying at anchor; when land (or the world edge) blocks the way it
--            turns around and sails back the other way.
--   home     OPTIONAL port id (see ports.lua): the boat runs a little ferry
--            route around that harbour -- a stop just off the pier, a stop on
--            another part of the island, pausing at each (Beffen at Bergen).
--   visits   OPTIONAL list of port ids: every so often the boat steers to an
--            anchorage off one of these cities, lies still a while, then sails
--            on (the big liners calling at Bergen/Oslo).
--
-- Add a boat: make a "<Name> - <Country> - sprite.png" (background removed),
-- run tools/make_ships.py, paste its stub here and fill in `type` (and `scale`).
-- Safe to edit by non-coders; F6 reloads it.

return {
    { photo = "aidaluna", name = "Aidaluna", country = "Tyskland", type = "Passasjerskip", cruise = true, visits = { "bergen", "oslo" } },
    { photo = "beffen", name = "Beffen", country = "Norge", type = "Ferje", scale = 0.55, cruise = true, home = "bergen" },
    { photo = "italeni", name = "Italeni", country = "Sør-Afrika", type = "Arbeidsskip", cruise = true },
    { photo = "msc_santhya", name = "MSC Santhya", country = "Panama", type = "Containerskip", scale = 1.15, cruise = true },
    { photo = "vasiliy_golovnin", name = "Vasiliy Golovnin", country = "Sør-Afrika", type = "Isbryter", cruise = true },
    { photo = "hurtigruten_nordlys", name = "MS Nordlys", country = "Norge", type = "Hurtigruteskip", cruise = true, visits = { "bergen", "oslo" } },
}
