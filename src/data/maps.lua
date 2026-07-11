-- src/data/maps.lua
-- Every world the game can sail. A map is DATA: a seed plus authored island
-- anchors plus which ports/ships files populate it. Worldgen is seeded, so the
-- same entry always builds the exact same world — which is what makes maps
-- shippable (and sellable) as resources. A future paid pack ("Amerika",
-- "Asia"…) is a new entry here with its own ports/ships files and a product id
-- (own state flag, NOT the Kaptein-pakken `premium` flag).
--
-- NOTE before shipping a second real map: fog / discovered islands / treasures
-- in the save are currently global, not per-map — they must move under the map
-- id or switching maps will leak exploration between worlds.
--
-- `comingSoon = true` shows a non-interactive teaser card in the selector.

return {
    {
        id      = "norge",
        name    = "Norge",
        country = "Norge",   -- flag on the map card
        free    = true,
        seed    = 1337,
        islands = {
            { x = 2600, y = 2600, radius = 2520 },  -- Bergen   (huge, NW)
            { x = 6200, y = 2200, radius = 1540 },  -- Alversund (N-mid)
            { x = 9600, y = 2600, radius = 1960 },  -- Florø    (NE)
            { x = 7800, y = 4400, radius = 1260 },  -- Hjellestad (center-E)
            { x = 2600, y = 6000, radius = 1820 },  -- Lerøy    (SW)
            { x = 5200, y = 6200, radius = 1050 },  -- Klokkarvik (tiny, S-mid)
            { x = 10000,y = 6200, radius = 2520 },  -- Oslo     (huge, SE)
            { x = 5100, y = 4300, radius = 1260 },  -- Florida  (big, central sea)
        },
        ports = "src.data.ports",
        ships = "src.data.ships",
    },
    {
        id      = "amerika",
        name    = "Amerika",
        country = "Amerika",
        premium = true,      -- part of Kaptein-pakken (boats + Amerika)
        seed    = 8492,
        -- An archipelago America, west→east: snowy Alaska in the NW, desert
        -- southwest (Los Angeles), green plains mid, lush northeast (New York,
        -- Boston) and the green mid-Atlantic (Washington DC, Norfolk).
        islands = {
            { x = 2200, y = 1900, radius = 2400, biome = "snow" },    -- Alaska
            { x = 2900, y = 5700, radius = 2000, biome = "desert" },  -- Los Angeles
            { x = 4900, y = 6700, radius = 950,  biome = "desert" },  -- Mojave isle
            { x = 5800, y = 3600, radius = 1500 },                    -- the plains
            { x = 8600, y = 2700, radius = 1900, biome = "lush" },    -- New York
            { x = 10300, y = 1700, radius = 1400, biome = "lush" },   -- Boston
            { x = 9100, y = 5300, radius = 1600 },                    -- Washington DC
            { x = 10600, y = 6500, radius = 1000 },                   -- Norfolk
        },
        ports = "src.data.ports_amerika",
        ships = "src.data.ships_amerika",
    },
}
