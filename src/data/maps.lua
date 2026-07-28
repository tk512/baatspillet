-- Every world the game can sail. A map is data: a seed, authored island anchors,
-- and which ports/ships files populate it. Worldgen is seeded, so an entry always
-- builds the same world. A paid pack is a new entry with its own product id and
-- state flag -- NOT the Kaptein-pakken `premium` flag.
-- Before a second real map ships: fog / discovered islands / treasures in the
-- save are global and must move under the map id, or exploration leaks between
-- worlds.
--   comingSoon  non-interactive teaser card in the selector
--   biome       per island, see config.BIOMES
--   remote      no countryside houses -- forest, rock and coast, no farms/roads

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
            { x = 9600, y = 2600, radius = 1960 },  -- Skiparviken (NE)
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
        -- Two continents split by a winding central strait, ~60% land: islands
        -- merge into landmasses and the narrow gaps between them read as fjords.
        islands = {
            -- west continent
            { x = 1600, y = 1300, radius = 2500, biome = "snow", remote = true },
            { x = 3700, y = 1000, radius = 1900, biome = "snow", remote = true },
            { x = 4900, y = 2100, radius = 1500 },
            { x = 1500, y = 3600, radius = 2000 },
            { x = 3300, y = 3300, radius = 1700 },
            { x = 2300, y = 5900, radius = 2400, biome = "desert" },  -- Los Angeles
            { x = 4500, y = 6600, radius = 1900, biome = "desert", remote = true },
            { x = 4700, y = 4900, radius = 1600, biome = "desert", remote = true },
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
            -- the strait: rocks you pass, not places you visit
            { x = 6100, y = 3900, radius = 1250, remote = true },     -- crossing waypoint
            { x = 6300, y = 300,  radius = 900, biome = "snow", remote = true }, -- arctic islet
        },
        ports = "src.data.ports_amerika",
        ships = "src.data.ships_amerika",
    },
}
