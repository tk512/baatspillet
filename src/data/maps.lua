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
        -- TWO CONTINENTS split by a winding central strait, ~60% land:
        -- overlapping islands merge into landmasses, and the narrow gaps
        -- between them become FJORDS. West: snowy Alaska shelf → green Pacific
        -- coast → desert southwest. East: lush northeast → green mid-Atlantic
        -- and south. A mid-strait island is the crossing waypoint, and an
        -- arctic islet guards the northern passage.
        islands = {
            -- west continent
            { x = 1600, y = 1300, radius = 2500, biome = "snow" },
            { x = 3700, y = 1000, radius = 1900, biome = "snow" },
            { x = 4900, y = 2100, radius = 1500 },
            { x = 1500, y = 3600, radius = 2000 },
            { x = 3300, y = 3300, radius = 1700 },
            { x = 2300, y = 5900, radius = 2400, biome = "desert" },  -- Los Angeles
            { x = 4500, y = 6600, radius = 1900, biome = "desert" },
            { x = 4700, y = 4900, radius = 1600, biome = "desert" },
            -- east continent
            { x = 7600, y = 1200, radius = 2000, biome = "lush" },
            { x = 9500, y = 1000, radius = 1900, biome = "lush" },    -- Boston
            { x = 11000, y = 2200, radius = 1700, biome = "lush" },
            { x = 8300, y = 2900, radius = 1800, biome = "lush" },    -- New York
            { x = 10300, y = 4000, radius = 1800 },
            { x = 8000, y = 5000, radius = 1800 },
            { x = 9800, y = 6200, radius = 1900 },                    -- Washington DC
            { x = 11300, y = 5600, radius = 1400 },                   -- Norfolk
            { x = 6900, y = 6500, radius = 1600 },
            -- the strait
            { x = 6100, y = 3900, radius = 1250 },                    -- crossing waypoint
            { x = 6300, y = 300,  radius = 900, biome = "snow" },     -- arctic islet
        },
        ports = "src.data.ports_amerika",
        ships = "src.data.ships_amerika",
    },
}
