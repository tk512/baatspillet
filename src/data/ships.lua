-- Ambient traffic: real boats, photographed and stylized by tools/make_ships.py.
-- Tap one in-game for a MarineTraffic-style popup. Safe to edit; F6 reloads.
--   photo      basename in assets/ships_photos/<photo>.png, bow pointing right
--   name       display name
--   country    Norwegian country name, drives the flag in src/ui/shipinfo.lua
--   type       Norwegian vessel type ("Passasjerskip", "Lasteskip", "Ferje"…)
--   scale      size multiplier (default 1); one boat is always the same size
--   cruise     sails a straight line, turning at land, instead of lying at anchor
--   home       port id: runs a two-stop ferry route around that harbour
--   visits     port ids: calls at an anchorage off each now and then
--   submarine  cruises invisible and unclickable, surfacing now and then
-- Add a boat: make "<Name> - <Country> - sprite.png" (background removed), run
-- tools/make_ships.py, paste its stub here, fill in `type` and `scale`.

return {
    { photo = "aidaluna", name = "Aidaluna", country = "Tyskland", type = "Passasjerskip", cruise = true, visits = { "bergen", "oslo" } },
    { photo = "beffen", name = "Beffen", country = "Norge", type = "Ferje", scale = 0.55, cruise = true, home = "bergen" },
    { photo = "italeni", name = "Italeni", country = "Sør-Afrika", type = "Arbeidsskip", cruise = true },
    { photo = "msc_santhya", name = "MSC Santhya", country = "Panama", type = "Containerskip", scale = 1.15, cruise = true },
    { photo = "vasiliy_golovnin", name = "Vasiliy Golovnin", country = "Sør-Afrika", type = "Isbryter", cruise = true },
    { photo = "hurtigruten_nordlys", name = "MS Nordlys", country = "Norge", type = "Hurtigruteskip", cruise = true, visits = { "bergen", "oslo" } },
    { photo = "rem_inspektor", name = "Rem Inspektør", country = "Norge", type = "Arbeidsskip", cruise = true },
    { photo = "norsk_ubat", name = "Norsk ubåt", country = "Norge", type = "Ubåt", cruise = true, submarine = true },
    -- leashed, no ferry route: the photo only reads well in one direction
    { photo = "hjellestad_politikammer", name = "Hjellestad Politikammer", country = "Norge", type = "Politibåt", scale = 0.9, cruise = true, home = "hjellestad", speed = 10, leashOnly = true, heading = -math.pi / 2 },
}
