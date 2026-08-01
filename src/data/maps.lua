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
            { x = 5100, y = 4300, radius = 1260 },  -- Valhall  (big, central sea)
        },
        -- Four platforms. Norway is an oil nation and a rig on the horizon is as
        -- Norwegian as the fjord it is nowhere near.
        --
        -- The first pass asked for 520 of clearance and 1700 from any harbour,
        -- and both rigs went to the map's outer margins -- the far east past
        -- Oslo and the north-west corner -- where nobody sails. Norge's towns
        -- only span x 3500..9000, so "far from every harbour" and "far from the
        -- game" turned out to be the same place. These numbers still put them in
        -- open sea (400 clear is six boat-lengths of water on every side, and
        -- 1100 is a long way off a pier) while leaving them inside the water the
        -- player crosses. A rig you never meet may as well not be there.
        -- No buoys here; Amerika's harbours have those.
        -- Four platforms, at spots written down rather than found at load. Norway
        -- is an oil nation and a rig on the horizon is as Norwegian as the fjord
        -- it is nowhere near.
        --
        -- These ARE the positions, on every device and every launch. They were
        -- scattered once by the rules below, checked, and then frozen -- because
        -- a procedural spot moves the moment the terrain, a channel or a tuning
        -- number changes, and then every one has to be re-checked. Put a `rigs =
        -- <count>` back to re-scatter; in dev that prints a paste-ready list.
        sea   = { rigs = { { 7536, 6669 },   -- 1627u off Hjellestad, mid-map
                           { 1273,  551 },   -- 2480u off Frekhaug, NW
                           { 9552,  787 },   -- 2580u off Skiparviken, NE
                           { 1155, 6545 } }, -- 2531u off Lerøy, SW
                  rig = { clear = 400, fromPort = 1100, nearPort = 2600, apart = 1400 } },
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
            { x = 9800, y = 6200, radius = 1900 },                    -- Starbase, TX
            { x = 11300, y = 5600, radius = 1400, biome = "tropical" }, -- Miami: palm coast
            { x = 6900, y = 6500, radius = 1600 },
            -- the strait: rocks you pass, not places you visit
            { x = 6100, y = 3900, radius = 1250, remote = true },     -- crossing waypoint
            { x = 6300, y = 300,  radius = 900, biome = "snow", remote = true }, -- arctic islet
        },
        -- Sea furniture: oil rigs standing in open water, and buoyed harbour
        -- channels. Both maps get rigs -- Norge's are further out, see its `sea`
        -- above -- but the buoyed channels are Amerika's alone. Tuning: config.SEA.
        -- `clear` is relaxed from the 260 default because Amerika is 60% land:
        -- at 260 the only qualifying water was the big southern ocean, and all
        -- six rigs came out in a row along the bottom edge like a fence. 190
        -- lets them into the wider mid-map bays while still rejecting every
        -- carved channel (those sit at ~96 clearance), so the fairways stay
        -- clear. `apart` spreads them over the map rather than into one field.
        -- Frozen the same way as Norge's -- see the note there.
        sea   = { rigs = { { 9687, 2970 },   --  948u off New York
                           {  306, 6242 },   -- 2977u off Los Angeles, W edge
                           { 11686, 7798 },  -- 2870u off Miami, SE
                           { 4555, 3414 },   -- 2210u off Los Angeles, mid-map
                           { 7566, 7553 },   -- 2893u off Starbase, S
                           { 3300, 7500 } }, -- 1992u off Los Angeles, SW.
                                             -- Was (3776,7639), which stood on
                                             -- the chest at (3744,7840): 200u
                                             -- apart, so its bump circle made
                                             -- that treasure unreachable.
                  buoys = true,
                  rig = { clear = 190, nearPort = 3000, apart = 1800 } },
        -- Waterways forced open (config.CHANNELS). Every one was found by
        -- MEASURING, not by eye: the sea is split into BASINS of water with at
        -- least 56 units of clearance, and anything outside the basin the boat
        -- starts in is somewhere a five-year-old cannot steer to. A gap he can
        -- *just* thread is worse than none -- the auto-steer bounces off one
        -- shore, turns, bounces off the other, and ping-pongs there for ever.
        --
        -- Widths look generous because the carve runs on the 64-unit corner grid
        -- and a tile needs all four corners clear, so a band of W leaves roughly
        -- (W-128)/2 of real clearance. 300 buys ~90 -- four boat widths, which
        -- steers like open water.
        channels = {
            { 5330, 4060, 5620, 4700, 300 },   -- the middle strait, cactus island
                                               -- to the wooded one. Was 8u.
            { 8850, 5640, 8660, 5880, 300 },   -- a 7000-cell sea east of centre,
                                               -- sealed behind a 160u neck
            { 4240, 3950, 4500, 3730, 300 },   -- the west-central bay (205u neck)
            { 3920, 2400, 4260, 2840, 300 },   -- the north-west bay (413u neck)
            -- The east coast lane. Land ran flush to the map border all down the
            -- eastern side, which walled off two seas totalling 11,000 cells and
            -- meant there was no way round that side of the world at all. This
            -- shaves the coast inward rather than cutting a canal through it.
            { 11880, 300, 11880, 7600, 340 },
        },
        ports = "src.data.ports_amerika",
        ships = "src.data.ships_amerika",
    },
}
